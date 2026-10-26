import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveForegroundLifecycleTests {
    @Test @MainActor func leavingThePageKeepsTheSameListeningRun() async {
        let harness = await ListeningHarness.make()
        harness.link.emit(.inputTranscript("KEEP_CAPTION"))
        #expect(await waitUntil { harness.controller.captions.contains { $0.text == "KEEP_CAPTION" } })

        harness.state.noteCarLivePageHidden()
        harness.state.noteCarLivePageShown()

        #expect(harness.controller.phase == .listening)
        #expect(harness.state.carLive === harness.controller)
        #expect(harness.transport.opens == 1)
        #expect(harness.link.closes == 0)
        #expect(harness.controller.captions.contains { $0.text == "KEEP_CAPTION" })
        #expect(await harness.api.abortSessionIDs.isEmpty)
        await harness.state.stopCarLive()
    }

    @Test @MainActor func connectInFlightSurvivesPageHide() async {
        let link = ForegroundLiveLink()
        let transport = HoldingTransport()
        let controller = CarLiveController(transport: transport, audio: ForegroundLiveAudio(), closeGrace: 0.05)
        let api = MockAPIClient()
        let state = preparedState(api: api, controller: controller)

        state.beginCarLiveConnect()
        #expect(await waitUntil { transport.opens == 1 })
        state.noteCarLivePageHidden()
        transport.release(link)
        link.emit(.started(sessionID: "held"))
        #expect(await waitUntil { controller.phase == .listening })
        state.noteCarLivePageShown()

        #expect(state.carLive === controller)
        #expect(transport.opens == 1)
        #expect(link.closes == 0)
        #expect(await api.abortSessionIDs.isEmpty)
        await state.stopCarLive()
    }

    @Test @MainActor func explicitEndClosesOnceAndDoesNotAbort() async {
        let harness = await ListeningHarness.make()
        await harness.state.stopCarLive()
        #expect(harness.controller.phase == .idle)
        #expect(harness.transport.opens == 1)
        #expect(harness.link.closes == 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func backgroundWhilePageHiddenClosesWithoutAbort() async {
        let harness = await ListeningHarness.make()
        harness.state.noteCarLivePageHidden()
        harness.state.isConnected = false
        #expect(await waitUntil { harness.link.closes == 1 })
        #expect(harness.controller.phase != .listening)
        #expect(harness.controller.phase != .speaking)
        #expect(harness.transport.opens == 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func oldCloseDoesNotCancelPreLeaseConnect() async {
        let transport = StickyHoldTransport()
        let controller = CarLiveController(transport: transport, audio: ForegroundLiveAudio(), closeGrace: 0.05)
        let api = MockAPIClient()
        let state = preparedState(api: api, controller: controller)
        let gate = LeaseHold()
        state.beginCarLiveConnect()
        #expect(await waitUntil { transport.opens == 1 })
        await state.stopCarLive()
        state.carLiveBeforeLease = { await gate.enter() }
        state.beginCarLiveConnect()
        #expect(await waitUntil { gate.didEnter })
        transport.releaseFirst()
        #expect(gate.passed == false)
        #expect(state.carLiveConnectTask != nil)
        #expect(state.carLiveLease == nil)
        #expect(state.carLiveConnectRun != nil)
        gate.release()
        #expect(await waitUntil { transport.opens == 2 })
        transport.releaseFirst()
        transport.links[1].emit(.started(sessionID: "new-run"))
        #expect(await waitUntil { controller.phase == .listening })
        #expect(gate.passed)
        #expect(transport.links[1].closes == 0)
        #expect(await api.abortSessionIDs.isEmpty)
        await state.stopCarLive()
    }

    @Test @MainActor func oldReturnDoesNotCloseSameContextLateLease() async {
        let transport = StickyHoldTransport()
        let controller = CarLiveController(transport: transport, audio: ForegroundLiveAudio(), closeGrace: 0.05)
        let api = MockAPIClient()
        let state = preparedState(api: api, controller: controller)
        state.beginCarLiveConnect()
        #expect(await waitUntil { transport.opens == 1 })
        let firstLease = state.carLiveLease
        state.beginCarLiveConnect()
        #expect(await waitUntil { transport.opens == 2 })
        let secondLease = state.carLiveLease
        #expect(secondLease != nil)
        #expect(secondLease != firstLease)
        #expect(secondLease?.hostID == firstLease?.hostID)
        #expect(secondLease?.contextKey == firstLease?.contextKey)
        transport.releaseFirst()
        #expect(state.carLiveConnectTask != nil)
        #expect(state.carLiveLease == secondLease)
        transport.releaseFirst()
        transport.links[1].emit(.started(sessionID: "late-lease"))
        #expect(await waitUntil { controller.phase == .listening })
        #expect(transport.links[1].closes == 0)
        #expect(await api.abortSessionIDs.isEmpty)
        await state.stopCarLive()
    }

    @Test @MainActor func disablingCarModeStopsVoiceWithoutAbort() async {
        let harness = await ListeningHarness.make()
        harness.state.isCarModeEnabled = true
        harness.state.isCarModeEnabled = false
        #expect(await waitUntil { harness.link.closes == 1 })
        #expect(harness.controller.phase != .listening)
        #expect(await harness.api.abortSessionIDs.isEmpty)
    }
}

