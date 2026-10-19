import Foundation
#if os(iOS) || os(watchOS)
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
    var startsBeforeConnection: Bool { get }
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
    func setHoldHandler(_ handler: (@Sendable (BackgroundVoiceHoldKind, UInt64) -> Void)?)
}

extension CarLiveAudioEngine {
    var startsBeforeConnection: Bool { false }
    func setPlaybackHeld(_ held: Bool) {}
    func setFailureHandler(_ handler: (@Sendable (String) -> Void)?) {}
    func setHoldHandler(_ handler: (@Sendable (BackgroundVoiceHoldKind, UInt64) -> Void)?) {}
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

    /// Previous-route ports whose `oldDeviceUnavailable` must end Live.
    /// Personal headsets stay here. USB, AirPlay, and car output are included
    /// without joining `isHeadset`, which still selects voice processing.
    static func isExternalOutputDisconnect(_ port: String) -> Bool {
        if isHeadset(port) { return true }
        return ["USBAudio", "AirPlay", "CarAudio"].contains(port)
    }

    static func closesForExternalOutputDisconnect(oldDeviceUnavailable: Bool, previousPorts: [String]) -> Bool {
        oldDeviceUnavailable && previousPorts.contains(where: isExternalOutputDisconnect)
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

nonisolated struct CarLivePlaybackRestart: Equatable, Sendable {
    var queuedCapture: UInt64
    var currentCapture: UInt64
    var queuedPlayback: UInt64
    var currentPlayback: UInt64
    var intendedRunning: Bool
    var engineRunning: Bool
    var playerAttached: Bool
    var hasAudio: Bool

    var ownsQueuedClear: Bool {
        intendedRunning && queuedCapture == currentCapture && queuedPlayback == currentPlayback
    }

    var shouldRestartFromClear: Bool { false }

    var shouldPlayScheduled: Bool {
        ownsQueuedClear && engineRunning && playerAttached && hasAudio
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
        #if os(iOS) || os(watchOS)
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

#if os(iOS) || os(watchOS)
nonisolated final class CarLiveIOSAudioEngine: CarLiveAudioEngine, @unchecked Sendable {
    var startsBeforeConnection: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }
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
    private var acceptSessionEvents = false
    private var audioHold: BackgroundVoiceHoldKind?
    private var holdHandler: (@Sendable (BackgroundVoiceHoldKind, UInt64) -> Void)?
    private var levelHandler: (@Sendable (Double, Double) -> Void)?
    private var idleHandler: (@Sendable () -> Void)?
    private var failureHandler: (@Sendable (String) -> Void)?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)

    func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startCapture() async throws -> CarLiveCaptureHandle {
        #if os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
        guard try await session.activate(options: []) else { throw CarLiveAudioError.failed }
        #endif
        return try await withCheckedThrowingContinuation { continuation in
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
        let token = locked { (gate.generation, gate.playbackGeneration) }
        queue.async { self.clearPlaybackOnQueue(capture: token.0, playback: token.1) }
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

    func setHoldHandler(_ handler: (@Sendable (BackgroundVoiceHoldKind, UInt64) -> Void)?) {
        lock.lock()
        holdHandler = handler
        lock.unlock()
    }

    private func startOnQueue() throws -> CarLiveCaptureHandle {
        if intendedRunning { stopOnQueue() }
        installObserversOnQueue()
        acceptSessionEvents = true
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: Self.categoryOptions())
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        #endif
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
            audioHold = nil
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
        return CarLiveCaptureHandle(generation: token, frames: opened.frames) { [weak opened] in
            opened?.finish()
        }
    }

    private func stopOnQueue() {
        acceptSessionEvents = false
        let opened = locked { () -> CarLiveFrameStream? in
            intendedRunning = false
            audioHold = nil
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

    private func clearPlaybackOnQueue(capture: UInt64, playback token: UInt64) {
        let decision = locked { () -> CarLivePlaybackRestart in
            let restart = CarLivePlaybackRestart(
                queuedCapture: capture,
                currentCapture: gate.generation,
                queuedPlayback: token,
                currentPlayback: gate.playbackGeneration,
                intendedRunning: intendedRunning,
                engineRunning: engine.isRunning,
                playerAttached: engine.attachedNodes.contains(player),
                hasAudio: false
            )
            if restart.ownsQueuedClear {
                playback.removeAll()
                gate.clearPlayback()
            }
            return restart
        }
        guard decision.ownsQueuedClear else {
            notePlayback(CarLiveLifecycleKind.playbackSkipPlay, decision)
            return
        }
        if decision.playerAttached {
            player.stop()
        }
        notePlayback(CarLiveLifecycleKind.playbackSkipPlay, decision)
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
        let owned = locked { (gate.generation, gate.playbackGeneration) }
        let playbackToken = owned.1
        while true {
            let slice: Data? = locked {
                guard gate.generation == owned.0, gate.playbackGeneration == playbackToken, playback.count >= 2 else { return nil }
                let count = min(4800, playback.count - playback.count % 2)
                let piece = Data(playback.prefix(count))
                playback.removeFirst(count)
                return piece
            }
            guard let slice, let buffer = floatBuffer(from: slice, format: playbackFormat, converter: playbackConverter) else { return }
            let decision = locked {
                CarLivePlaybackRestart(
                    queuedCapture: owned.0,
                    currentCapture: gate.generation,
                    queuedPlayback: playbackToken,
                    currentPlayback: gate.playbackGeneration,
                    intendedRunning: intendedRunning && !playbackHeld,
                    engineRunning: engine.isRunning,
                    playerAttached: engine.attachedNodes.contains(player),
                    hasAudio: true
                )
            }
            let held = locked { audioHold != nil }
            guard !held, decision.shouldPlayScheduled, engine.isRunning, engine.attachedNodes.contains(player) else { return }
            let admitted = locked { gate.noteScheduled(token: playbackToken) }
            guard admitted, engine.isRunning, engine.attachedNodes.contains(player) else { return }
            player.play()
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
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: Notification.Name("AVAudioEngineConfigurationChangeNotification"), object: engine, queue: nil) { [weak self] _ in
            self?.queue.async { self?.recoverOnceOnQueue() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? -1
            let previous = Self.previousPorts(note)
            let unavailable = reason == Int(AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
            let generation = self?.currentGeneration() ?? 0
            self?.queue.async {
                self?.handleRouteOnQueue(oldDeviceUnavailable: unavailable, previousPorts: previous, eventGeneration: generation)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
            let began = type == AVAudioSession.InterruptionType.began.rawValue
            let generation = self?.currentGeneration() ?? 0
            self?.queue.async { self?.handleLegacyInterruptionOnQueue(began: began, eventGeneration: generation) }
        })
        if #available(iOS 27, watchOS 27, *) {
            observers.append(center.addObserver(forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: nil) { [weak self] note in
                let parsed = Self.inactiveParts(note)
                let generation = self?.currentGeneration() ?? 0
                self?.queue.async {
                    self?.handleInactiveOnQueue(source: parsed.source, interruptionReason: parsed.reason, eventGeneration: generation)
                }
            })
        }
    }

    private func currentGeneration() -> UInt64 {
        locked { gate.generation }
    }

    private static func previousPorts(_ note: Notification) -> [String] {
        guard let route = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return []
        }
        return route.inputs.map(\.portType.rawValue) + route.outputs.map(\.portType.rawValue)
    }

    @available(iOS 27, watchOS 27, *)
    private static func inactiveParts(_ note: Notification) -> (source: Int, reason: Int?) {
        guard let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext else {
            return (-1, nil)
        }
        let reason: Int?
        if let interruption = context.interruptionContext {
            reason = Int(interruption.reason.rawValue)
        } else {
            reason = nil
        }
        return (context.source.rawValue, reason)
    }

    private func handleRouteOnQueue(oldDeviceUnavailable: Bool, previousPorts: [String], eventGeneration: UInt64) {
        guard acceptSessionEvents else { return }
        guard CarLiveAudioRoute.closesForExternalOutputDisconnect(
            oldDeviceUnavailable: oldDeviceUnavailable,
            previousPorts: previousPorts
        ) else { return }
        applyHoldOnQueue(.headphoneRemoved, releaseSession: true, eventGeneration: eventGeneration)
    }

    private func handleLegacyInterruptionOnQueue(began: Bool, eventGeneration: UInt64) {
        guard acceptSessionEvents else { return }
        guard BackgroundVoicePolicy.closesForLegacyInterruptionBegan(began) else { return }
        applyHoldOnQueue(.systemInterruption, releaseSession: false, eventGeneration: eventGeneration)
    }

    private func handleInactiveOnQueue(source: Int, interruptionReason: Int?, eventGeneration: UInt64) {
        guard acceptSessionEvents else { return }
        guard BackgroundVoicePolicy.closesForSystemInterruption(sourceRaw: source, interruptionReasonRaw: interruptionReason) else { return }
        applyHoldOnQueue(.systemInterruption, releaseSession: false, eventGeneration: eventGeneration)
    }

    private func applyHoldOnQueue(_ kind: BackgroundVoiceHoldKind, releaseSession: Bool, eventGeneration: UInt64) {
        let applied = locked { () -> (UInt64, CarLiveFrameStream?)? in
            guard audioHold == nil, intendedRunning, gate.accepts(eventGeneration) else { return nil }
            audioHold = kind
            intendedRunning = false
            acceptSessionEvents = false
            gate.finishStream()
            gate.clearPlayback()
            playback.removeAll()
            let current = stream
            stream = nil
            return (eventGeneration, current)
        }
        guard let applied else { return }
        applied.1?.finish()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.attachedNodes.contains(player) {
            player.stop()
        }
        if engine.isRunning { engine.stop() }
        if releaseSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        let handler = locked { holdHandler }
        handler?(kind, applied.0)
    }

    private func removeObserversOnQueue() {
        let center = NotificationCenter.default
        for token in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func recoverOnceOnQueue() {
        let snapshot = locked { () -> (Bool, Int, UInt64, Bool) in
            (intendedRunning && gate.accepts(gate.generation), recoveryStarts, gate.generation, audioHold != nil)
        }
        guard BackgroundVoicePolicy.shouldRecoverGraph(
            intendedRunning: snapshot.0,
            held: snapshot.3,
            recoveryStarts: snapshot.1,
            engineRunning: engine.isRunning
        ) else { return }
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

    private static func categoryOptions() -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = []
        for name in CarLiveCaptureSessionPlan.optionNames {
            switch name {
            case "defaultToSpeaker":
                #if os(iOS)
                options.insert(.defaultToSpeaker)
                #endif
            case "allowBluetoothHFP":
                options.insert(.allowBluetoothHFP)
            default:
                continue
            }
        }
        return options
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

    private func notePlayback(_ event: String, _ decision: CarLivePlaybackRestart) {
        CarLiveLifecycleLog.shared.note(CarLiveLifecycleRecord(
            phase: "audio",
            event: event,
            errorCode: "playback_skip",
            engineRunning: decision.engineRunning,
            intendedRunning: decision.intendedRunning,
            playerAttached: decision.playerAttached
        ))
    }
}

#endif
