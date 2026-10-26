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

@MainActor
private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
private final class FakeVoiceHost: DeviceVoiceHost {
    var turns: [String] = []
    var spoken: [String] = []
    var permissionAnswers: [(permission: PendingPermission, allow: Bool)] = []
    var turnAnswer = "ok"

    func runDeviceVoiceTurn(_ transcript: String) async -> String? {
        turns.append(transcript)
        return turnAnswer
    }

    func speakDeviceVoiceReply(_ text: String) async {
        spoken.append(text)
    }

    func stopDeviceVoiceReply() {}

    func answerDeviceVoicePermission(_ permission: PendingPermission, allow: Bool) async {
        permissionAnswers.append((permission, allow))
    }

    func deliverDeviceVoiceReplyToWatch(_ text: String) async {
        spoken.append(text)
    }
}

private func makePermission() -> PendingPermission {
    PendingPermission(
        sessionID: "s1",
        permissionID: "p1",
        permission: "bash",
        patterns: [],
        allowAlways: false,
        tool: "bash",
        description: "Run a command"
    )
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

    @Test @MainActor func aSpokenYesAnswersAPermissionOnce() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        let host = FakeVoiceHost()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { text in await host.runDeviceVoiceTurn(text) },
            speaker: { text in await host.speakDeviceVoiceReply(text) }
        )
        engine.host = host

        await engine.start()
        let permission = makePermission()
        engine.askPermission(permission)
        #expect(await waitUntil { host.spoken.contains { $0.contains("bash") } })

        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "yes", isFinal: true)))
        #expect(await waitUntil { !host.permissionAnswers.isEmpty })
        #expect(host.permissionAnswers.first?.permission.id == permission.id)
        #expect(host.permissionAnswers.first?.allow == true)
        // The answer decides the permission; it is not a new turn.
        #expect(host.turns.isEmpty)
        // The user is told what was decided.
        #expect(await waitUntil { host.spoken.contains { $0.contains("Allowed") } })
    }

    /// On the watch the confirmation has to go to the wrist too, not to the
    /// phone's speaker next to the user's arm.
    @Test @MainActor func thePermissionConfirmationFollowsTheDeliveryMode() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        let host = FakeVoiceHost()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { text in await host.runDeviceVoiceTurn(text) },
            speaker: { text in await host.speakDeviceVoiceReply(text) }
        )
        engine.host = host
        engine.delivery = .watch

        await engine.start()
        engine.askPermission(makePermission())
        #expect(await waitUntil { host.spoken.contains { $0.contains("bash") } })

        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "yes", isFinal: true)))
        #expect(await waitUntil { !host.permissionAnswers.isEmpty })
        #expect(await waitUntil { host.spoken.contains { $0.contains("Allowed") } })
    }

    @Test @MainActor func aSpokenNoRefusesAPermission() async throws {
        let audio = FakeAudioEngine()
        let recognizer = FakeStreamingRecognizer()
        let host = FakeVoiceHost()
        let engine = DeviceVoiceEngine(
            audioEngine: audio,
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: recognizer)
                try session.start()
                return session
            },
            turnRunner: { text in await host.runDeviceVoiceTurn(text) },
            speaker: { text in await host.speakDeviceVoiceReply(text) }
        )
        engine.host = host

        await engine.start()
        engine.askPermission(makePermission())
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "no, do not run that", isFinal: true)))
        #expect(await waitUntil { !host.permissionAnswers.isEmpty })
        #expect(host.permissionAnswers.first?.allow == false)
    }

    @Test func spokenAnswersAreWholeWords() {
        #expect(DeviceVoiceEngine.isAffirmative("yes"))
        #expect(DeviceVoiceEngine.isAffirmative("Yes, go ahead"))
        #expect(DeviceVoiceEngine.isAffirmative("okay"))
        #expect(DeviceVoiceEngine.isAffirmative("allow it"))
        #expect(!DeviceVoiceEngine.isAffirmative("no"))
        #expect(!DeviceVoiceEngine.isAffirmative("no, stop"))
        #expect(!DeviceVoiceEngine.isAffirmative("I don't know"))
        #expect(!DeviceVoiceEngine.isAffirmative(""))
    }
}