@MainActor
private struct ListeningHarness {
    let api: MockAPIClient
    let transport: ForegroundLiveTransport
    let link: ForegroundLiveLink
    let controller: CarLiveController
    let state: AppState

    static func make() async -> ListeningHarness {
        let link = ForegroundLiveLink()
        let transport = ForegroundLiveTransport(link: link)
        let controller = CarLiveController(transport: transport, audio: ForegroundLiveAudio(), closeGrace: 0.05)
        let api = MockAPIClient()
        let state = preparedState(api: api, controller: controller)
        let starting = Task { await state.startCarLive() }
        #expect(await waitUntil { transport.opens == 1 })
        link.emit(.started(sessionID: "foreground"))
        await starting.value
        #expect(controller.phase == .listening)
        return ListeningHarness(api: api, transport: transport, link: link, controller: controller, state: state)
    }
}

@MainActor
private func preparedState(api: MockAPIClient, controller: CarLiveController) -> AppState {
    let state = makeIsolatedAppState(apiClient: api)
    state.carLive = controller
    state.isConnected = true
    state.aiBuilderToken = "token"
    state.aiBuilderBaseURL = "https://portal.example"
    return state
}

private func waitUntil(_ ready: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<40 {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await MainActor.run(body: ready)
}

private final class ForegroundLiveLink: CarLiveLink, @unchecked Sendable {
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

nonisolated private final class ForegroundLiveTransport: CarLiveTransporting, @unchecked Sendable {
    let link: ForegroundLiveLink
    private let lock = NSLock()
    private var openCount = 0

    init(link: ForegroundLiveLink) {
        self.link = link
    }

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        lock.withLock { openCount += 1 }
        return link
    }

    var opens: Int { lock.withLock { openCount } }
}

nonisolated private final class StickyHoldTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var openCount = 0
    private(set) var links: [ForegroundLiveLink] = []

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let link = ForegroundLiveLink()
        lock.withLock {
            openCount += 1
            links.append(link)
        }
        await withCheckedContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
        return link
    }

    func releaseFirst() {
        let waiter = lock.withLock { waiters.isEmpty ? nil : waiters.removeFirst() }
        waiter?.resume()
    }

    var opens: Int { lock.withLock { openCount } }
}

@MainActor
private final class LeaseHold {
    private var hold: CheckedContinuation<Void, Never>?
    private(set) var didEnter = false
    private(set) var passed = false

    func enter() async {
        didEnter = true
        await withCheckedContinuation { hold = $0 }
        passed = true
    }

    func release() {
        hold?.resume()
        hold = nil
    }
}

nonisolated private final class HoldingTransport: CarLiveTransporting, @unchecked Sendable {
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

private final class ForegroundLiveAudio: CarLiveAudioEngine, @unchecked Sendable {
    func requestRecordPermission() async -> Bool { true }
    func startCapture() async throws -> CarLiveCaptureHandle {
        let stream = CarLiveFrameStream(generation: 1)
        return CarLiveCaptureHandle(generation: 1, frames: stream.frames) { stream.finish() }
    }
    func stopCapture(generation: UInt64) async {}
    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}
}
