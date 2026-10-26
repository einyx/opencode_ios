import Foundation

extension AppState {
    func handleApplicationScene(_ kind: BackgroundVoiceSceneKind) {
        switch kind {
        case .inactive, .other:
            return
        case .active:
            backgroundVoiceScene = .active
            backgroundCleanupApplied = false
        case .background:
            backgroundVoiceScene = .background
            let live = BackgroundVoicePolicy.liveKind(
                isVoiceRunning: deviceVoice.isListening,
                connectInFlight: deviceVoice.isStarting,
                closing: false
            )
            #if os(iOS)
            // Keep the phone's existing audio hold policy when it is capturing.
            // Watch alone preserves the route without granting background time.
            if watchPhoneBridge?.isActive == true, !deviceVoice.isListening, !deviceVoice.isStarting { return }
            #endif
            switch BackgroundVoicePolicy.action(scene: .background, live: live, connected: isConnected) {
            case .ignore:
                return
            case .holdOpenConnections:
                holdingBackgroundVoice = true
                skipForegroundConnectionRestore = true
                foregroundHoldRestoreConsumed = false
                backgroundCleanupApplied = false
            case .cancelPendingThenCleanup:
                guard !backgroundCleanupApplied else { return }
                cancelPendingVoiceCapture()
                applyBackgroundDisconnect()
            case .legacyCleanup:
                guard !backgroundCleanupApplied else { return }
                applyBackgroundDisconnect()
            }
        }
    }

    func restoreConnectionsAfterForeground() async {
        backgroundVoiceScene = .active
        backgroundCleanupApplied = false
        let linksStillOpen = BackgroundVoicePolicy.shouldSkipForegroundRestore(
            armed: true,
            connected: isConnected,
            sseConnected: statusStreamConnected,
            sshEnabled: sshTunnelManager.config.isEnabled,
            sshConnected: sshTunnelManager.status == .connected
        )
        if skipForegroundConnectionRestore && linksStillOpen {
            skipForegroundConnectionRestore = false
            holdingBackgroundVoice = false
            foregroundHoldRestoreConsumed = true
            return
        }
        if foregroundHoldRestoreConsumed && linksStillOpen {
            return
        }
        foregroundHoldRestoreConsumed = false
        skipForegroundConnectionRestore = false
        holdingBackgroundVoice = false
        #if !os(visionOS)
        if sshTunnelManager.config.isEnabled, sshTunnelManager.status != .connected {
            await sshTunnelManager.connect()
        }
        #endif
        await refresh()
        #if !os(visionOS)
        if sshTunnelManager.config.isEnabled, !isConnected {
            sshTunnelManager.disconnect()
            await sshTunnelManager.connect()
            await refresh()
        }
        #endif
        if isConnected {
            await processPendingDeepLinkIfPossible()
            await retryClientCapabilityOutbox()
        } else {
            disconnectSSE()
        }
    }

    /// The audio route is gone (headphones removed, a system interruption).
    /// The voice cannot continue on a route that no longer exists.
    func noteAudioHold(epoch: UInt64) async {
        guard epoch == backgroundVoiceEpoch else { return }
        guard deviceVoice.isListening else { return }
        await deviceVoice.stop()
    }

    /// The voice session ended on its own.
    func noteLiveEnded(epoch: UInt64) {
        guard epoch == backgroundVoiceEpoch else { return }
        guard backgroundVoiceScene == .background else { return }
        guard !deviceVoice.isListening else { return }
        releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: epoch)
    }

    func bindBackgroundVoiceHold(epoch: UInt64) {
        deviceVoice.onAudioRouteLost = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.noteAudioHold(epoch: epoch)
            }
        }
    }

    func invalidateBackgroundVoicePolicy() {
        backgroundVoiceEpoch &+= 1
        holdingBackgroundVoice = false
        skipForegroundConnectionRestore = false
        foregroundHoldRestoreConsumed = false
    }

    func releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: UInt64) {
        guard expectedEpoch == backgroundVoiceEpoch else { return }
        guard backgroundVoiceScene == .background else { return }
        #if os(iOS)
        guard watchPhoneBridge?.isActive != true else { return }
        #endif
        applyBackgroundDisconnect()
    }

    func cancelPendingVoiceCapture() {
        Task { @MainActor in
            await deviceVoice.stop()
        }
    }

    func applyBackgroundDisconnect() {
        guard !applyingBackgroundCleanup else { return }
        applyingBackgroundCleanup = true
        defer { applyingBackgroundCleanup = false }
        backgroundCleanupApplied = true
        holdingBackgroundVoice = false
        skipForegroundConnectionRestore = false
        foregroundHoldRestoreConsumed = false
        invalidateDeepLinkRoute(keepPending: true)
        if isConnected {
            isConnected = false
        }
        disconnectSSE()
        #if !os(visionOS)
        if sshTunnelManager.config.isEnabled {
            sshTunnelManager.disconnect()
        }
        #endif
    }
}
