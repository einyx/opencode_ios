import Foundation
#if os(iOS)
import AVFoundation
#endif

nonisolated enum CarLiveAudioError: Error, Equatable, Sendable {
    case unavailable
    case failed
}

nonisolated struct CarLiveCaptureHandle: Sendable {
    var generation: UInt64
    var frames: AsyncStream<Data>
    var finish: @Sendable () -> Void
}

nonisolated protocol CarLiveAudioEngine: Sendable {
    func requestRecordPermission() async -> Bool
    func startCapture() async throws -> CarLiveCaptureHandle
    func stopCapture(generation: UInt64) async
    func setMuted(_ muted: Bool)
    func enqueuePlayback(_ pcm: Data)
    func clearPlayback()
    func setPlaybackHeld(_ held: Bool)
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?)
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?)
    func setFailureHandler(_ handler: (@Sendable (String) -> Void)?)
}

extension CarLiveAudioEngine {
    func setPlaybackHeld(_ held: Bool) {}
    func setFailureHandler(_ handler: (@Sendable (String) -> Void)?) {}
}

nonisolated enum CarLiveAudioRoute {
    static func usesVoiceProcessing(portTypes: [String]) -> Bool {
        if portTypes.contains(where: isHeadset) { return false }
        return portTypes.contains(where: isSpeaker)
    }

    static func isHeadset(_ port: String) -> Bool {
        ["Headphones", "HeadsetMic", "MicrophoneWired", "BluetoothHFP", "BluetoothA2DP", "BluetoothLE"].contains(port)
    }

    static func isSpeaker(_ port: String) -> Bool {
        ["Speaker", "Receiver", "BuiltInSpeaker", "BuiltInReceiver"].contains(port)
    }
}

nonisolated struct CarLiveCaptureGate: Equatable, Sendable {
    var generation: UInt64 = 0
    var playbackGeneration: UInt64 = 0
    var accepting = false
    var scheduledPlayback = 0
    private var finished = false

    mutating func open() -> UInt64 {
        generation &+= 1
        accepting = true
        finished = false
        return generation
    }

    mutating func finishStream() {
        finished = true
        accepting = false
    }

    func accepts(_ token: UInt64) -> Bool {
        accepting && !finished && token == generation
    }

    mutating func clearPlayback() {
        playbackGeneration &+= 1
        scheduledPlayback = 0
    }

    mutating func noteScheduled(token: UInt64) -> Bool {
        guard playbackGeneration == token else { return false }
        scheduledPlayback += 1
        return true
    }

    mutating func finishScheduled(token: UInt64, stagingEmpty: Bool) -> Bool? {
        guard playbackGeneration == token else { return nil }
        scheduledPlayback = max(0, scheduledPlayback - 1)
        return stagingEmpty && scheduledPlayback == 0
    }
}

nonisolated struct CarLiveLevelGate: Equatable, Sendable {
    var lastAt: TimeInterval = -.greatestFiniteMagnitude
    var interval: TimeInterval = 0.1

    mutating func allow(now: TimeInterval) -> Bool {
        guard now - lastAt >= interval else { return false }
        lastAt = now
        return true
    }
}

