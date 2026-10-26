//
//  DeviceVoiceEngineTests.swift
//  OpenCodeClientTests
//

import AVFoundation
import Foundation
import Testing
@testable import OpenCodeClient

/// An audio engine stand-in: it hands out captured frames and records the
/// capture lifecycle.
private final class FakeAudioEngine: CarLiveAudioEngine, @unchecked Sendable {
    var startsBeforeConnection: Bool { false }
    var permissionGranted = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var levelHandler: (@Sendable (Double, Double) -> Void)?
    private var continuation: AsyncStream<Data>.Continuation?

    func requestRecordPermission() async -> Bool { permissionGranted }

    func startCapture() async throws -> CarLiveCaptureHandle {
        startCount += 1
        var captured: AsyncStream<Data>.Continuation!
        let frames = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(8)) { captured = $0 }
        continuation = captured
        return CarLiveCaptureHandle(generation: UInt64(startCount), frames: frames, finish: {})
    }

    func stopCapture(generation: UInt64) async { stopCount += 1 }

    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setPlaybackHeld(_ held: Bool) {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) { levelHandler = handler }
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}
    func setFailureHandler(_ handler: (@Sendable (String) -> Void)?) {}
    func setHoldHandler(_ handler: (@Sendable (BackgroundVoiceHoldKind, UInt64) -> Void)?) {}

    /// Delivers one captured frame to the engine.
    func deliver(_ pcm: Data) {
        continuation?.yield(pcm)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@Suite(.serialized)
struct DeviceVoiceEngineTests {
    @Test @MainActor func aFinalTranscriptBecomesASpokenAnswer() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        var turns: [String] = []
        var spoken: [String] = []
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { text in
                turns.append(text)
                return "The garage door is closed."
            },
            speaker: { text in spoken.append(text) }
        )

        await engine.start()
        #expect(engine.phase == .listening)

        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "Is the garage closed?", isFinal: true)))
        #expect(await waitUntil { spoken.count == 1 })
        #expect(turns == ["Is the garage closed?"])
        #expect(spoken == ["The garage door is closed."])
        #expect(engine.reply == "The garage door is closed.")
    }

    @Test @MainActor func aPartialTranscriptIsShownWithoutRunningATurn() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        var turns: [String] = []
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { text in
                turns.append(text)
                return "ok"
            },
            speaker: { _ in }
        )

        await engine.start()
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "Is the garage", isFinal: false)))
        #expect(await waitUntil { engine.transcript == "Is the garage" })
        #expect(turns.isEmpty)
        #expect(engine.phase == .listening)
    }

    @Test @MainActor func speakingOverTheAnswerInterruptsIt() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        var stopped = 0
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { _ in "A long answer that is still being spoken." },
            speaker: { _ in
                // The answer is long enough for the user to talk over it.
                try? await Task.sleep(for: .milliseconds(400))
            },
            silencer: { stopped += 1 }
        )

        await engine.start()
        // Starting the engine stops whatever was running before it, so the
        // counter only measures the barge-in from here on.
        stopped = 0
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "First question", isFinal: true)))
        #expect(await waitUntil { engine.phase == .speaking })

        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "Wait", isFinal: false)))
        #expect(await waitUntil { stopped == 1 })
        #expect(engine.phase == .listening)
        #expect(engine.transcript == "Wait")
    }

    @Test @MainActor func aMissingMicrophoneIsReported() async {
        let audio = FakeAudioEngine()
        audio.permissionGranted = false
        let recognizer = FakeStreamingRecognizer()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { _ in "ok" },
            speaker: { _ in }
        )

        await engine.start()
        #expect(engine.phase == .failed(L10n.t(.carVoiceMicrophoneDenied)))
        #expect(audio.startCount == 0)
    }

    @Test @MainActor func stoppingReleasesTheMicrophone() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { _ in "ok" },
            speaker: { _ in }
        )

        await engine.start()
        #expect(audio.startCount == 1)

        await engine.stop()
        #expect(audio.stopCount == 1)
        #expect(engine.phase == .idle)
        #expect(engine.transcript == "")
    }

    @Test @MainActor func capturedFramesReachTheRecognizer() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { _ in "ok" },
            speaker: { _ in }
        )

        await engine.start()
        audio.deliver(Data(repeating: 0, count: 4_800))
        #expect(await waitUntil { recognizer.appendedBufferCount > 0 })
    }
}
