import Foundation

extension AppState {
    func handleApplicationScene(_ kind: BackgroundVoiceSceneKind) {
        switch kind {
        case .inactive, .other:
            return
        case .active:
            backgroundVoiceScene = .active
            backgroundCleanupApplied = false
            carLive?.blocksNewCapture = false
        case .background:
            backgroundVoiceScene = .background
            let live = BackgroundVoicePolicy.liveKind(
                phase: carLive?.phase ?? .idle,
                captureGeneration: carLive?.captureGenerationForPolicy ?? 0,
                connectInFlight: carLiveConnectTask != nil || carLive?.phase == .connecting,
                closing: carLive?.isClosingForPolicy == true || carLive?.phase == .closing
            )
            #if os(iOS)
            // Keep the phone's existing audio hold policy when it is capturing.
            // Watch alone preserves the route without granting background time.
            if watchPhoneBridge?.isActive == true,
               carLive?.phase != .listening, carLive?.phase != .speaking,
               carLive?.phase != .connecting, carLiveConnectTask == nil { return }
            #endif
            switch BackgroundVoicePolicy.action(scene: .background, live: live, connected: isConnected) {
            case .ignore:
                return
            case .holdOpenConnections:
                holdingBackgroundVoice = true
                skipForegroundConnectionRestore = true
                foregroundHoldRestoreConsumed = false
                backgroundCleanupApplied = false
                carLive?.blocksNewCapture = false
            case .cancelPendingThenCleanup:
                guard !backgroundCleanupApplied else { return }
                carLive?.blocksNewCapture = true
                cancelPendingCarLiveCapture()
                applyBackgroundDisconnect()
            case .legacyCleanup:
                guard !backgroundCleanupApplied else { return }
                carLive?.blocksNewCapture = true
                applyBackgroundDisconnect()
            }
        }
    }

    func restoreConnectionsAfterForeground() async {
        carLive?.blocksNewCapture = false
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

    func noteAudioHold(epoch: UInt64, generation: UInt64) async {
        guard epoch == backgroundVoiceEpoch else { return }
        guard let carLive else { return }
        guard carLive.captureGenerationForPolicy == generation, generation != 0 else { return }
        guard carLive.phase == .listening || carLive.phase == .speaking else { return }
        guard !carLive.isClosingForPolicy else { return }
        await stopCarLive()
    }

    func noteLiveEnded(epoch: UInt64, endedToken: UInt64) {
        guard epoch == backgroundVoiceEpoch else { return }
        guard backgroundVoiceScene == .background else { return }
        guard let carLive else {
            releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: epoch)
            return
        }
        if carLive.phase == .listening || carLive.phase == .speaking {
            return
        }
        if carLive.phase == .connecting, carLive.captureGenerationForPolicy != 0 {
            return
        }
        let current = carLive.runTokenForPolicy
        guard current == endedToken || current == endedToken &+ 1 else { return }
        releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: epoch)
    }

    func bindBackgroundVoiceHold(epoch: UInt64) {
        carLive?.onExternalAudioHold = { [weak self] generation in
            guard let self else { return }
            Task { @MainActor in
                await self.noteAudioHold(epoch: epoch, generation: generation)
            }
        }
        carLive?.onLiveEnded = { [weak self] endedToken in
            guard let self else { return }
            Task { @MainActor in
                self.noteLiveEnded(epoch: epoch, endedToken: endedToken)
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

    func cancelPendingCarLiveCapture() {
        carLive?.blocksNewCapture = true
        carLive?.cancelStartBeforeCapture()
        cancelCarLiveConnect()
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
