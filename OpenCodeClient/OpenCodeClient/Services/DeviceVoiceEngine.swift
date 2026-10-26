//
//  DeviceVoiceEngine.swift
//  OpenCodeClient
//

import AVFoundation
import Foundation

/// Converts captured audio into the format the Speech framework takes.
///
/// The capture runs at 24 kHz; on-device recognition wants 16 kHz PCM16 mono.
/// The converter is stateful, so it belongs to one session at a time.
struct SpeechAudioConverter {
    private let sourceFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat?
    private let converter: AVAudioConverter?

    init(sourceSampleRate: Double = 24_000, targetSampleRate: Double = 16_000) {
        let source = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sourceSampleRate, channels: 1, interleaved: true)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: targetSampleRate, channels: 1, interleaved: true)
        self.sourceFormat = source
        self.targetFormat = target
        self.converter = source.flatMap { source in
            target.flatMap { target in AVAudioConverter(from: source, to: target) }
        }
    }

    /// Converts one captured frame.
    ///
    /// A frame that cannot be converted is dropped rather than ending the
    /// session: one bad buffer should not cost the user their sentence.
    func buffer(from pcm: Data) -> AVAudioPCMBuffer? {
        guard let converter, let sourceFormat, let targetFormat else { return nil }
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard frames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames) else { return nil }
        source.frameLength = frames
        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let destination = source.int16ChannelData?.pointee else { return }
            destination.update(from: base.assumingMemoryBound(to: Int16.self), count: Int(frames))
        }
        let ratio = targetFormat.sampleRate / max(sourceFormat.sampleRate, 1)
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(capacity, 1)) else { return nil }
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

/// What the device voice engine needs from the app: a way to run a turn
/// against the user's own server and a way to speak the answer.
@MainActor
protocol DeviceVoiceHost: AnyObject {
    /// Runs one turn and returns the text of the answer.
    func runDeviceVoiceTurn(_ transcript: String) async -> String?
    /// Speaks the answer on this device.
    func speakDeviceVoiceReply(_ text: String) async
    /// Stops the current utterance.
    func stopDeviceVoiceReply()
}

/// One line of the voice conversation.
struct AmbientVoiceEntry: Identifiable, Equatable, Sendable {
    /// Who said it.
    enum Role: Equatable, Sendable {
        /// The person talking to the app.
        case you
        /// The answer, from the user's own server.
        case opencode
    }

    var id = UUID()
    var role: Role
    var text: String
}

