import AVFoundation
import Foundation
import Speech

/// On-device transcription via Apple's Speech framework. No account, no
/// network, no token: the recognizer is pinned to
/// `requiresOnDeviceRecognition` so audio never leaves the device.
enum AppleSpeechTranscriptionError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case onDeviceUnavailable
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .authorizationDenied: L10n.t(.speechApplePermissionDenied)
        case .recognizerUnavailable: L10n.t(.speechAppleUnavailable)
        case .onDeviceUnavailable: L10n.t(.speechAppleOnDeviceUnavailable)
        case .emptyResult: L10n.t(.speechAppleNoSpeech)
        }
    }
}

/// The slice of `SFSpeechRecognizer` the transcriber uses. A protocol so
/// tests can inject a stand-in: constructing real recognizers in the
/// simulator corrupts a Speech-framework global and blows up unrelated
/// allocations later in the run.
protocol SpeechRecognizing: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    func recognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> SFSpeechRecognitionTask
}

extension SFSpeechRecognizer: SpeechRecognizing {}

struct AppleSpeechTranscriber {
    /// Authorization request, injectable for tests.
    let requestAuthorization: @Sendable () async -> SFSpeechRecognizerAuthorizationStatus
    /// Recognizer factory, injectable for tests.
    let makeRecognizer: @Sendable (Locale) -> (any SpeechRecognizing)?
    /// Last-resort recognizer when the locale probes fail, injectable for tests.
    let fallbackRecognizer: @Sendable () -> (any SpeechRecognizing)?
    /// On-device capability probe, injectable for tests.
    let supportsOnDevice: @Sendable (any SpeechRecognizing) -> Bool
    /// The actual recognition run, injectable for tests.
    private let recognize: @Sendable (any SpeechRecognizing, SFSpeechURLRecognitionRequest, (@Sendable (String) -> Void)?) async throws -> String

    init(
        requestAuthorization: @escaping @Sendable () async -> SFSpeechRecognizerAuthorizationStatus = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        },
        makeRecognizer: @escaping @Sendable (Locale) -> (any SpeechRecognizing)? = { SFSpeechRecognizer(locale: $0) },
        fallbackRecognizer: @escaping @Sendable () -> (any SpeechRecognizing)? = { SFSpeechRecognizer() },
        supportsOnDevice: @escaping @Sendable (any SpeechRecognizing) -> Bool = { $0.supportsOnDeviceRecognition },
        recognize: @escaping @Sendable (any SpeechRecognizing, SFSpeechURLRecognitionRequest, (@Sendable (String) -> Void)?) async throws -> String = AppleSpeechTranscriber.defaultRecognize
    ) {
        self.requestAuthorization = requestAuthorization
        self.makeRecognizer = makeRecognizer
        self.fallbackRecognizer = fallbackRecognizer
        self.supportsOnDevice = supportsOnDevice
        self.recognize = recognize
    }

    /// Transcribes a recorded audio file (WAV/PCM16 from the voice capture)
    /// entirely on-device. `onPartial` reports best-transcription progress
    /// while the recognizer works through the file.
    func transcribeFile(
        at url: URL,
        locale: Locale = .current,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard await requestAuthorization() == .authorized else {
            throw AppleSpeechTranscriptionError.authorizationDenied
        }
        // Locale precedence: the device locale (what the user actually
        // speaks) with a regional fallback (it-IT -> it), then any recognizer.
        guard let recognizer = makeRecognizer(locale)
            ?? makeRecognizer(Locale(identifier: locale.identifier.split(separator: "_").first.map { String($0) } ?? locale.identifier))
            ?? fallbackRecognizer() else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }
        // On-device is the point of this engine; without it we fail loudly
        // instead of silently uploading the recording.
        guard supportsOnDevice(recognizer) else {
            throw AppleSpeechTranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = onPartial != nil
        request.requiresOnDeviceRecognition = true
        request.taskHint = .confirmation
        return try await recognize(recognizer, request, onPartial)
    }

    /// Drives one recognition task to its final result. Partials are surfaced
    /// through `onPartial` as the recognizer works through the file.
    private static func defaultRecognize(
        _ recognizer: any SpeechRecognizing,
        _ request: SFSpeechURLRecognitionRequest,
        _ onPartial: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var finalized = false
            let lock = NSLock()
            recognizer.recognitionTask(with: request, resultHandler: { result, error in
                lock.lock()
                if finalized {
                    lock.unlock()
                    return
                }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        finalized = true
                        lock.unlock()
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            continuation.resume(throwing: AppleSpeechTranscriptionError.emptyResult)
                        } else {
                            continuation.resume(returning: trimmed)
                        }
                        return
                    }
                    lock.unlock()
                    if let onPartial, !text.isEmpty {
                        onPartial(text)
                    }
                    return
                }
                lock.unlock()
                guard let error else { return }
                lock.lock()
                if finalized {
                    lock.unlock()
                    return
                }
                finalized = true
                lock.unlock()
                // A cancelled task surfaces as kAFAssistantErrorDomain 203/216;
                // rethrow as Swift cancellation so the callers' attempt-gate
                // treats it as a bail-out rather than a transcription failure.
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && [203, 216].contains(nsError.code) {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error)
                }
            })
        }
    }
}
