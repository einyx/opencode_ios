import Foundation

nonisolated enum SpeechAttemptGate {
    static func owns(_ attemptID: UUID, activeAttemptID: UUID?) -> Bool {
        attemptID == activeAttemptID
    }

    static func accepts(
        _ attemptID: UUID,
        activeAttemptID: UUID?,
        originatingSessionID: String?,
        currentSessionID: String?
    ) -> Bool {
        owns(attemptID, activeAttemptID: activeAttemptID)
            && originatingSessionID == currentSessionID
    }
}

struct ChatSpeechDraftRoute: Equatable {
    let sourceSessionID: String?
    let sourceDraftText: String
    let currentComposerText: String?
}

enum ChatSpeechNavigationDisposition: Equatable {
    case detachFinalization
    case cancelAndPreserve
}

struct ChatSpeechCleanupPlan: Equatable {
    /// True only while Chat itself is recording or starting capture.
    var releasesOwnedMicrophone: Bool
    /// True for an owned capture or an in-flight transcription whose hardware was already released.
    var preservesBackendCapture: Bool
}

@MainActor
protocol ChatSpeechMicrophoneControlling: AnyObject {
    func stop() async throws -> URL?
    func discard()
}

nonisolated enum ChatSpeechRouting {
    static func mergedInput(prefix: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return prefix }
        guard !prefix.isEmpty else { return cleanedTranscript }
        return prefix + " " + cleanedTranscript
    }

    static func draftRoute(
        prefix: String,
        transcript: String,
        sourceSessionID: String?,
        currentSessionID: String?
    ) -> ChatSpeechDraftRoute {
        route(
            fullText: mergedInput(prefix: prefix, transcript: transcript),
            sourceSessionID: sourceSessionID,
            currentSessionID: currentSessionID
        )
    }

    static func route(
        fullText: String,
        sourceSessionID: String?,
        currentSessionID: String?
    ) -> ChatSpeechDraftRoute {
        ChatSpeechDraftRoute(
            sourceSessionID: sourceSessionID,
            sourceDraftText: fullText,
            currentComposerText: sourceSessionID == currentSessionID ? fullText : nil
        )
    }

    static func navigationDisposition(
        detachFinalizationOnSessionSwitch: Bool,
        finalizationID: UUID?,
        sourceSessionID: String?,
        currentSessionID: String?
    ) -> ChatSpeechNavigationDisposition {
        if detachFinalizationOnSessionSwitch,
           finalizationID != nil,
           sourceSessionID != currentSessionID {
            return .detachFinalization
        }
        return .cancelAndPreserve
    }

    /// Idle Chat and transcription-only Chat do not own the shared microphone.
    /// Recording or starting capture still releases that hardware.
    static func cleanupPlan(
        isRecording: Bool,
        isStartingRecording: Bool,
        isTranscribing: Bool
    ) -> ChatSpeechCleanupPlan {
        let ownsMicrophone = isRecording || isStartingRecording
        return ChatSpeechCleanupPlan(
            releasesOwnedMicrophone: ownsMicrophone,
            preservesBackendCapture: ownsMicrophone || isTranscribing
        )
    }
}

@MainActor
enum ChatSpeechCaptureCleanup {
    /// Stops and discards only when `plan` says Chat owns the microphone.
    /// Returns the stopped file URL, or nil when hardware is left alone.
    static func releaseOwnedMicrophone(
        _ microphone: any ChatSpeechMicrophoneControlling,
        plan: ChatSpeechCleanupPlan
    ) async -> URL? {
        guard plan.releasesOwnedMicrophone else { return nil }
        let audioURL = try? await microphone.stop()
        microphone.discard()
        return audioURL
    }
}