/// The hands-free voice loop, running entirely on the user's own devices.
///
/// The microphone feeds an on-device recogniser; the recognised text becomes a
/// turn against the user's own OpenCode server; the answer is spoken by the
/// device's own speech synthesiser. No audio is uploaded anywhere: the only
/// thing that leaves the device is the transcript, sent to that server.
@MainActor
@Observable
final class DeviceVoiceEngine {
    /// What the engine is doing right now.
    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case failed(String)
    }

    /// The silence after the last recognised word that ends an utterance.
    ///
    /// The recogniser closes most utterances by itself; this is the backstop
    /// for a speaker who never pauses.
    static let utteranceSilence: TimeInterval = 1.2

    /// How many lines of the conversation are kept. A long session must not
    /// grow without bound.
    static let maximumEntries = 40

    /// What the engine is doing right now.
    private(set) var phase: Phase = .idle
    /// What the user is saying right now.
    private(set) var transcript: String = ""
    /// The last answer the engine spoke.
    private(set) var reply: String = ""
    /// The conversation so far, newest last.
    private(set) var entries: [AmbientVoiceEntry] = []
    /// The microphone level, 0...1, for the meter.
    private(set) var inputLevel: Double = 0

    /// The app the engine asks to run turns and to speak the answer.
    ///
    /// It is a weak reference set once, when the state finishes starting:
    /// creating the engine lazily inside a view body would mutate the state
    /// during the view update.
    weak var host: (any DeviceVoiceHost)?

    private let audioEngine: any CarLiveAudioEngine
    private let makeSession: @MainActor () async throws -> OnDeviceSpeechSession
    private let turnRunner: (@MainActor (String) async -> String?)?
    private let speaker: (@MainActor (String) async -> Void)?
    private let silencer: (@MainActor () -> Void)?

    private var session: OnDeviceSpeechSession?
    private var capture: CarLiveCaptureHandle?
    private var converter: SpeechAudioConverter?
    private var frameTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var speaking = false

    init(
        audioEngine: any CarLiveAudioEngine = CarLiveAudioEngines.makeDefault(),
        makeSession: @escaping @MainActor () async throws -> OnDeviceSpeechSession = {
            try await OnDeviceSpeechSession.startAppleOnDevice()
        },
        turnRunner: (@MainActor (String) async -> String?)? = nil,
        speaker: (@MainActor (String) async -> Void)? = nil,
        silencer: (@MainActor () -> Void)? = nil
    ) {
        self.audioEngine = audioEngine
        self.makeSession = makeSession
        self.turnRunner = turnRunner
        self.speaker = speaker
        self.silencer = silencer
    }

    /// True while the engine holds the microphone.
    var isListening: Bool {
        if case .listening = phase { return true }
        if case .thinking = phase { return true }
        return false
    }

    /// Starts listening.
    func start() async {
        guard !isListening else { return }
        await stop()

        guard await audioEngine.requestRecordPermission() else {
            phase = .failed(L10n.t(.carVoiceMicrophoneDenied))
            return
        }
        do {
            let session = try await makeSession()
            let handle = try await audioEngine.startCapture()
            self.session = session
            self.capture = handle
            self.converter = SpeechAudioConverter()
            audioEngine.setLevelHandler { [weak self] input, _ in
                Task { @MainActor in self?.inputLevel = input }
            }
            frameTask = Task { [weak self] in
                await self?.consumeFrames(handle)
            }
            eventTask = Task { [weak self] in
                await self?.consumeEvents(session)
            }
            phase = .listening
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Stops listening and cancels the turn in flight.
    func stop() async {
        silenceTask?.cancel()
        silenceTask = nil
        frameTask?.cancel()
        frameTask = nil
        eventTask?.cancel()
        eventTask = nil
        turnTask?.cancel()
        turnTask = nil
        session?.cancel()
        session = nil
        if let capture {
            await audioEngine.stopCapture(generation: capture.generation)
        }
        capture = nil
        converter = nil
        audioEngine.setLevelHandler(nil)
        stopTheAnswer()
        speaking = false
        transcript = ""
        inputLevel = 0
        phase = .idle
    }

    /// Runs one turn against the user's own server.
    private func runTurnOnServer(_ text: String) async -> String? {
        if let turnRunner { return await turnRunner(text) }
        return await host?.runDeviceVoiceTurn(text)
    }

    /// Speaks the answer on this device.
    private func speakAnswer(_ text: String) async {
        if let speaker {
            await speaker(text)
            return
        }
        await host?.speakDeviceVoiceReply(text)
    }

    /// Stops the current utterance.
    private func stopTheAnswer() {
        if let silencer {
            silencer()
            return
        }
        host?.stopDeviceVoiceReply()
    }

    private func consumeFrames(_ handle: CarLiveCaptureHandle) async {
        for await pcm in handle.frames {
            guard let session, let converter else { return }
            guard let buffer = converter.buffer(from: pcm) else { continue }
            session.append(buffer)
        }
    }

    private func consumeEvents(_ session: OnDeviceSpeechSession) async {
        for await event in session.events {
            switch event {
            case .transcript(let update):
                note(update)
            case .failed(let failure):
                switch failure {
                case .cancelled:
                    break
                case .failed(let message):
                    phase = .failed(message)
                }
            }
        }
    }

    /// Takes one transcript update.
    ///
    /// This never waits: the turn and the answer run in their own task, so a
    /// word spoken over the answer still reaches the engine while the answer
    /// is being spoken.
    private func note(_ update: SpeechTranscriptUpdate) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if speaking {
            // Barge-in: the user started talking over the answer, so the
            // answer stops and the new words take over. The abandoned turn
            // is cancelled with it — it must not claim the phase back.
            stopTheAnswer()
            speaking = false
            turnTask?.cancel()
            phase = .listening
        }
        transcript = text
        if update.isFinal {
            session?.finish()
            turnTask?.cancel()
            turnTask = Task { [weak self] in
                await self?.runTurn(text)
            }
        } else {
            scheduleSilenceCheck()
        }
    }

    private func runTurn(_ text: String) async {
        phase = .thinking
        transcript = ""
        silenceTask?.cancel()
        silenceTask = nil
        entries.append(AmbientVoiceEntry(role: .you, text: text))
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        let answer = await runTurnOnServer(text)
        // A turn the user took over must not answer afterwards.
        guard !Task.isCancelled else { return }
        guard let answer, !answer.isEmpty else {
            phase = .idle
            beginNextUtterance()
            return
        }
        reply = answer
        entries.append(AmbientVoiceEntry(role: .opencode, text: answer))
        phase = .speaking
        speaking = true
        await speakAnswer(answer)
        speaking = false
        guard !Task.isCancelled else { return }
        phase = .idle
        beginNextUtterance()
    }

    /// Starts the next utterance, so the user can keep talking.
    private func beginNextUtterance() {
        guard let session else { return }
        do {
            try session.start()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func scheduleSilenceCheck() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.utteranceSilence))
            guard !Task.isCancelled else { return }
            self?.closeUtteranceIfStillOpen()
        }
    }

    /// Closes an utterance the recogniser has not closed itself.
    private func closeUtteranceIfStillOpen() {
        guard !transcript.isEmpty else { return }
        session?.finish()
    }
}
