//
//  WatchSpeechOutput.swift
//  OpenCodeWatch
//

import AVFoundation
import Foundation

/// Speech output on the watch.
///
/// The watch speaks the answer itself: the phone recognises what the watch's
/// microphone hears and sends the words back, so the voice comes from the
/// wrist. Nothing is streamed as audio — the words are synthesised here, on
/// the device.
@MainActor
final class WatchSpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Speaks the text and returns when the utterance is done.
    func speak(_ text: String) async {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.language(for: trimmed))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    /// Stops the current utterance.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    private func finish() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    /// Chinese when the words are Chinese, English otherwise.
    private static func language(for text: String) -> String {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } ? "zh-CN" : "en-US"
    }
}
