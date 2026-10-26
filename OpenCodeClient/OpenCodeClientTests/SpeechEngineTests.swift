import AVFoundation
import Speech
import Testing

@testable import OpenCodeClient

// These suites use Swift Testing on purpose: the repo's tests are `@Test`
// functions, and XCTest-style tests that allocate + drop a MainActor
// `AppState` trip a Swift concurrency back-deploy deinit bug
// (swift_task_deinitOnExecutorMainActorBackDeploy -> SessionStore dealloc
// aborts in malloc). Keep new tests in this style.

/// A stand-in recognizer: keeps real Speech-framework objects out of the
/// test process entirely.
private final class FakeRecognizer: SpeechRecognizing {
    let isAvailable = true
    let supportsOnDeviceRecognition = true
    func recognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        fatalError("not expected in these tests")
    }
}

@Suite
struct SpeechRecognitionEngineTests {
    // MARK: persistence / migration

    @Test func emptyStoredValueResolvesToAppleOnDevice() {
        #expect(SpeechRecognitionEngine.resolved(fromRaw: nil) == .appleOnDevice)
        #expect(SpeechRecognitionEngine.resolved(fromRaw: "") == .appleOnDevice)
    }

    @Test func aRemovedStrategyFallsBackToTheOnDeviceOne() {
        // The cloud strategies are gone. A device that still remembers one
        // must land on the on-device engine, not on a broken voice input.
        #expect(SpeechRecognitionEngine.resolved(fromRaw: "gptLiveTranscribe") == .appleOnDevice)
        #expect(SpeechRecognitionEngine.resolved(fromRaw: "openAIRealtime") == .appleOnDevice)
        #expect(SpeechRecognitionEngine.resolved(fromRaw: "grokBatch") == .appleOnDevice)
    }

    @Test func unknownStoredValueFallsBackToAppleOnDevice() {
        #expect(SpeechRecognitionEngine.resolved(fromRaw: "telepathy") == .appleOnDevice)
    }

    // MARK: capability matrix

    @Test func appleOnDeviceNeedsNoService() {
        #expect(!SpeechRecognitionEngine.appleOnDevice.usesVoiceFlowService)
        #expect(!SpeechRecognitionEngine.appleOnDevice.usesRealtimeSession)
        #expect(!SpeechRecognitionEngine.appleOnDevice.showsLivePartials)
    }

    // MARK: AppState gating

    @Test @MainActor func voiceIsConfiguredWithZeroSetup() {
        let state = makeIsolatedAppState()
        state.speechRecognitionEngine = .appleOnDevice
        #expect(state.isChatSpeechConfigured, "on-device speech must work with zero setup")
    }

    // MARK: transcription routing

    @Test @MainActor func transcribeWithAppleEngineSkipsTheTokenAndReturnsLocalResult() async throws {
        let state = makeIsolatedAppState()
        state.speechRecognitionEngine = .appleOnDevice
        state.appleSpeechTranscriber = AppleSpeechTranscriber(
            requestAuthorization: { .authorized },
            makeRecognizer: { _ in FakeRecognizer() },
            recognize: { _, _, _ in "hello from the device" }
        )
        let url = URL(fileURLWithPath: "/dev/null")
        let transcript = try await state.transcribeAudio(audioFileURL: url, engine: .appleOnDevice, surface: .chat)
        #expect(transcript == "hello from the device")
    }

}

@Suite
struct AppleSpeechTranscriberTests {
    @Test @MainActor func deniedAuthorizationThrowsPermissionDenied() async {
        let transcriber = AppleSpeechTranscriber(
            requestAuthorization: { .denied },
            makeRecognizer: { _ in Issue.record("recognizer must not be built before authorization"); return nil }
        )
        do {
            _ = try await transcriber.transcribeFile(at: URL(fileURLWithPath: "/dev/null"))
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

    @Test @MainActor func unavailableRecognizerThrowsRecognizerUnavailable() async {
        let transcriber = AppleSpeechTranscriber(
            requestAuthorization: { .authorized },
            makeRecognizer: { _ in nil },
            fallbackRecognizer: { nil }
        )
        do {
            _ = try await transcriber.transcribeFile(at: URL(fileURLWithPath: "/dev/null"))
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

    @Test @MainActor func recognizeReceivesAnOnDevicePinnedRequest() async throws {
        nonisolated(unsafe) var seenRequest: SFSpeechURLRecognitionRequest?
        let transcriber = AppleSpeechTranscriber(
            requestAuthorization: { .authorized },
            makeRecognizer: { locale in
                #expect(locale.identifier == "it_IT")
                return FakeRecognizer()
            },
            recognize: { _, request, _ in
                seenRequest = request
                return "ok"
            }
        )
        let result = try await transcriber.transcribeFile(at: URL(fileURLWithPath: "/dev/null"), locale: Locale(identifier: "it_IT"))
        #expect(result == "ok")
        #expect(seenRequest?.shouldReportPartialResults == false)
    }

    @Test @MainActor func onDeviceProbeFailureThrowsOnDeviceUnavailable() async {
        let transcriber = AppleSpeechTranscriber(
            requestAuthorization: { .authorized },
            makeRecognizer: { _ in FakeRecognizer() },
            supportsOnDevice: { _ in false },
            recognize: { _, _, _ in Issue.record("recognition must not run without on-device support"); return "" }
        )
        do {
            _ = try await transcriber.transcribeFile(at: URL(fileURLWithPath: "/dev/null"))
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
}
