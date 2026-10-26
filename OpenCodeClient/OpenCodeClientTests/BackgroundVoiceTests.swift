import Foundation
import Testing
@testable import OpenCodeClient

/// The background policy is engine-agnostic: it decides what happens when
/// the app goes to the background while a voice session is running.
struct BackgroundVoicePolicyTests {
    @Test func backgroundHoldsOnlyAStartedCapture() {
        let running = BackgroundVoicePolicy.liveKind(isVoiceRunning: true, connectInFlight: false, closing: false)
        #expect(running == .captureRunning)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: running, connected: true) == .holdOpenConnections)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: running, connected: false) == .legacyCleanup)

        let connecting = BackgroundVoicePolicy.liveKind(isVoiceRunning: false, connectInFlight: true, closing: false)
        #expect(connecting == .connecting)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: connecting, connected: true) == .cancelPendingThenCleanup)

        let closing = BackgroundVoicePolicy.liveKind(isVoiceRunning: true, connectInFlight: false, closing: true)
        #expect(closing == .closing)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: closing, connected: true) == .legacyCleanup)

        let idle = BackgroundVoicePolicy.liveKind(isVoiceRunning: false, connectInFlight: false, closing: false)
        #expect(idle == .none)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: idle, connected: true) == .legacyCleanup)
        #expect(BackgroundVoicePolicy.action(scene: .inactive, live: running, connected: true) == .ignore)
        #expect(BackgroundVoicePolicy.action(scene: .active, live: running, connected: true) == .ignore)
    }

    @Test func silenceAndLockScreenDoNotEndOrReopen() {
        #expect(BackgroundVoicePolicy.silenceEndsSession(frameCount: 0) == false)
        #expect(BackgroundVoicePolicy.silenceEndsSession(frameCount: 4) == false)
        #expect(BackgroundVoicePolicy.closesForSystemInterruption(sourceRaw: BackgroundVoicePolicy.appDeactivationSource, interruptionReasonRaw: 1) == false)
        #expect(BackgroundVoicePolicy.closesForSystemInterruption(sourceRaw: 2, interruptionReasonRaw: nil) == false)
        #expect(BackgroundVoicePolicy.closesForSystemInterruption(sourceRaw: 2, interruptionReasonRaw: 1))
        #expect(BackgroundVoicePolicy.closesForLegacyInterruptionBegan(true))
        #expect(BackgroundVoicePolicy.closesForLegacyInterruptionBegan(false) == false)
        #expect(BackgroundVoicePolicy.shouldReopenMicrophone(systemRecommendsResume: true) == false)
        #expect(BackgroundVoicePolicy.closesForHeadsetDisconnect(oldDeviceUnavailable: true, previousPorts: ["BluetoothHFP"]))
        #expect(BackgroundVoicePolicy.closesForHeadsetDisconnect(oldDeviceUnavailable: true, previousPorts: ["Speaker"]) == false)
        #expect(BackgroundVoicePolicy.closesForHeadsetDisconnect(oldDeviceUnavailable: false, previousPorts: ["Headphones"]) == false)
        #expect(BackgroundVoicePolicy.closesForHeadsetRoute(oldDeviceUnavailable: true, previousPorts: ["BluetoothHFP"], interruptionBegan: false))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["USBAudio"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["AirPlay"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["CarAudio"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["USBAudio", "Speaker"]))
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["Speaker"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["BuiltInSpeaker"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: true, previousPorts: ["Receiver"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: false, previousPorts: ["USBAudio"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: false, previousPorts: ["AirPlay"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: false, previousPorts: ["CarAudio"]) == false)
        #expect(CarLiveAudioRoute.closesForExternalOutputDisconnect(oldDeviceUnavailable: false, previousPorts: ["Headphones"]) == false)
        #expect(CarLiveCaptureSessionPlan.preservesOtherApps())
        #expect(CarLiveCaptureSessionPlan.preservesOtherApps(["mixWithOthers"]) == false)
        #expect(CarLiveCaptureSessionPlan.preservesOtherApps(["duckOthers"]) == false)
    }

    @Test func repeatAndStaleHoldDoNotApply() {
        #expect(BackgroundVoicePolicy.shouldApplyAudioHold(alreadyHeld: false, eventGeneration: 4, currentGeneration: 4, sessionLive: true, closing: false))
        #expect(BackgroundVoicePolicy.shouldApplyAudioHold(alreadyHeld: true, eventGeneration: 4, currentGeneration: 4, sessionLive: true, closing: false) == false)
        #expect(BackgroundVoicePolicy.shouldApplyAudioHold(alreadyHeld: false, eventGeneration: 3, currentGeneration: 4, sessionLive: true, closing: false) == false)
        #expect(BackgroundVoicePolicy.shouldApplyAudioHold(alreadyHeld: false, eventGeneration: 4, currentGeneration: 4, sessionLive: true, closing: true) == false)
        #expect(BackgroundVoicePolicy.shouldApplyAudioHold(alreadyHeld: false, eventGeneration: 0, currentGeneration: 0, sessionLive: false, closing: false) == false)
    }

    @Test func foregroundSkipRequiresLiveLinks() {
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: true, connected: true, sseConnected: true, sshEnabled: true, sshConnected: true))
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: true, connected: true, sseConnected: true, sshEnabled: false, sshConnected: false))
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: true, connected: true, sseConnected: false, sshEnabled: false, sshConnected: false) == false)
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: false, connected: true, sseConnected: true, sshEnabled: false, sshConnected: false) == false)
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: true, connected: false, sseConnected: true, sshEnabled: false, sshConnected: false) == false)
        #expect(BackgroundVoicePolicy.shouldSkipForegroundRestore(armed: true, connected: true, sseConnected: true, sshEnabled: true, sshConnected: false) == false)
    }

    @Test func graphRecoveryContractUnchanged() {
        let restart = CarLivePlaybackRestart(
            queuedCapture: 1,
            currentCapture: 1,
            queuedPlayback: 1,
            currentPlayback: 1,
            intendedRunning: true,
            engineRunning: true,
            playerAttached: true,
            hasAudio: false
        )
        #expect(restart.shouldRestartFromClear == false)
        #expect(restart.shouldPlayScheduled == false)
        #expect(BackgroundVoicePolicy.shouldRecoverGraph(intendedRunning: true, held: true, recoveryStarts: 0, engineRunning: false) == false)
        #expect(BackgroundVoicePolicy.shouldRecoverGraph(intendedRunning: true, held: false, recoveryStarts: 0, engineRunning: false))
    }
}
