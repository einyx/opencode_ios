//
//  OnDeviceSpeechSessionTests.swift
//  OpenCodeClientTests
//

import AVFoundation
import Foundation
import Speech
import Testing
@testable import OpenCodeClient

@Suite(.serialized)
struct OnDeviceSpeechSessionTests {
    @Test @MainActor func deniedAuthorizationThrowsPermissionDenied() async {
        do {
            _ = try await OnDeviceSpeechSession.startAppleOnDevice(
                requestAuthorization: { .denied },
                makeRecognizer: { _ in
                    Issue.record("the recognizer must not be built before authorization")
                    return nil
                }
            )
            Issue.record("expected authorizationDenied")
        } catch let error as AppleSpeechTranscriptionError {
            guard case .authorizationDenied = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test @MainActor func missingRecognizerThrowsRecognizerUnavailable() async {
        do {
            _ = try await OnDeviceSpeechSession.startAppleOnDevice(
                requestAuthorization: { .authorized },
                makeRecognizer: { _ in nil },
                fallbackRecognizer: { nil }
            )
            Issue.record("expected recognizerUnavailable")
        } catch let error as AppleSpeechTranscriptionError {
            guard case .recognizerUnavailable = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test @MainActor func onDeviceProbeFailureThrowsOnDeviceUnavailable() async {
        do {
            _ = try await OnDeviceSpeechSession.startAppleOnDevice(
                requestAuthorization: { .authorized },
                makeRecognizer: { _ in FakeStreamingRecognizer() },
                supportsOnDevice: { _ in false }
            )
            Issue.record("expected onDeviceUnavailable")
        } catch let error as AppleSpeechTranscriptionError {
            guard case .onDeviceUnavailable = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test @MainActor func sessionReportsTranscriptsInOrder() async throws {
        let recognizer = FakeStreamingRecognizer()
        let session = OnDeviceSpeechSession(recognizer: recognizer)
        try session.start()

        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "hello", isFinal: false)))
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "hello there", isFinal: false)))
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "hello there", isFinal: true)))

        var received: [SpeechSessionEvent] = []
        for await event in session.events {
            received.append(event)
            if case .transcript(let update) = event, update.isFinal { break }
        }
        #expect(received.count == 3)
        #expect(received.first == .transcript(SpeechTranscriptUpdate(text: "hello", isFinal: false)))
        #expect(received.last == .transcript(SpeechTranscriptUpdate(text: "hello there", isFinal: true)))
    }

    @Test @MainActor func sessionForwardsAudioOnlyAfterStart() async throws {
        let recognizer = FakeStreamingRecognizer()
        let session = OnDeviceSpeechSession(recognizer: recognizer)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!

        session.append(buffer)
        #expect(recognizer.appendedBufferCount == 0)

        try session.start()
        session.append(buffer)
        #expect(recognizer.appendedBufferCount == 1)
    }

    @Test @MainActor func finishingTheUtteranceEndsItExactlyOnce() async throws {
        let recognizer = FakeStreamingRecognizer()
        let session = OnDeviceSpeechSession(recognizer: recognizer)
        try session.start()

        session.finish()
        session.finish()
        #expect(recognizer.finishCount == 1)
    }

    @Test @MainActor func cancellingStopsTheSessionAndClosesTheStream() async throws {
        let recognizer = FakeStreamingRecognizer()
        let session = OnDeviceSpeechSession(recognizer: recognizer)
        try session.start()

        session.cancel()
        #expect(recognizer.cancelCount == 1)

        // A late event from the recognizer must not reopen a cancelled session.
        recognizer.emit(.transcript(SpeechTranscriptUpdate(text: "late", isFinal: true)))

        var received: [SpeechSessionEvent] = []
        for await event in session.events {
            received.append(event)
        }
        #expect(received.isEmpty)
    }

    @Test @MainActor func startAppleOnDeviceFallsBackToTheRegionalLocale() async throws {
        let device = Locale(identifier: "it_IT")
        let regional = Locale(identifier: "it")
        let recognizer = FakeStreamingRecognizer()
        var asked: [String] = []
        _ = try await OnDeviceSpeechSession.startAppleOnDevice(
            locale: device,
            requestAuthorization: { .authorized },
            makeRecognizer: { locale in
                asked.append(locale.identifier)
                // The device locale is tried first; the regional one is the
                // fallback when it has no recognizer.
                return locale.identifier == regional.identifier ? recognizer : nil
            }
        )
        #expect(asked == [device.identifier, regional.identifier])
        #expect(recognizer.startCount == 1)
    }
}
