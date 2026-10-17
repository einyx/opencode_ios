import Foundation

enum BackgroundVoiceSceneKind: Equatable, Sendable {
    case active
    case inactive
    case background
    case other
}

enum BackgroundVoiceLiveKind: Equatable, Sendable {
    case none
    case connecting
    case captureRunning
    case closing
}

enum BackgroundVoiceAction: Equatable, Sendable {
    case ignore
    case holdOpenConnections
    case cancelPendingThenCleanup
    case legacyCleanup
}

enum BackgroundVoiceHoldKind: Equatable, Sendable {
    case systemInterruption
    case headphoneRemoved
}

enum CarLiveCaptureSessionPlan {
    static let optionNames = ["defaultToSpeaker", "allowBluetoothHFP"]

    static func preservesOtherApps(_ names: [String] = optionNames) -> Bool {
        names.allSatisfy { $0 != "mixWithOthers" && $0 != "duckOthers" }
    }
}

enum BackgroundVoicePolicy {
    static let appDeactivationSource = 1

    static func liveKind(
        phase: CarLivePhase,
        captureGeneration: UInt64,
        connectInFlight: Bool,
        closing: Bool
    ) -> BackgroundVoiceLiveKind {
        if closing || phase == .closing {
            return .closing
        }
        if (phase == .listening || phase == .speaking) && captureGeneration != 0 {
            return .captureRunning
        }
        if phase == .connecting || connectInFlight {
            return .connecting
        }
        return .none
    }

    static func action(
        scene: BackgroundVoiceSceneKind,
        live: BackgroundVoiceLiveKind,
        connected: Bool
    ) -> BackgroundVoiceAction {
        switch scene {
        case .inactive, .active, .other:
            return .ignore
        case .background:
            switch live {
            case .captureRunning:
                return connected ? .holdOpenConnections : .legacyCleanup
            case .connecting:
                return .cancelPendingThenCleanup
            case .none, .closing:
                return .legacyCleanup
            }
        }
    }

    static func silenceEndsSession(frameCount: Int) -> Bool {
        _ = frameCount
        return false
    }

    static func closesForSystemInterruption(sourceRaw: Int, interruptionReasonRaw: Int?) -> Bool {
        sourceRaw != appDeactivationSource && interruptionReasonRaw != nil
    }

    static func closesForLegacyInterruptionBegan(_ began: Bool) -> Bool {
        began
    }

    static func closesForHeadsetDisconnect(oldDeviceUnavailable: Bool, previousPorts: [String]) -> Bool {
        oldDeviceUnavailable && previousPorts.contains(where: CarLiveAudioRoute.isHeadset)
    }

    static func closesForHeadsetRoute(
        oldDeviceUnavailable: Bool,
        previousPorts: [String],
        interruptionBegan: Bool
    ) -> Bool {
        _ = interruptionBegan
        return closesForHeadsetDisconnect(oldDeviceUnavailable: oldDeviceUnavailable, previousPorts: previousPorts)
    }

    static func shouldReopenMicrophone(systemRecommendsResume: Bool) -> Bool {
        _ = systemRecommendsResume
        return false
    }

    static func shouldApplyAudioHold(
        alreadyHeld: Bool,
        eventGeneration: UInt64,
        currentGeneration: UInt64,
        sessionLive: Bool,
        closing: Bool
    ) -> Bool {
        !alreadyHeld && eventGeneration == currentGeneration && sessionLive && !closing && currentGeneration != 0
    }

    static func shouldSkipForegroundRestore(
        armed: Bool,
        connected: Bool,
        sseConnected: Bool,
        sshEnabled: Bool,
        sshConnected: Bool
    ) -> Bool {
        guard armed, connected, sseConnected else { return false }
        if sshEnabled && !sshConnected { return false }
        return true
    }

    static func shouldRecoverGraph(
        intendedRunning: Bool,
        held: Bool,
        recoveryStarts: Int,
        engineRunning: Bool
    ) -> Bool {
        intendedRunning && !held && recoveryStarts == 0 && !engineRunning
    }
}
