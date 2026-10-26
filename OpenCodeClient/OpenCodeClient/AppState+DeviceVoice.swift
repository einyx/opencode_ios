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
        // The turn may be the answer to a confirmation the agent asked for.
        // The flag that says "a confirmation is outstanding" goes with it.
        clearDeviceVoiceConfirmation()
        return await submitCarTurn(transcript, speaks: false)
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

    /// The question the agent asked at the end of the last turn.
    ///
    /// The agent's structured reply can end with a confirmation it needs
    /// before it acts. The voice engine asks it out loud, and the answer
    /// becomes the next thing the user said.
    func deviceVoiceConfirmationPrompt() -> String? {
        guard carPhase == .awaitingConfirmation else { return nil }
        return carLastResponse?.confirmation?.prompt
    }

    /// Clears the pending confirmation once the user has answered it.
    ///
    /// The answer arrives as the next turn, so the flag that says "a
    /// confirmation is outstanding" has to go with it.
    func clearDeviceVoiceConfirmation() {
        guard carPhase == .awaitingConfirmation else { return }
        carPhase = .idle
        carLastResponse = nil
        let key = carContextKey
        guard var record = carSessionsByContext[key] else { return }
        record.pendingConfirmationID = nil
        carSessionsByContext[key] = record
        persistCarSessions()
    }
}
