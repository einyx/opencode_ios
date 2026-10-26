//
//  AppState+DeviceVoice.swift
//  OpenCodeClient
//

import Foundation

/// The state is what the device voice engine talks to: it runs the turn
/// against the user's own server and speaks the answer through the device's
/// own speech synthesiser.
extension AppState: DeviceVoiceHost {
    /// Runs one turn against the user's own server and returns the text of
    /// the answer. The answer is not spoken here — the engine decides, so the
    /// watch can ask for the text and speak it on the wrist.
    func runDeviceVoiceTurn(_ transcript: String) async -> String? {
        await submitCarTurn(transcript, speaks: false)
    }

    /// Speaks the answer on this device.
    func speakDeviceVoiceReply(_ text: String) async {
        await carSpeechOutput.speak(text)
    }

    /// Answers a permission the agent asked for during a voice turn.
    ///
    /// "Yes" allows it once and "no" refuses it — the same two answers the
    /// permission card offers.
    func answerDeviceVoicePermission(_ permission: PendingPermission, allow: Bool) async {
        await respondPermission(permission, response: allow ? .once : .reject)
        await carSpeechOutput.speak(L10n.t(allow ? .carVoicePermissionAllowed : .carVoicePermissionRefused))
    }

    /// Stops the current utterance.
    func stopDeviceVoiceReply() {
        carSpeechOutput.stop()
    }

    /// Hands an answer to the watch, which speaks it on the wrist.
    func deliverDeviceVoiceReplyToWatch(_ text: String) async {
        #if os(iOS)
        watchPhoneBridge?.deliverVoiceReply(text)
        #endif
    }
}
