import Foundation
import Testing
@testable import OpenCodeClient

struct BackgroundVoicePolicyTests {
    @Test func backgroundHoldsOnlyStartedCapture() {
        let running = BackgroundVoicePolicy.liveKind(phase: .listening, captureGeneration: 3, connectInFlight: false, closing: false)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: running, connected: true) == .holdOpenConnections)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: running, connected: false) == .legacyCleanup)
        let connecting = BackgroundVoicePolicy.liveKind(phase: .connecting, captureGeneration: 0, connectInFlight: true, closing: false)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: connecting, connected: true) == .cancelPendingThenCleanup)
        let staleConnecting = BackgroundVoicePolicy.liveKind(phase: .connecting, captureGeneration: 4, connectInFlight: true, closing: false)
        #expect(staleConnecting == .connecting)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: staleConnecting, connected: true) == .cancelPendingThenCleanup)
        let closing = BackgroundVoicePolicy.liveKind(phase: .listening, captureGeneration: 4, connectInFlight: false, closing: true)
        #expect(closing == .closing)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: closing, connected: true) == .legacyCleanup)
        let idleGeneration = BackgroundVoicePolicy.liveKind(phase: .idle, captureGeneration: 4, connectInFlight: false, closing: false)
        #expect(idleGeneration == .none)
        let failedGeneration = BackgroundVoicePolicy.liveKind(phase: .failed, captureGeneration: 4, connectInFlight: false, closing: false)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: failedGeneration, connected: true) == .legacyCleanup)
        let listeningWithoutCapture = BackgroundVoicePolicy.liveKind(phase: .listening, captureGeneration: 0, connectInFlight: false, closing: false)
        #expect(BackgroundVoicePolicy.action(scene: .background, live: listeningWithoutCapture, connected: true) == .legacyCleanup)
        let idle = BackgroundVoicePolicy.liveKind(phase: .idle, captureGeneration: 0, connectInFlight: false, closing: false)
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
        #expect(BackgroundVoicePolicy.closesForLegacyInterruptionBegan(false) == false)
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

    @Test func clearAndCloseContractUnchanged() {
        #expect(CarLiveProtocol.closeGrace == 15)
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

struct BackgroundVoiceLifecycleTests {
    @Test @MainActor func activeVoiceBackgroundKeepsCaptureLinkAndDoesNotAbort() async {
        let defaults = makeIsolatedUserDefaults()
        defaults.set("isolated", forKey: "background-voice-isolation")
        #expect(UserDefaults.standard.string(forKey: "background-voice-isolation") == nil)
        let harness = await listen(defaults: defaults)
        let sseToken = harness.state.sseConnectionToken
        harness.state.handleApplicationScene(.inactive)
        #expect(harness.controller.phase == .listening)
        harness.state.handleApplicationScene(.background)
        harness.state.handleApplicationScene(.background)
        #expect(harness.controller.phase == .listening)
        #expect(harness.link.closes == 0)
        #expect(harness.transport.opens == 1)
        #expect(harness.audio.startCount == 1)
        #expect(harness.state.isConnected)
        #expect(harness.state.sseConnectionToken == sseToken)
        #expect(harness.state.holdingBackgroundVoice)
        #expect(await harness.api.abortSessionIDs.isEmpty)
        await harness.state.stopCarLive()
    }

    @Test @MainActor func noVoiceBackgroundStillDisconnects() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.connectSSE()
        let sseToken = state.sseConnectionToken
        var sshCalls = 0
        state.sshTunnelManager.tunnelConnector = { snapshot in
            sshCalls += 1
            return SSHOpenedTunnel(remotePort: snapshot.remotePort, close: {})
        }
        state.sshTunnelManager.config = SSHTunnelConfig(isEnabled: true, host: "gateway.invalid", port: 22, username: "opencode", remotePort: 19001)
        await state.sshTunnelManager.connect()
        #expect(sshCalls == 1)
        #expect(state.sshTunnelManager.status == .connected)
        state.handleApplicationScene(.background)
        #expect(state.isConnected == false)
        #expect(state.sseConnectionToken > sseToken)
        #expect(state.sshTunnelManager.status == .disconnected)
        #expect(sshCalls == 1)
        #expect(await api.abortSessionIDs.isEmpty)
        #expect(await api.healthCallCount == 0)
    }

    @Test @MainActor func permissionPendingBackgroundDoesNotOpenMicrophone() async {
        let audio = PermissionGateAudio()
        let transport = ImmediateTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let api = MockAPIClient()
        let state = voiceState(api: api, controller: controller)
        state.beginCarLiveConnect()
        #expect(await waitUntil { audio.isWaiting })
        state.handleApplicationScene(.background)
        audio.resume(true)
        #expect(await waitUntil { controller.phase != .connecting })
        #expect(audio.startCount == 0)
        #expect(transport.opens == 0)
        #expect(state.isConnected == false)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func connectingBackgroundDoesNotLateOpenMicrophone() async {
        let audio = CountingAudio()
        let transport = HoldingTransport()
        let link = VoiceLink()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let api = MockAPIClient()
        let state = voiceState(api: api, controller: controller)
        state.beginCarLiveConnect()
        #expect(await waitUntil { transport.opens == 1 })
        state.handleApplicationScene(.background)
        transport.release(link)
        link.emit(.started(sessionID: "late"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(audio.startCount == 0)
        #expect(transport.opens == 1)
        #expect(controller.phase != .listening)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func backgroundEndReleasesNetworkHold() async {
        let harness = await listen()
        var sshCalls = 0
        harness.state.sshTunnelManager.tunnelConnector = { snapshot in
            sshCalls += 1
            return SSHOpenedTunnel(remotePort: snapshot.remotePort, close: {})
        }
        harness.state.sshTunnelManager.config = SSHTunnelConfig(isEnabled: true, host: "gateway.invalid", port: 22, username: "opencode", remotePort: 19001)
        await harness.state.sshTunnelManager.connect()
        harness.state.connectSSE()
        harness.state.handleApplicationScene(.background)
        #expect(harness.state.holdingBackgroundVoice)
        await harness.state.stopCarLive()
        #expect(harness.controller.phase == .idle)
        #expect(harness.state.isConnected == false)
        #expect(harness.state.sshTunnelManager.status == .disconnected)
        #expect(sshCalls == 1)
        #expect(harness.transport.opens == 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func interruptClosesOnceAndRepeatDoesNotReconnect() async {
        let harness = await listen()
        let generation = harness.controller.captureGenerationForPolicy
        harness.controller.noteExternalAudioHold(generation: generation &+ 1)
        #expect(harness.controller.phase == .listening)
        harness.controller.noteExternalAudioHold(generation: generation)
        #expect(await waitUntil { harness.controller.phase == .idle })
        harness.controller.noteExternalAudioHold(generation: generation)
        #expect(harness.transport.opens == 1)
        #expect(harness.audio.startCount == 1)
        #expect(harness.state.isConnected)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func backgroundInterruptReleasesNetworkAndDoesNotReconnect() async {
        let harness = await listen()
        var sshCalls = 0
        harness.state.sshTunnelManager.tunnelConnector = { snapshot in
            sshCalls += 1
            return SSHOpenedTunnel(remotePort: snapshot.remotePort, close: {})
        }
        harness.state.sshTunnelManager.config = SSHTunnelConfig(isEnabled: true, host: "gateway.invalid", port: 22, username: "opencode", remotePort: 19001)
        await harness.state.sshTunnelManager.connect()
        harness.state.handleApplicationScene(.background)
        let generation = harness.controller.captureGenerationForPolicy
        harness.controller.noteExternalAudioHold(generation: generation)
        #expect(await waitUntil { harness.controller.phase == .idle })
        harness.controller.noteExternalAudioHold(generation: generation)
        #expect(harness.state.isConnected == false)
        #expect(harness.state.sshTunnelManager.status == .disconnected)
        #expect(sshCalls == 1)
        #expect(harness.transport.opens == 1)
        #expect(harness.audio.startCount == 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func foregroundRestoreDoesNotRepeatPostSSEOrSSH() async {
        let harness = await listen()
        var sshCalls = 0
        harness.state.sshTunnelManager.tunnelConnector = { snapshot in
            sshCalls += 1
            return SSHOpenedTunnel(remotePort: snapshot.remotePort, close: {})
        }
        harness.state.sshTunnelManager.config = SSHTunnelConfig(isEnabled: true, host: "gateway.invalid", port: 22, username: "opencode", remotePort: 19001)
        await harness.state.sshTunnelManager.connect()
        harness.state.statusStreamConnected = true
        harness.state.sseConnectionToken = 7
        let task = Task {}
        harness.state.sseTask = task
        harness.state.handleApplicationScene(.background)
        await harness.state.restoreConnectionsAfterForeground()
        #expect(await harness.api.healthCallCount == 0)
        #expect(harness.state.sseConnectionToken == 7)
        #expect(harness.state.sseTask == task)
        #expect(sshCalls == 1)
        #expect(harness.state.sshTunnelManager.status == .connected)
        #expect(harness.transport.opens == 1)
        #expect(harness.controller.phase == .listening)
        await harness.state.stopCarLive()
    }

    @Test @MainActor func hostSwitchCancelsOldHoldPolicy() async throws {
        let harness = await listen()
        harness.state.handleApplicationScene(.background)
        let epoch = harness.state.backgroundVoiceEpoch
        let generation = harness.controller.captureGenerationForPolicy
        let other = HostProfile(name: "Other", transport: .direct, serverURL: "http://127.0.0.1:9", basicAuth: nil, ssh: nil, lastUsedAt: nil)
        try harness.state.saveHostProfile(other, makeCurrent: true)
        await harness.state.finishHostTransportConfiguration()
        #expect(harness.state.backgroundVoiceEpoch == epoch &+ 1)
        harness.state.isConnected = true
        harness.state.statusStreamConnected = true
        await harness.state.noteAudioHold(epoch: epoch, generation: generation)
        harness.controller.noteExternalAudioHold(generation: generation)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.transport.opens == 1)
        #expect(harness.audio.startCount == 1)
        #expect(harness.state.isConnected)
        #expect(await harness.api.abortSessionIDs.isEmpty)
        #expect(await harness.api.healthCallCount == 0)
    }

    @Test @MainActor func projectChangeBumpsHoldEpoch() {
        let state = makeIsolatedAppState()
        let epoch = state.backgroundVoiceEpoch
        state.invalidateCarTurnForRealProjectChange()
        #expect(state.backgroundVoiceEpoch == epoch &+ 1)
        #expect(state.holdingBackgroundVoice == false)
    }

    @Test @MainActor func stoppedGenerationDoesNotOpenMicrophoneOnNextConnect() async {
        let audio = CountingAudio()
        let transport = TwoStepTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let api = MockAPIClient()
        let state = voiceState(api: api, controller: controller)
        let starting = Task { await state.startCarLive() }
        #expect(await waitUntil { transport.opens == 1 })
        transport.first.emit(.started(sessionID: "live"))
        await starting.value
        #expect(controller.phase == .listening)
        #expect(controller.captureGenerationForPolicy != 0)
        await state.stopCarLive()
        #expect(controller.phase == .idle)
        #expect(controller.captureGenerationForPolicy == 0)
        #expect(state.isConnected)
        let again = Task { await state.startCarLive() }
        #expect(await waitUntil { transport.opens == 2 })
        state.handleApplicationScene(.background)
        let late = VoiceLink()
        transport.releaseSecond(late)
        late.emit(.started(sessionID: "late"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(audio.startCount == 1)
        #expect(controller.phase != .listening)
        #expect(controller.phase != .speaking)
        #expect(state.isConnected == false)
        #expect(await api.abortSessionIDs.isEmpty)
        _ = again
    }

    @Test @MainActor func backgroundServerCloseReleasesNetwork() async {
        let harness = await listen()
        var sshCalls = 0
        harness.state.sshTunnelManager.tunnelConnector = { snapshot in
            sshCalls += 1
            return SSHOpenedTunnel(remotePort: snapshot.remotePort, close: {})
        }
        harness.state.sshTunnelManager.config = SSHTunnelConfig(isEnabled: true, host: "gateway.invalid", port: 22, username: "opencode", remotePort: 19001)
        await harness.state.sshTunnelManager.connect()
        harness.state.connectSSE()
        harness.state.handleApplicationScene(.background)
        #expect(harness.state.holdingBackgroundVoice)
        harness.link.emit(.closed(1))
        #expect(await waitUntil { harness.controller.phase == .idle })
        #expect(await waitUntil { harness.state.isConnected == false })
        #expect(harness.state.sshTunnelManager.status == .disconnected)
        #expect(harness.state.skipForegroundConnectionRestore == false)
        #expect(sshCalls == 1)
        #expect(harness.transport.opens == 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func foregroundServerCloseKeepsOpenCodeConnection() async {
        let harness = await listen()
        harness.state.connectSSE()
        let token = harness.state.sseConnectionToken
        harness.link.emit(.closed(1))
        #expect(await waitUntil { harness.controller.phase == .idle })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(harness.state.isConnected)
        #expect(harness.state.sseConnectionToken == token)
        #expect(harness.controller.captureGenerationForPolicy == 0)
        #expect(await harness.api.healthCallCount == 0)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func backgroundTerminalFailureReleasesNetwork() async {
        let harness = await listen()
        harness.state.handleApplicationScene(.background)
        harness.link.emit(.failed("connection_lost"))
        #expect(await waitUntil { harness.controller.phase == .failed || harness.controller.phase == .idle })
        #expect(await waitUntil { harness.state.isConnected == false })
        #expect(harness.state.holdingBackgroundVoice == false)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func repeatedForegroundRestoreDoesNotRepeatPost() async {
        let harness = await listen()
        harness.state.statusStreamConnected = true
        harness.state.sseConnectionToken = 7
        let task = Task {}
        harness.state.sseTask = task
        harness.state.handleApplicationScene(.background)
        await harness.state.restoreConnectionsAfterForeground()
        await harness.state.restoreConnectionsAfterForeground()
        #expect(await harness.api.healthCallCount == 0)
        #expect(harness.state.sseConnectionToken == 7)
        #expect(harness.state.sseTask == task)
        #expect(harness.transport.opens == 1)
        #expect(harness.controller.phase == .listening)
        await harness.state.stopCarLive()
    }

    @Test @MainActor func lateBackgroundEndDoesNotTouchNewHost() async throws {
        let harness = await listen()
        harness.state.handleApplicationScene(.background)
        let epoch = harness.state.backgroundVoiceEpoch
        let other = HostProfile(name: "Other", transport: .direct, serverURL: "http://127.0.0.1:9", basicAuth: nil, ssh: nil, lastUsedAt: nil)
        try harness.state.saveHostProfile(other, makeCurrent: true)
        await harness.state.finishHostTransportConfiguration()
        #expect(harness.state.backgroundVoiceEpoch == epoch &+ 1)
        harness.state.isConnected = true
        harness.state.statusStreamConnected = true
        harness.link.emit(.closed(1))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(harness.state.isConnected)
        #expect(harness.transport.opens == 1)
        #expect(await harness.api.healthCallCount == 0)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func authenticationDropIsNotHidden() async {
        let harness = await listen()
        harness.state.handleApplicationScene(.background)
        harness.state.isConnected = false
        #expect(await waitUntil { harness.controller.phase == .idle })
        #expect(harness.state.isConnected == false)
        #expect(harness.state.skipForegroundConnectionRestore == false)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func awaitedEndAfterEpochSwitchKeepsReplacementConnection() async {
        let harness = await listen(closeGrace: 2)
        harness.state.handleApplicationScene(.background)
        let stopping = Task { await harness.state.stopCarLive() }
        defer {
            harness.link.emit(.closed(1))
            stopping.cancel()
        }
        #expect(await waitUntil { harness.controller.phase == .closing })
        harness.state.invalidateBackgroundVoicePolicy()
        harness.state.isConnected = true
        harness.state.statusStreamConnected = true
        harness.state.sseConnectionToken = 11
        harness.link.emit(.closed(1))
        await stopping.value
        #expect(harness.state.isConnected)
        #expect(harness.state.sseConnectionToken == 11)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }
}

@MainActor
private func voiceState(api: MockAPIClient, controller: CarLiveController, defaults: UserDefaults? = nil) -> AppState {
    let state = makeIsolatedAppState(apiClient: api, userDefaults: defaults)
    state.carLive = controller
    state.isConnected = true
    state.aiBuilderToken = "token"
    state.aiBuilderBaseURL = "https://portal.example"
    return state
}

@MainActor
private func listen(defaults: UserDefaults? = nil, closeGrace: Double = 0.05) async -> VoiceHarness {
    let audio = CountingAudio()
    let link = VoiceLink()
    let transport = ImmediateTransport(link: link)
    let controller = CarLiveController(transport: transport, audio: audio, closeGrace: closeGrace)
    let api = MockAPIClient()
    let state = voiceState(api: api, controller: controller, defaults: defaults)
    let starting = Task { await state.startCarLive() }
    #expect(await waitUntil { transport.opens == 1 })
    link.emit(.started(sessionID: "live"))
    await starting.value
    return VoiceHarness(api: api, transport: transport, link: link, audio: audio, controller: controller, state: state)
}

private func waitUntil(_ ready: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<40 {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await MainActor.run(body: ready)
}

@MainActor
private struct VoiceHarness {
    var api: MockAPIClient
    var transport: ImmediateTransport
    var link: VoiceLink
    var audio: CountingAudio
    var controller: CarLiveController
    var state: AppState
}

private final class VoiceLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    private var closeCount = 0

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) {
        continuation.yield(event)
    }

    func send(_ event: CarLiveClientEvent) async throws {}
    func ping() async throws {}

    func close() async {
        lock.withLock { closeCount += 1 }
        continuation.finish()
    }

    var closes: Int { lock.withLock { closeCount } }
}

private final class ImmediateTransport: CarLiveTransporting, @unchecked Sendable {
    var link: VoiceLink
    private let lock = NSLock()
    private var openCount = 0

    init(link: VoiceLink = VoiceLink()) {
        self.link = link
    }

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        lock.withLock { openCount += 1 }
        return link
    }

    var opens: Int { lock.withLock { openCount } }
}

private final class TwoStepTransport: CarLiveTransporting, @unchecked Sendable {
    let first = VoiceLink()
    private let lock = NSLock()
    private var openCount = 0
    private var waiter: CheckedContinuation<any CarLiveLink, Error>?

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let count = lock.withLock { () -> Int in
            openCount += 1
            return openCount
        }
        if count == 1 { return first }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiter = continuation }
        }
    }

    func releaseSecond(_ link: any CarLiveLink) {
        let waiter = lock.withLock { () -> CheckedContinuation<any CarLiveLink, Error>? in
            let value = self.waiter
            self.waiter = nil
            return value
        }
        waiter?.resume(returning: link)
    }

    var opens: Int { lock.withLock { openCount } }
}

