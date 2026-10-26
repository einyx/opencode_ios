//
//  AppState+Speech.swift
//  OpenCodeClient
//

import Foundation
import os

/// Which surface is asking for a transcription. It is a telemetry tag.
enum SpeechSurface: String {
    case chat
    case car
}

/// Speech recognition, entirely on the device.
///
/// The app has one recognizer: Apple's, pinned to on-device recognition. The
/// audio never leaves the device, and there is no credential to configure.
extension AppState {
    /// Transcribes a recorded audio file on the device.
    func transcribeAudio(
        audioFileURL: URL,
        engine: SpeechRecognitionEngine,
        surface: SpeechSurface,
        onPartialTranscript: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        Self.logger.notice("[SpeechProfile] surface=\(surface.rawValue, privacy: .public) strategy=appleOnDevice phase=transcribe outcome=started")
        do {
            let transcriber = appleSpeechTranscriber
            let text = try await transcriber.transcribeFile(at: audioFileURL, onPartial: onPartialTranscript)
            let elapsed = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.notice("[SpeechProfile] surface=\(surface.rawValue, privacy: .public) strategy=appleOnDevice phase=transcribe outcome=succeeded ms=\(elapsed, privacy: .public)")
            return text
        } catch {
            let elapsed = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
            Self.logger.error("[SpeechProfile] surface=\(surface.rawValue, privacy: .public) strategy=appleOnDevice phase=transcribe outcome=failed ms=\(elapsed, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
