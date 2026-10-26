import SwiftUI
import os
#if os(iOS) || os(visionOS)
@preconcurrency import AVFoundation
#endif

/// Mic-button voice input for the chat composer.
///
/// The composer records the microphone, transcribes the recording on the
/// device and puts the words in the draft. There is no cloud path: the
/// audio never leaves the device and there is no credential to configure.
/// UI states (`isRecording`, `isTranscribing`, `isStartingRecording`,
/// `speechError`) and the `@State` fields live on `ChatTabView` itself —
/// SwiftUI requires `@State` on the containing struct — and this extension
/// hosts the lifecycle methods.

nonisolated enum ChatSpeechOwner: Hashable {
    case session(String)
    case noSession

    init(sessionID: String?) {
        if let sessionID {
            self = .session(sessionID)
        } else {
            self = .noSession
        }
    }
}

enum PendingChatSpeechAudio {
    case file(URL, prefix: String)

    var prefix: String {
        switch self {
        case .file(_, let prefix): prefix
        }
    }
}

extension ChatTabView {
    static func mergedSpeechInput(prefix: String, transcript: String) -> String {
        ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript)
    }

    static func speechFailureInput(prefix: String, lastPartialTranscript: String) -> String {
        mergedSpeechInput(prefix: prefix, transcript: lastPartialTranscript)
    }

    static func requestMicrophonePermissionForRecording() async -> Bool {
        #if os(iOS) || os(visionOS)
        let application = AVAudioApplication.shared
        switch application.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
        #else
        return true
        #endif
    }

    func applySpeechDraft(
        prefix: String,
        transcript: String,
        sourceSessionID: String?,
        sourceHost: HostRequestSnapshot
    ) {
        let origin = ComposerWriteOrigin(sessionID: sourceSessionID, host: sourceHost)
        let visible = ComposerOwnedWrite.sameVisibleComposer(
            origin: origin,
            currentSessionID: state.currentSessionID,
            currentHostID: state.currentHostProfileID
        )
        if visible, !canAssignComposerText {
            deferSpeechDraftWhileMarked(prefix: prefix, transcript: transcript, origin: origin)
            return
        }
        if visible {
            publishSpeechTranscript(transcript, prefix: prefix, origin: origin)
            return
        }
        let merged = ComposerOwnedWrite.speechIntoSourceDraft(
            prefix: prefix,
            transcript: transcript,
            origin: origin,
            state: state
        )
        if sourceSessionID == nil {
            completedSpeechDraftByOwner[ChatSpeechOwner(sessionID: nil)] = merged
        }
    }

    func storePendingSpeechAudio(_ pending: PendingChatSpeechAudio, owner: ChatSpeechOwner) {
        if let existing = pendingSpeechAudioByOwner.removeValue(forKey: owner) {
            discardPendingSpeechAudio(existing)
        }
        pendingSpeechAudioByOwner[owner] = pending
    }

    func discardPendingSpeechAudio(_ pending: PendingChatSpeechAudio) {
        switch pending {
        case .file(let audioURL, _):
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    func startSpeechAudioLevelConsumer() {
        speechAudioLevelTask?.cancel()
        speechAudioLevel = 0
        let levels = microphone.audioLevel
        speechAudioLevelTask = Task {
            for await level in levels {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    speechAudioLevel = level
                }
            }
        }
    }

    func stopSpeechAudioLevelConsumer() {
        speechAudioLevelTask?.cancel()
        speechAudioLevelTask = nil
        speechAudioLevel = 0
    }

    func stopSpeechForNavigation() async {
        await stopSpeechForNavigation(detachFinalizationOnSessionSwitch: true)
    }

    private func stopSpeechForNavigation(detachFinalizationOnSessionSwitch: Bool) async {
        let disposition = ChatSpeechRouting.navigationDisposition(
            detachFinalizationOnSessionSwitch: detachFinalizationOnSessionSwitch,
            finalizationID: speechFinalizationID,
            sourceSessionID: speechOriginSessionID,
            currentSessionID: state.currentSessionID
        )
        if disposition == .detachFinalization {
            speechRetryID = nil
            speechRetrySessionID = nil
            stopSpeechAudioLevelConsumer()
            isRecording = false
            isTranscribing = false
            isStartingRecording = false
            isRetryingSpeech = false
            return
        }

        let originSessionID = speechOriginSessionID
        let owner = ChatSpeechOwner(sessionID: originSessionID)
        let prefix = recordingInputPrefix
        let cleanupPlan = ChatSpeechRouting.cleanupPlan(
            isRecording: isRecording,
            isStartingRecording: isStartingRecording,
            isTranscribing: isTranscribing
        )
        speechStartID = nil
        speechFinalizationID = nil
        speechRetryID = nil
        speechRetrySessionID = nil
        stopSpeechAudioLevelConsumer()
        let audioURL = await ChatSpeechCaptureCleanup.releaseOwnedMicrophone(microphone, plan: cleanupPlan)
        // The engine is closed from here on, so the capture state can clear.
        state.chatSpeechCaptureActive = false

        speechOriginSessionID = nil
        isRecording = false
        isTranscribing = false
        isStartingRecording = false
        isRetryingSpeech = false

        guard cleanupPlan.preservesBackendCapture else {
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
            return
        }
        if let audioURL {
            storePendingSpeechAudio(.file(audioURL, prefix: prefix), owner: owner)
        }
    }

    func stopSpeechForBackground() async {
        await stopSpeechForNavigation(detachFinalizationOnSessionSwitch: false)
    }

    func toggleRecording() async {
        guard speechConfigurationCleanupTask == nil else { return }
        if isRecording {
            let finalizationID = UUID()
            speechFinalizationID = finalizationID
            let stoppingMicrophone = microphone
            let originSessionID = speechOriginSessionID
            let owner = ChatSpeechOwner(sessionID: originSessionID)
            let prefix = recordingInputPrefix
            let engine = activeSpeechStrategy
            stopSpeechAudioLevelConsumer()
            let stopStart = ProcessInfo.processInfo.systemUptime
            let audioURL = try? await stoppingMicrophone.stop()
            // The engine is closed from here on, so the capture state can clear.
            state.chatSpeechCaptureActive = false
            stoppingMicrophone.discard()
            guard SpeechAttemptGate.owns(finalizationID, activeAttemptID: speechFinalizationID),
                  speechOriginSessionID == originSessionID else {
                if let audioURL {
                    storePendingSpeechAudio(.file(audioURL, prefix: prefix), owner: owner)
                }
                await stopSpeechForNavigation(detachFinalizationOnSessionSwitch: false)
                return
            }
            isRecording = false
            // Boundary event: the microphone is closing right now, so the
            // microphone guard does not apply.
            DesignHaptics.fire(.recordingStopped, microphoneOpen: state.isMicrophoneCaptureActive)
            Self.logger.notice("[SpeechProfile] capture stopped ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - stopStart) * 1000)), privacy: .public)")

            isTranscribing = originSessionID == state.currentSessionID

            guard let audioURL else {
                isTranscribing = false
                speechFinalizationID = nil
                speechOriginSessionID = nil
                if originSessionID == state.currentSessionID {
                    speechError = L10n.t(.carTranscriptionFailed)
                }
                return
            }
            storePendingSpeechAudio(.file(audioURL, prefix: prefix), owner: owner)
            do {
                let transcript = try await state.transcribeAudio(
                    audioFileURL: audioURL,
                    engine: engine,
                    surface: .chat
                )
                guard SpeechAttemptGate.owns(finalizationID, activeAttemptID: speechFinalizationID),
                      speechOriginSessionID == originSessionID else { return }
                applySpeechDraft(
                    prefix: prefix,
                    transcript: transcript,
                    sourceSessionID: originSessionID,
                    sourceHost: speechOriginHost ?? state.captureHostRequestSnapshot()
                )
                clearPreservedSpeechAudio(for: owner)
            } catch {
                guard SpeechAttemptGate.owns(finalizationID, activeAttemptID: speechFinalizationID),
                      speechOriginSessionID == originSessionID else { return }
                Self.logger.error("[SpeechProfile] chat transcribe failed error=\(error.localizedDescription, privacy: .public)")
                if originSessionID == state.currentSessionID {
                    speechError = error.localizedDescription
                }
            }
            if speechFinalizationID == finalizationID {
                speechFinalizationID = nil
                speechOriginSessionID = nil
                isTranscribing = false
            }
        } else {
            guard !isStartingRecording else { return }
            // The level stream belongs to the microphone instance, so it is
            // recreated per capture and repeated start/stop cycles keep
            // publishing real levels for the waveform.
            let startingMicrophone = DeviceMicrophone()
            microphone = startingMicrophone
            let engine = state.speechRecognitionEngine
            let originSessionID = state.currentSessionID
            let originHost = state.captureHostRequestSnapshot()
            let startID = UUID()
            speechStartID = startID
            speechOriginSessionID = originSessionID
            speechOriginHost = originHost
            isStartingRecording = true
            let permissionStart = ProcessInfo.processInfo.systemUptime
            let allowed = await Self.requestMicrophonePermissionForRecording()
            Self.logger.notice("[SpeechProfile] microphone permission allowed=\(allowed, privacy: .public) ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - permissionStart) * 1000)), privacy: .public)")
            guard allowed else {
                guard SpeechAttemptGate.accepts(
                    startID,
                    activeAttemptID: speechStartID,
                    originatingSessionID: originSessionID,
                    currentSessionID: state.currentSessionID
                ) else { return }
                speechStartID = nil
                speechOriginSessionID = nil
                isStartingRecording = false
                speechError = L10n.t(.chatMicrophoneDenied)
                return
            }
            guard SpeechAttemptGate.accepts(
                startID,
                activeAttemptID: speechStartID,
                originatingSessionID: originSessionID,
                currentSessionID: state.currentSessionID
            ) else { return }
            let startRecordingStart = ProcessInfo.processInfo.systemUptime
            do {
                speechRetryID = nil
                recordingInputPrefix = inputText
                speechDraft.begin(prefix: inputText, sessionID: originSessionID)
                activeSpeechStrategy = engine
                startSpeechAudioLevelConsumer()

                // Acknowledge the tap and publish the capture state *before* the
                // microphone opens. The haptic lands ahead of the capture window
                // rather than inside it, and `isMicrophoneCaptureActive` is true
                // for the whole time the engine is live.
                DesignHaptics.fire(.recordingStarted, microphoneOpen: state.isMicrophoneCaptureActive)
                state.chatSpeechCaptureActive = true

                try await startingMicrophone.start()

                guard SpeechAttemptGate.accepts(
                    startID,
                    activeAttemptID: speechStartID,
                    originatingSessionID: originSessionID,
                    currentSessionID: state.currentSessionID
                ) else {
                    let audioURL = try? await startingMicrophone.stop()
                    // The engine is closed from here on, so the capture state can clear.
                    state.chatSpeechCaptureActive = false
                    // Close the `.recordingStarted` pair: the tap was
                    // acknowledged, and the attempt is over.
                    DesignHaptics.fire(.recordingStopped, microphoneOpen: state.isMicrophoneCaptureActive)
                    startingMicrophone.discard()
                    let owner = ChatSpeechOwner(sessionID: originSessionID)
                    if let audioURL {
                        storePendingSpeechAudio(.file(audioURL, prefix: recordingInputPrefix), owner: owner)
                    }
                    return
                }
                isRecording = true
                speechStartID = nil
                isStartingRecording = false
                Self.logger.notice("[SpeechProfile] capture started strategy=onDevice ms=\(max(0, Int((ProcessInfo.processInfo.systemUptime - startRecordingStart) * 1000)), privacy: .public)")
            } catch {
                let audioURL = try? await startingMicrophone.stop()
                // The engine is closed from here on, so the capture state can clear.
                state.chatSpeechCaptureActive = false
                // Close the `.recordingStarted` pair: the tap was acknowledged and
                // the attempt is over. The failure itself is reported by
                // the error channel, not by this haptic.
                DesignHaptics.fire(.recordingStopped, microphoneOpen: state.isMicrophoneCaptureActive)
                startingMicrophone.discard()
                let owner = ChatSpeechOwner(sessionID: originSessionID)
                if let audioURL {
                    storePendingSpeechAudio(.file(audioURL, prefix: recordingInputPrefix), owner: owner)
                }
                let shouldReportError = SpeechAttemptGate.accepts(
                    startID,
                    activeAttemptID: speechStartID,
                    originatingSessionID: originSessionID,
                    currentSessionID: state.currentSessionID
                )
                if shouldReportError {
                    stopSpeechAudioLevelConsumer()
                    speechStartID = nil
                    speechOriginSessionID = nil
                    isStartingRecording = false
                }
                guard shouldReportError else { return }
                Self.logger.error("[SpeechProfile] capture start failed error=\(error.localizedDescription, privacy: .public)")
                speechError = error.localizedDescription
            }
        }
    }

    func abortSpeechRecognition() async {
        let cleanup = prepareSpeechAbort()
        await cleanup()
    }

    /// Revoke callback ownership synchronously, before a cleanup task can yield.
    func prepareSpeechAbort() -> @MainActor () async -> Void {
        let originSessionID = speechOriginSessionID
        let owner = ChatSpeechOwner(sessionID: originSessionID)
        // Capture and detach before releasing the microphone: an invalidated
        // finalization may finish during that await and clear the capture.
        let prefix = recordingInputPrefix
        let stoppingMicrophone = microphone
        let cleanupPlan = ChatSpeechRouting.cleanupPlan(
            isRecording: isRecording,
            isStartingRecording: isStartingRecording,
            isTranscribing: isTranscribing
        )
        speechStartID = nil
        speechFinalizationID = nil
        speechRetryID = nil
        speechRetrySessionID = nil
        stopSpeechAudioLevelConsumer()

        return {
            let audioURL = await ChatSpeechCaptureCleanup.releaseOwnedMicrophone(stoppingMicrophone, plan: cleanupPlan)
            // The engine is closed from here on, so the capture state can clear.
            state.chatSpeechCaptureActive = false

            speechOriginSessionID = nil
            isRecording = false
            isTranscribing = false
            isStartingRecording = false
            isRetryingSpeech = false

            if let audioURL {
                storePendingSpeechAudio(.file(audioURL, prefix: prefix), owner: owner)
            }
        }
    }

    func retryPreservedSpeechAudio() async {
        guard speechConfigurationCleanupTask == nil, state.isChatSpeechConfigured else { return }
        let retrySessionID = state.currentSessionID
        let retryHost = state.captureHostRequestSnapshot()
        speechOriginHost = retryHost
        let owner = ChatSpeechOwner(sessionID: retrySessionID)
        guard let pending = pendingSpeechAudioByOwner[owner] else { return }
        let retryID = UUID()
        speechRetryID = retryID
        speechRetrySessionID = retrySessionID
        isRetryingSpeech = true
        defer {
            if speechRetryID == retryID {
                speechRetryID = nil
                speechRetrySessionID = nil
                isRetryingSpeech = false
            }
        }

        let prefix = pending.prefix
        speechDraft.ensureAnchor(prefix)
        do {
            let transcript: String
            switch pending {
            case .file(let audioURL, _):
                transcript = try await state.transcribeAudio(
                    audioFileURL: audioURL,
                    engine: activeSpeechStrategy,
                    surface: .chat
                )
            }
            guard SpeechAttemptGate.accepts(
                retryID,
                activeAttemptID: speechRetryID,
                originatingSessionID: retrySessionID,
                currentSessionID: state.currentSessionID
            ), speechRetrySessionID == retrySessionID else { return }
            speechRetryID = nil
            speechRetrySessionID = nil
            isRetryingSpeech = false
            publishSpeechTranscript(
                transcript,
                prefix: prefix,
                origin: ComposerWriteOrigin(sessionID: retrySessionID, host: retryHost)
            )
            clearPreservedSpeechAudio(for: owner)
        } catch {
            guard SpeechAttemptGate.accepts(
                retryID,
                activeAttemptID: speechRetryID,
                originatingSessionID: retrySessionID,
                currentSessionID: state.currentSessionID
            ), speechRetrySessionID == retrySessionID else { return }
            Self.logger.error("[SpeechProfile] speech retry failed error=\(error.localizedDescription, privacy: .public)")
            speechError = error.localizedDescription
        }
    }

    func clearPreservedSpeechAudio() {
        clearPreservedSpeechAudio(for: ChatSpeechOwner(sessionID: state.currentSessionID))
    }

    func clearPreservedSpeechAudio(for owner: ChatSpeechOwner) {
        if let pending = pendingSpeechAudioByOwner.removeValue(forKey: owner) {
            discardPendingSpeechAudio(pending)
        }
    }
}