private final class HoldingTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<any CarLiveLink, Error>] = []
    private var openCount = 0

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        lock.withLock { openCount += 1 }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
    }

    func release(_ link: any CarLiveLink) {
        let waiter = lock.withLock { waiters.isEmpty ? nil : waiters.removeFirst() }
        waiter?.resume(returning: link)
    }

    var opens: Int { lock.withLock { openCount } }
}

private final class CountingAudio: CarLiveAudioEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0

    func requestRecordPermission() async -> Bool { true }

    func startCapture() async throws -> CarLiveCaptureHandle {
        lock.withLock { starts += 1 }
        let stream = CarLiveFrameStream(generation: 1)
        return CarLiveCaptureHandle(generation: 1, frames: stream.frames) { stream.finish() }
    }

    func stopCapture(generation: UInt64) async {}
    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}

    var startCount: Int { lock.withLock { starts } }
}

private final class PermissionGateAudio: CarLiveAudioEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Bool, Never>?
    private var starts = 0

    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.withLock { waiter = continuation }
        }
    }

    var isWaiting: Bool { lock.withLock { waiter != nil } }

    func resume(_ granted: Bool) {
        let current = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            let value = waiter
            waiter = nil
            return value
        }
        current?.resume(returning: granted)
    }

    func startCapture() async throws -> CarLiveCaptureHandle {
        lock.withLock { starts += 1 }
        let stream = CarLiveFrameStream(generation: 1)
        return CarLiveCaptureHandle(generation: 1, frames: stream.frames) { stream.finish() }
    }

    func stopCapture(generation: UInt64) async {}
    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}

    var startCount: Int { lock.withLock { starts } }
}
