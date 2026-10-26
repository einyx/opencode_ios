//
//  OnDeviceSpeechSession.swift
//  OpenCodeClient
//

import AVFoundation
import Foundation
import Speech

/// One transcript update from a live recognition session.
struct SpeechTranscriptUpdate: Equatable, Sendable {
    /// What the recognizer believes was said so far.
    var text: String
    /// True once the recognizer has closed the utterance.
    var isFinal: Bool
}

/// Why a live recognition session stopped before it produced a transcript.
enum SpeechRecognitionFailure: Error, Equatable, Sendable {
    /// The session was cancelled on purpose.
    case cancelled
    /// The recognizer failed.
    case failed(String)
}

/// What a live recognition session reports.
enum SpeechSessionEvent: Equatable, Sendable {
    /// A transcript update — partial while the user speaks, final once it ends.
    case transcript(SpeechTranscriptUpdate)
    /// The session stopped early.
    case failed(SpeechRecognitionFailure)
}

/// The slice of the Speech framework a live session drives.
///
/// A protocol so the session can be tested without a recognizer: the
/// framework's own request and result types cannot be built outside it.
protocol StreamingSpeechRecognizing: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    /// Starts the task. `events` reports transcripts and failures as they happen.
    @MainActor
    func start(events: @escaping @Sendable (SpeechSessionEvent) -> Void) throws
    /// Feeds one buffer of audio into the running task.
    @MainActor
    func append(_ buffer: AVAudioPCMBuffer)
    /// Ends the utterance, so the task can report its final transcript.
    @MainActor
    func finish()
    /// Stops the task without a final transcript.
    @MainActor
    func cancel()
}

/// A live, on-device speech recognition session.
///
/// The request is pinned to on-device recognition: when the device cannot do
/// it the session fails loudly instead of sending the audio anywhere.
/// Transcripts arrive as they are recognised, so the interface can show what
/// the user is saying while they are still saying it.
@MainActor
final class OnDeviceSpeechSession {
    /// Transcript updates and failures, in the order the recognizer reported
    /// them.
    let events: AsyncStream<SpeechSessionEvent>

    private let recognizer: any StreamingSpeechRecognizing
    private let continuation: AsyncStream<SpeechSessionEvent>.Continuation
    private var started = false
    private var ended = false

    init(recognizer: any StreamingSpeechRecognizing) {
        self.recognizer = recognizer
        var captured: AsyncStream<SpeechSessionEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        continuation = captured
    }

    /// Starts an utterance.
    ///
    /// A recognition task ends with its utterance, so every new utterance
    /// needs a new one — the recognizer itself is reused.
    func start() throws {
        guard !started || ended else { return }
        started = true
        ended = false
        try recognizer.start { [weak self] event in
            // The recognizer reports on its own queue; the session owns the
            // order, so the events go out in the order they arrived.
            self?.continuation.yield(event)
        }
    }

    /// Feeds one buffer of captured audio into the recognizer.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard started, !ended else { return }
        recognizer.append(buffer)
    }

    /// Ends the utterance so the recognizer can report its final transcript.
    func finish() {
        guard started, !ended else { return }
        ended = true
        recognizer.finish()
    }

    /// Stops the session. No final transcript will arrive.
    func cancel() {
        guard !ended else { return }
        ended = true
        recognizer.cancel()
        continuation.finish()
    }
}

extension OnDeviceSpeechSession {
    /// Starts a live session on Apple's on-device recognizer.
    ///
    /// The on-device probe is a hard gate: without it the session refuses to
    /// start rather than risk sending audio off the device.
    @MainActor
    static func startAppleOnDevice(
        locale: Locale = .current,
        requestAuthorization: @escaping @Sendable () async -> SFSpeechRecognizerAuthorizationStatus = {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        },
        makeRecognizer: @escaping @MainActor @Sendable (Locale) -> (any StreamingSpeechRecognizing)? = { locale in
            SFSpeechRecognizer(locale: locale).map { FrameworkStreamingRecognizer(recognizer: $0) }
        },
        fallbackRecognizer: @escaping @MainActor @Sendable () -> (any StreamingSpeechRecognizing)? = {
            SFSpeechRecognizer().map { FrameworkStreamingRecognizer(recognizer: $0) }
        },
        supportsOnDevice: @escaping @MainActor @Sendable (any StreamingSpeechRecognizing) -> Bool = { $0.supportsOnDeviceRecognition }
    ) async throws -> OnDeviceSpeechSession {
        guard await requestAuthorization() == .authorized else {
            throw AppleSpeechTranscriptionError.authorizationDenied
        }
        // Locale precedence: the device locale (what the user actually
        // speaks) with a regional fallback (it-IT -> it), then any recognizer.
        let regional = Locale(identifier: locale.identifier.split(separator: "_").first.map { String($0) } ?? locale.identifier)
        guard let recognizer = makeRecognizer(locale)
            ?? makeRecognizer(regional)
            ?? fallbackRecognizer() else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }
        guard supportsOnDevice(recognizer) else {
            throw AppleSpeechTranscriptionError.onDeviceUnavailable
        }
        let session = OnDeviceSpeechSession(recognizer: recognizer)
        try session.start()
        return session
    }
}

/// The live recognizer built on Apple's Speech framework.
///
/// The request is pinned to on-device recognition and reports partial results,
/// so the utterance can be shown while it is being spoken.
@MainActor
final class FrameworkStreamingRecognizer: StreamingSpeechRecognizing {
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest
    private var task: SFSpeechRecognitionTask?

    /// The recognizer and the request are framework objects with no actor
    /// affinity; only the task lifecycle below is main-actor work.
    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
        self.request = Self.makeRequest()
    }

    /// A request is per utterance: the task ends with the utterance, so the
    /// next one needs a fresh request on the same recognizer.
    private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        return request
    }

    var isAvailable: Bool { recognizer.isAvailable }
    var supportsOnDeviceRecognition: Bool { recognizer.supportsOnDeviceRecognition }

    func start(events: @escaping @Sendable (SpeechSessionEvent) -> Void) throws {
        request = Self.makeRequest()
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                events(.transcript(SpeechTranscriptUpdate(
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal
                )))
                return
            }
            guard let error else { return }
            // A cancelled task surfaces as kAFAssistantErrorDomain 203/216;
            // report it as a cancellation so the callers' attempt-gate treats
            // it as a bail-out rather than a recognition failure.
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && [203, 216].contains(nsError.code) {
                events(.failed(.cancelled))
            } else {
                events(.failed(.failed(error.localizedDescription)))
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() {
        request.endAudio()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