nonisolated final class CarLiveFrameStream: @unchecked Sendable {
    let generation: UInt64
    let frames: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private var finished = false

    init(generation: UInt64, bound: Int = 16) {
        self.generation = generation
        var captured: AsyncStream<Data>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(bound)) { captured = $0 }
        continuation = captured
    }

    func yield(_ data: Data, generation token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, token == generation, data.count >= 2, data.count % 2 == 0 else { return false }
        continuation.yield(data)
        return true
    }

    func finish() {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        if !already { continuation.finish() }
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

nonisolated enum CarLiveAudioEngines {
    static func makeDefault() -> any CarLiveAudioEngine {
        #if os(iOS)
        return CarLiveIOSAudioEngine()
        #else
        return CarLiveUnavailableAudioEngine()
        #endif
    }
}

nonisolated final class CarLiveUnavailableAudioEngine: CarLiveAudioEngine, @unchecked Sendable {
    func requestRecordPermission() async -> Bool { false }

    func startCapture() async throws -> CarLiveCaptureHandle {
        throw CarLiveAudioError.unavailable
    }

    func stopCapture(generation: UInt64) async {}
    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setPlaybackHeld(_ held: Bool) {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}
}

#if os(iOS)
nonisolated final class CarLiveIOSAudioEngine: CarLiveAudioEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "com.grapeot.OpenCodeClient.carlive.audio")
    private let lock = NSLock()
    private var gate = CarLiveCaptureGate()
    private var levelGate = CarLiveLevelGate()
    private var outputLevelGate = CarLiveLevelGate()
    private var stream: CarLiveFrameStream?
    private var muted = false
    private var tapInstalled = false
    private var inputConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private var playbackFormat: AVAudioFormat?
    private var playback = Data()
    private var playbackHeld = false
    private var observers: [NSObjectProtocol] = []
    private var recoveryStarts = 0
    private var intendedRunning = false
    private var levelHandler: (@Sendable (Double, Double) -> Void)?
    private var idleHandler: (@Sendable () -> Void)?
    private var failureHandler: (@Sendable (String) -> Void)?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)

    func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startCapture() async throws -> CarLiveCaptureHandle {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
            do {
                let handle = try self.startOnQueue()
                continuation.resume(returning: handle)
            } catch {
                self.stopOnQueue()
                continuation.resume(throwing: error)
            }
            }
        }
    }

    func stopCapture(generation: UInt64) async {
        await withCheckedContinuation { continuation in
            queue.async {
                let current = self.locked { self.gate.generation }
                if current == generation {
                    self.stopOnQueue()
                }
                continuation.resume()
            }
        }
    }

    func setMuted(_ muted: Bool) {
        lock.lock()
        self.muted = muted
        lock.unlock()
    }

    func enqueuePlayback(_ pcm: Data) {
        let even = pcm.count - pcm.count % 2
        guard even >= 2 else { return }
        let accepted = locked { () -> Bool in
            guard !playbackHeld else { return false }
            playback.append(pcm.prefix(even))
            if playback.count > 480_000 { playback.removeFirst(playback.count - 480_000) }
            return true
        }
        guard accepted else { return }
        queue.async { self.scheduleOnQueue() }
    }

    func clearPlayback() {
        queue.async { self.clearPlaybackOnQueue() }
    }

    func setPlaybackHeld(_ held: Bool) {
        let shouldClear = locked { () -> Bool in
            let changed = playbackHeld != held
            playbackHeld = held
            return held && changed
        }
        if shouldClear { clearPlayback() }
    }

    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {
        lock.lock()
        levelHandler = handler
        lock.unlock()
    }

    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        idleHandler = handler
        lock.unlock()
    }

    func setFailureHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.lock()
        failureHandler = handler
        lock.unlock()
    }

    private func startOnQueue() throws -> CarLiveCaptureHandle {
        if intendedRunning { stopOnQueue() }
        installObserversOnQueue()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        var ports = routePorts(session)
        if ports.isEmpty {
            try session.setActive(true)
            ports = routePorts(session)
        }
        let voiceProcessing = CarLiveAudioRoute.usesVoiceProcessing(portTypes: ports)
        if engine.isRunning { engine.stop() }
        try applyVoiceProcessing(voiceProcessing)
        try session.setActive(true)
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard let targetFormat, inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              outputFormat.sampleRate > 0, outputFormat.channelCount > 0,
              let inputConverter = AVAudioConverter(from: inputFormat, to: targetFormat),
              let connectFormat = AVAudioFormat(standardFormatWithSampleRate: outputFormat.sampleRate, channels: outputFormat.channelCount),
              let playbackConverter = AVAudioConverter(from: targetFormat, to: connectFormat) else {
            throw CarLiveAudioError.failed
        }
        self.inputConverter = inputConverter
        self.playbackConverter = playbackConverter
        self.playbackFormat = connectFormat
        let token = locked {
            recoveryStarts = 0
            intendedRunning = true
            playbackHeld = false
            playback.removeAll()
            return gate.open()
        }
        let opened = CarLiveFrameStream(generation: token)
        locked { stream = opened }
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: connectFormat)
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInput(buffer, converter: inputConverter, target: targetFormat, generation: token)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        player.play()
        return CarLiveCaptureHandle(generation: token, frames: opened.frames) { [weak opened] in
            opened?.finish()
        }
    }

    private func stopOnQueue() {
        let opened = locked { () -> CarLiveFrameStream? in
            intendedRunning = false
            playbackHeld = false
            gate.finishStream()
            gate.clearPlayback()
            playback.removeAll()
            let current = stream
            stream = nil
            return current
        }
        opened?.finish()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        if engine.isRunning { engine.stop() }
        if engine.attachedNodes.contains(player) { engine.detach(player) }
        inputConverter = nil
        playbackConverter = nil
        playbackFormat = nil
        removeObserversOnQueue()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func clearPlaybackOnQueue() {
        let running = locked { () -> Bool in
            playback.removeAll()
            gate.clearPlayback()
            return intendedRunning
        }
        guard running else { return }
        player.stop()
        player.play()
    }

    private func handleInput(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat, generation: UInt64) {
        let accepted = locked { gate.accepts(generation) }
        guard accepted, let pcm = convertToPCM16(buffer, converter: converter, target: target) else { return }
        let muted = locked { self.muted }
        let evenCount = pcm.count - pcm.count % 2
        guard evenCount >= 2 else { return }
        let frame = muted ? CarLivePCM.silence(byteCount: evenCount) : Data(pcm.prefix(evenCount))
        let opened = locked { stream }
        _ = opened?.yield(frame, generation: generation)
        let now = ProcessInfo.processInfo.systemUptime
        let publish = locked { levelGate.allow(now: now) }
        guard publish else { return }
        let handler = locked { levelHandler }
        handler?(CarLivePCM.rms(frame), 0)
    }

    private func scheduleOnQueue() {
        guard locked({ intendedRunning && !playbackHeld }), let playbackFormat, let playbackConverter else { return }
        let playbackToken = locked { gate.playbackGeneration }
        while true {
            let slice: Data? = locked {
                guard gate.playbackGeneration == playbackToken, playback.count >= 2 else { return nil }
                let count = min(4800, playback.count - playback.count % 2)
                let piece = Data(playback.prefix(count))
                playback.removeFirst(count)
                return piece
            }
            guard let slice, let buffer = floatBuffer(from: slice, format: playbackFormat, converter: playbackConverter) else { return }
            let admitted = locked { gate.noteScheduled(token: playbackToken) }
            guard admitted else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if locked({ outputLevelGate.allow(now: now) }) {
                let handler = locked { levelHandler }
                handler?(0, CarLivePCM.rms(slice))
            }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.queue.async { self?.finishSlice(playback: playbackToken) }
            }
        }
    }

    private func finishSlice(playback token: UInt64) {
        let idle = locked { gate.finishScheduled(token: token, stagingEmpty: playback.isEmpty) }
        guard let idle else { return }
        if idle {
            let handler = locked { idleHandler }
            handler?()
        } else {
            scheduleOnQueue()
        }
    }

    private func applyVoiceProcessing(_ enabled: Bool) throws {
        if enabled {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            if engine.outputNode.isVoiceProcessingEnabled == false {
                try engine.outputNode.setVoiceProcessingEnabled(true)
            }
        } else if engine.inputNode.isVoiceProcessingEnabled {
            try engine.inputNode.setVoiceProcessingEnabled(false)
        }
    }

    private func installObserversOnQueue() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: Notification.Name("AVAudioEngineConfigurationChangeNotification"), object: engine, queue: nil) { [weak self] _ in
            self?.queue.async { self?.recoverOnceOnQueue() }
        })
    }

    private func removeObserversOnQueue() {
        let center = NotificationCenter.default
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func recoverOnceOnQueue() {
        let snapshot = locked { () -> (Bool, Int, UInt64) in
            (intendedRunning && gate.accepts(gate.generation), recoveryStarts, gate.generation)
        }
        guard snapshot.0, snapshot.1 == 0, engine.isRunning == false else { return }
        locked { recoveryStarts += 1 }
        do {
            try rebuildInputChainOnQueue(generation: snapshot.2)
        } catch {
            failCaptureOnQueue()
        }
    }

    private func rebuildInputChainOnQueue(generation: UInt64) throws {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        guard let targetFormat,
              inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              outputFormat.sampleRate > 0, outputFormat.channelCount > 0,
              let inputConverter = AVAudioConverter(from: inputFormat, to: targetFormat),
              let connectFormat = AVAudioFormat(standardFormatWithSampleRate: outputFormat.sampleRate, channels: outputFormat.channelCount),
              let playbackConverter = AVAudioConverter(from: targetFormat, to: connectFormat) else {
            throw CarLiveAudioError.failed
        }
        self.inputConverter = inputConverter
        self.playbackConverter = playbackConverter
        self.playbackFormat = connectFormat
        if engine.attachedNodes.contains(player) == false {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: connectFormat)
        engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInput(buffer, converter: inputConverter, target: targetFormat, generation: generation)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        player.play()
    }

    private func failCaptureOnQueue() {
        let opened = locked { () -> CarLiveFrameStream? in
            intendedRunning = false
            playbackHeld = false
            gate.finishStream()
            gate.clearPlayback()
            playback.removeAll()
            let current = stream
            stream = nil
            return current
        }
        opened?.finish()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        if engine.isRunning { engine.stop() }
        let handler = locked { failureHandler }
        handler?("audio_recovery_failed")
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func routePorts(_ session: AVAudioSession) -> [String] {
        session.currentRoute.inputs.map(\.portType.rawValue) + session.currentRoute.outputs.map(\.portType.rawValue)
    }

    private func convertToPCM16(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, target: AVAudioFormat) -> Data? {
        let ratio = target.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: max(capacity, 1)) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, output.frameLength > 0, let channel = output.int16ChannelData?.pointee else { return nil }
        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    private func floatBuffer(from pcm: Data, format: AVAudioFormat, converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let sourceFormat = targetFormat else { return nil }
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames) else { return nil }
        source.frameLength = frames
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let destination = source.int16ChannelData?.pointee else { return }
            destination.update(from: base.assumingMemoryBound(to: Int16.self), count: Int(frames))
        }
        let ratio = format.sampleRate / 24_000
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return source
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

#endif
