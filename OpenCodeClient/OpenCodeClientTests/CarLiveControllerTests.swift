import Foundation
import Testing
@testable import OpenCodeClient

private final class CarLiveHoldLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    var failAudio = false
    var audioHang: CarLiveHang?
    private(set) var closed = false
    private(set) var sent: [CarLiveClientEvent] = []

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) {
        continuation.yield(event)
    }

    func send(_ event: CarLiveClientEvent) async throws {
        if case .audio = event, let audioHang { await audioHang.wait() }
        if failAudio, case .audio = event {
            throw CarLiveTransportError.socket
        }
        lock.withLock { sent.append(event) }
    }

    func sentSnapshot() -> [CarLiveClientEvent] {
        lock.withLock { sent }
    }

    func ping() async throws {}

    func finish() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            continuation.finish()
        }
    }

    func close() async {
        finish()
    }
}

nonisolated private final class CarLiveGateTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<any CarLiveLink, Error>] = []
    private(set) var openCount = 0

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

    func cancelAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<any CarLiveLink, Error>] in
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume(throwing: CarLiveTransportError.socket)
        }
    }
}

private final class CarLiveProbeAudio: CarLiveAudioEngine, @unchecked Sendable {
    var startsBeforeConnection = false
    var holdPermission = false
    var permissionGranted = true
    var stopHang: CarLiveHang?
    private let lock = NSLock()
    private var permissionWaiters: [CheckedContinuation<Bool, Never>] = []
    var waitingPermissions: Int {
        lock.withLock { permissionWaiters.count }
    }
    private(set) var stopCalls: [UInt64] = []
    private(set) var current: UInt64 = 0
    private(set) var enqueued = 0
    private(set) var clears = 0
    private(set) var holdBegins = 0
    private var stream: CarLiveFrameStream?
    private var levelHandler: (@Sendable (Double, Double) -> Void)?
    private var idleHandler: (@Sendable () -> Void)?

    func requestRecordPermission() async -> Bool {
        guard permissionGranted else { return false }
        guard holdPermission else { return true }
        return await withCheckedContinuation { continuation in
            lock.withLock { permissionWaiters.append(continuation) }
        }
    }

    func grantPermission() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Bool, Never>] in
            let waiters = permissionWaiters
            permissionWaiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: true)
        }
    }

    func startCapture() async throws -> CarLiveCaptureHandle {
        let generation = lock.withLock { () -> UInt64 in
            current += 1
            return current
        }
        let opened = CarLiveFrameStream(generation: generation)
        lock.withLock { stream = opened }
        return CarLiveCaptureHandle(generation: generation, frames: opened.frames) { opened.finish() }
    }

    func pushFrame() {
        let opened = lock.withLock { () -> (CarLiveFrameStream?, UInt64) in
            (stream, current)
        }
        _ = opened.0?.yield(Data([1, 0]), generation: opened.1)
    }

    func stopCapture(generation: UInt64) async {
        if let stopHang { await stopHang.wait() }
        let opened = lock.withLock { () -> CarLiveFrameStream? in
            stopCalls.append(generation)
            guard generation == current else { return nil }
            let opened = stream
            stream = nil
            current = 0
            return opened
        }
        opened?.finish()
    }

    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {
        lock.withLock { enqueued += 1 }
    }
    func clearPlayback() {
        lock.withLock { clears += 1 }
    }
    func setPlaybackHeld(_ held: Bool) {
        if held {
            lock.withLock { holdBegins += 1 }
        }
    }
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {
        lock.withLock { levelHandler = handler }
    }
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {
        lock.withLock { idleHandler = handler }
    }
    func emitLevel(input: Double, output: Double) {
        let handler = lock.withLock { levelHandler }
        handler?(input, output)
    }
    func emitIdle() {
        let handler = lock.withLock { idleHandler }
        handler?()
    }
}

private actor CarLiveHang {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private func finishLive(
    hold: ToolHold,
    link: CarLiveHoldLink,
    controller: CarLiveController,
    _ body: () async throws -> Void
) async rethrows {
    do {
        try await body()
    } catch {
        hold.release()
        link.finish()
        await controller.stop()
        throw error
    }
    hold.release()
    link.finish()
    await controller.stop()
}

private func waitUntil(_ ready: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<50 {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await MainActor.run(body: ready)
}

private func liveConfig() -> CarLiveConfiguration {
    CarLiveConfiguration(
        portalBaseURL: URL(string: "https://space.example/backend")!,
        builderToken: "builder-test",
        ownerToken: "owner-a"
    )
}

struct CarLiveControllerTests {
    @Test @MainActor func hangingHardwareStopLeavesClosingAndBlocksCaptureUntilCleanupCompletes() async {
        let transport = CarLiveGateTransport()
        let audio = CarLiveProbeAudio()
        let hang = CarLiveHang()
        audio.stopHang = hang
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.04)
        let starting = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 1 })
        let link = CarLiveHoldLink()
        transport.release(link)
        link.emit(.started(sessionID: "audio-stop-hang"))
        await starting.value
        var stopped = false
        let stopping = Task { await controller.stop(); stopped = true }
        #expect(await waitUntil { stopped })
        #expect(controller.phase == .failed)
        #expect(controller.audioCleanupPending)
        #expect(controller.captureGenerationForPolicy != 0)
        await controller.start(configuration: liveConfig())
        #expect(transport.openCount == 1)
        audio.stopHang = nil
        await hang.release()
        await stopping.value
        #expect(await waitUntil { !controller.audioCleanupPending })
        #expect(controller.captureGenerationForPolicy == 0)
        let restarted = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 2 })
        let next = CarLiveHoldLink()
        transport.release(next)
        next.emit(.started(sessionID: "audio-recovered"))
        await restarted.value
        #expect(controller.phase == .listening)
        await controller.stop()
    }

    @Test @MainActor func watchAudioSendThatNeverReturnsFailsInsteadOfSilentlyFreezing() async {
        let transport = CarLiveGateTransport()
        let audio = CarLiveProbeAudio()
        let hang = CarLiveHang()
        let link = CarLiveHoldLink()
        link.audioHang = hang
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.04, audioSendTimeout: 0.03)
        let starting = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 1 })
        transport.release(link)
        link.emit(.started(sessionID: "audio-send-hang"))
        await starting.value
        audio.pushFrame()
        #expect(await waitUntil { controller.phase == .failed })
        #expect(controller.errorMessage != nil)
        await hang.release()
        #expect(await waitUntil { audio.current == 0 })
        await controller.stop()
    }

    @Test @MainActor func watchCaptureStartsBeforeSocketAndIsReusedAfterStarted() async {
        let transport = CarLiveGateTransport()
        let audio = CarLiveProbeAudio()
        audio.startsBeforeConnection = true
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.01)
        let starting = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 1 })
        #expect(audio.current == 1)
        #expect(controller.phase == .connecting)
        let link = CarLiveHoldLink()
        transport.release(link)
        link.emit(.started(sessionID: "watch"))
        await starting.value
        #expect(audio.current == 1)
        audio.pushFrame()
        #expect(await waitUntil { controller.inputFrameCount > 0 })
        await controller.stop()
        #expect(audio.current == 0)
    }

    @Test @MainActor func earlyCaptureIsStoppedWhenSocketFails() async {
        let transport = CarLiveGateTransport()
        let audio = CarLiveProbeAudio()
        audio.startsBeforeConnection = true
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.01)
        let starting = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 1 })
        transport.cancelAll()
        await starting.value
        #expect(controller.phase == .failed)
        #expect(audio.current == 0)
    }

    @Test @MainActor func lateToolAfterResetDoesNotWriteNewActivities() async {
        let transport = CarLiveFreshTransport()
        defer { transport.finishAll() }
        let hang = CarLiveHang()
        defer { Task { await hang.release() } }
        let controller = CarLiveController(transport: transport, audio: CarLiveProbeAudio(), closeGrace: 0.05)
        controller.toolExecutor = { _ in
            await hang.wait()
            return CarLiveToolResult(output: "{\"ok\":true}")
        }
        let starting = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 1 })
        transport.links[0].emit(.started(sessionID: "live-old"))
        await starting.value
        transport.links[0].emit(.hosted(.functionCall(callID: "call-old", name: "query_jobs", arguments: "{}")))
        #expect(await waitUntil { controller.activities.contains { $0.id == "call-old" && $0.status == "running" } })
        let resetting = Task { await controller.resetConversation() }
        transport.links[0].emit(.closed(1))
        await resetting.value
        let restarted = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 2 })
        transport.links[1].emit(.started(sessionID: "live-new"))
        await restarted.value
        await hang.release()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(controller.activities.contains { $0.id == "call-old" } == false)
        #expect(controller.activities.contains { $0.status == "dropped" } == false)
        await controller.stop()
    }

    @Test @MainActor func emptyHistoryStartClearsPreviousConversation() async {
        let transport = CarLiveFreshTransport()
        defer { transport.finishAll() }
        let controller = CarLiveController(transport: transport, audio: CarLiveProbeAudio(), closeGrace: 0.05)
        let first = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 1 })
        transport.links[0].emit(.started(sessionID: "live-old"))
        await first.value
        transport.links[0].emit(.inputTranscript("旧字幕"))
        transport.links[0].emit(.hosted(.functionCall(callID: "call-old", name: "query_jobs", arguments: "{}")))
        #expect(await waitUntil { controller.captions.contains { $0.text == "旧字幕" } })
        #expect(await waitUntil { controller.activities.contains { $0.id == "call-old" && $0.status == "running" } })
        let stopping = Task { await controller.stop() }
        transport.links[0].emit(.closed(1))
        await stopping.value
        let second = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 2 })
        #expect(controller.captions.isEmpty)
        #expect(controller.activities.isEmpty)
        transport.links[1].emit(.started(sessionID: "live-new"))
        await second.value
        #expect(controller.captions.isEmpty)
        #expect(controller.activities.isEmpty)
        await controller.stop()
    }

    @Test @MainActor func explicitHistoryReplacesUnrelatedCaptions() async {
        let transport = CarLiveFreshTransport()
        defer { transport.finishAll() }
        let controller = CarLiveController(transport: transport, audio: CarLiveProbeAudio(), closeGrace: 0.05)
        let first = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 1 })
        transport.links[0].emit(.started(sessionID: "live-old"))
        await first.value
        transport.links[0].emit(.inputTranscript("不相关"))
        #expect(await waitUntil { controller.captions.contains { $0.text == "不相关" } })
        let stopping = Task { await controller.stop() }
        transport.links[0].emit(.closed(1))
        await stopping.value
        var config = liveConfig()
        config.history = [
            CarLiveHistoryTurn(role: "user", text: "上次说过"),
            CarLiveHistoryTurn(role: "assistant", text: "上次回过")
        ]
        let second = Task { await controller.start(configuration: config) }
        #expect(await waitUntil { transport.links.count == 2 })
        #expect(controller.captions.map(\.text) == ["上次说过", "上次回过"])
        #expect(controller.captions.map(\.role) == ["user", "assistant"])
        #expect(controller.captions.map(\.sequence) == [1, 2])
        #expect(controller.captions.contains { $0.text == "不相关" } == false)
        transport.links[1].emit(.started(sessionID: "live-history"))
        await second.value
        await controller.stop()
    }

    @Test @MainActor func rejectedStartKeepsPreviousCaptions() async {
        let transport = CarLiveFreshTransport()
        defer { transport.finishAll() }
        let audio = CarLiveProbeAudio()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let first = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.links.count == 1 })
        transport.links[0].emit(.started(sessionID: "live-old"))
        await first.value
        transport.links[0].emit(.inputTranscript("保留"))
        #expect(await waitUntil { controller.captions.contains { $0.text == "保留" } })
        let stopping = Task { await controller.stop() }
        transport.links[0].emit(.closed(1))
        await stopping.value
        audio.permissionGranted = false
        await controller.start(configuration: liveConfig())
        #expect(controller.captions.contains { $0.text == "保留" })
        #expect(controller.phase == .failed)
        var missing = liveConfig()
        missing.builderToken = " "
        await controller.start(configuration: missing)
        #expect(controller.captions.contains { $0.text == "保留" })
        #expect(controller.phase == .failed)
    }

    @Test @MainActor func staleOpenClosesOwnSocketAndLeavesNewCapture() async {
        let audio = CarLiveProbeAudio()
        let transport = CarLiveGateTransport()
        defer { transport.cancelAll() }
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let first = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 1 })
        let second = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { transport.openCount == 2 })
        let stale = CarLiveHoldLink()
        transport.release(stale)
        await first.value
        #expect(stale.closed)
        #expect(audio.stopCalls.isEmpty)
        let live = CarLiveHoldLink()
        transport.release(live)
        live.emit(.started(sessionID: "live-new"))
        await second.value
        #expect(controller.phase == .listening)
        #expect(audio.current != 0)
        #expect(audio.stopCalls.contains(audio.current) == false)
        await controller.stop()
    }

    @Test @MainActor func permissionWaitThenNewStartDoesNotStopLaterCapture() async {
        let audio = CarLiveProbeAudio()
        audio.holdPermission = true
        let transport = CarLiveGateTransport()
        defer { transport.cancelAll(); audio.grantPermission() }
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let first = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { audio.waitingPermissions == 1 })
        let second = Task { await controller.start(configuration: liveConfig()) }
        #expect(await waitUntil { audio.waitingPermissions == 2 })
        audio.grantPermission()
        #expect(await waitUntil { transport.openCount >= 1 })
        await first.value
        #expect(audio.stopCalls.isEmpty)
        let live = CarLiveHoldLink()
        transport.release(live)
        live.emit(.started(sessionID: "live-after-permission"))
        await second.value
        #expect(controller.phase == .listening)
        #expect(audio.current != 0)
        await controller.stop()
    }

    @Test @MainActor func serverClosedStopsCaptureWithoutFailingAndKeepsLateUsage() async {
        let link = CarLiveHoldLink()
        let audio = CarLiveProbeAudio()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: audio,
            closeGrace: 0.12
        )
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        #expect(controller.phase == .listening)
        link.emit(.closed(nil))
        link.emit(.portalUsage(requestID: "voice-1", estimatedUSD: 0.04, confirmed: false, status: "provisional"))
        #expect(await waitUntil { controller.phase == .idle })
        #expect(controller.phase != .failed)
        #expect(controller.errorMessage == nil)
        #expect(controller.portalEstimatedUSD == 0.04)
        #expect(controller.usageUnconfirmed)
        #expect(audio.current == 0)
    }

    @Test @MainActor func audioSendFailureStopsLocallyWithoutAnotherPost() async {
        let link = CarLiveHoldLink()
        link.failAudio = true
        let audio = CarLiveProbeAudio()
        let transport = CarLiveFixedReadyTransport(link: link)
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        audio.pushFrame()
        #expect(await waitUntil { controller.phase == .failed })
        #expect(controller.errorMessage != nil)
        #expect(transport.openCount == 1)
    }

    @Test @MainActor func transcriptToolTranscriptKeepsArrivalOrderAndStableIdentity() async throws {
        let link = CarLiveHoldLink()
        let hold = ToolHold()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: CarLiveProbeAudio(),
            closeGrace: 0.05
        )
        try await finishLive(hold: hold, link: link, controller: controller) {
            controller.toolExecutor = { _ in
                await hold.wait()
                return CarLiveToolResult(output: "ok")
            }
            let starting = Task { await controller.start(configuration: liveConfig()) }
            link.emit(.started(sessionID: "live-order"))
            await starting.value

            link.emit(.inputTranscript("hel"))
            link.emit(.inputTranscript("lo"))
            try #require(await waitUntil { controller.captions.first?.text == "hello" })
            #expect(controller.captions.count == 1)
            let userID = controller.captions[0].id
            let userSequence = controller.captions[0].sequence
            #expect(userSequence > 0)

            link.emit(.hosted(.functionCall(callID: "call-1", name: "echo", arguments: "text=ok")))
            try #require(await waitUntil { controller.activities.contains { $0.id == "call-1" } })
            let tool = controller.activities[0]
            #expect(tool.sequence > userSequence)
            #expect(tool.result.isEmpty)

            link.emit(.outputTranscript("there"))
            try #require(await waitUntil { controller.captions.contains { $0.role == "assistant" && $0.text == "there" } })
            link.emit(.inputTranscript(" later"))
            try #require(await waitUntil { controller.captions.filter { $0.role == "user" }.count == 2 })
            #expect(controller.captions[0].id == userID)
            #expect(controller.captions[0].sequence == userSequence)
            #expect(controller.captions[0].text == "hello")
            #expect(controller.captions[1].role == "assistant")
            #expect(controller.captions[1].text == "there")
            let secondUser = try #require(controller.captions.last { $0.role == "user" })
            #expect(secondUser.id != userID)
            #expect(secondUser.text == " later")
            #expect(secondUser.sequence > tool.sequence)
            #expect(secondUser.sequence > controller.captions[1].sequence)

            hold.release()
            try #require(await waitUntil {
                controller.activities.contains { $0.id == "call-1" && $0.status == "sent" && $0.result == "ok" }
            })
            let updated = controller.activities[0]
            #expect(updated.id == tool.id)
            #expect(updated.sequence == tool.sequence)

            let rows = CarLiveTimeline.rows(captions: controller.captions, activities: controller.activities)
            #expect(rows.map(CarLiveTimeline.kind) == ["user", "tool", "assistant", "user"])
        }
    }

    @Test @MainActor func interleavedDeltasStayOneRowPerRole() async throws {
        let link = CarLiveHoldLink()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: CarLiveProbeAudio(),
            closeGrace: 0.05
        )
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live-rows"))
        await starting.value
        link.emit(.inputTranscript(CarLiveTranscriptFragment(text: "你", eventID: "evt_1")))
        link.emit(.outputTranscript(CarLiveTranscriptFragment(text: "我", eventID: "evt_2")))
        link.emit(.inputTranscript(CarLiveTranscriptFragment(text: "好", eventID: "evt_3")))
        link.emit(.outputTranscript(CarLiveTranscriptFragment(text: "在", eventID: "evt_4")))
        try #require(await waitUntil {
            controller.captions.contains { $0.role == "assistant" && $0.text == "我在" }
        })
        let users = controller.captions.filter { $0.role == "user" }
        let assistants = controller.captions.filter { $0.role == "assistant" }
        #expect(users.count == 1)
        #expect(users.first?.text == "你好")
        #expect(assistants.count == 1)
        #expect(controller.captions.count == 2)
        link.finish()
        await controller.stop()
    }

    @Test @MainActor func toolEitherSideKeepsOrderWithoutPerTokenRows() async throws {
        let link = CarLiveHoldLink()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: CarLiveProbeAudio(),
            closeGrace: 0.05
        )
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live-tool-order"))
        await starting.value
        link.emit(.outputTranscript("先"))
        link.emit(.hosted(.functionCall(callID: "call-a", name: "echo", arguments: "{}")))
        try #require(await waitUntil { controller.activities.contains { $0.id == "call-a" } })
        link.emit(.inputTranscript("后"))
        link.emit(.outputTranscript("再"))
        link.emit(.outputTranscript("说"))
        try #require(await waitUntil { controller.captions.contains { $0.text == "再说" } })
        let rows = CarLiveTimeline.rows(captions: controller.captions, activities: controller.activities)
        #expect(rows.map(CarLiveTimeline.kind) == ["assistant", "tool", "user", "assistant"])
        #expect(controller.captions.filter { $0.role == "assistant" }.map(\.text) == ["先", "再说"])
        link.emit(.inputTranscript("A"))
        link.emit(.outputTranscript("B"))
        link.emit(.inputTranscript("C"))
        try #require(await waitUntil { controller.captions.contains { $0.text == "后AC" } })
        #expect(controller.captions.filter { $0.role == "user" }.count == 1)
        #expect(controller.captions.filter { $0.role == "assistant" }.count == 2)
        link.finish()
        await controller.stop()
    }

    @Test @MainActor func playbackIdleDoesNotSplitCaptions() async throws {
        let link = CarLiveHoldLink()
        let audio = CarLiveProbeAudio()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: audio,
            closeGrace: 0.05
        )
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live-idle"))
        await starting.value
        link.emit(.outputAudio(Data([1, 0])))
        #expect(await waitUntil { controller.phase == .speaking })
        link.emit(.inputTranscript("你"))
        link.emit(.outputTranscript("我"))
        link.emit(.inputTranscript("好"))
        try #require(await waitUntil { controller.captions.contains { $0.text == "你好" } })
        audio.emitIdle()
        #expect(await waitUntil { controller.phase == .listening })
        link.emit(.outputTranscript("再"))
        link.emit(.inputTranscript("呀"))
        try #require(await waitUntil {
            controller.captions.contains { $0.role == "user" && $0.text == "你好呀" }
        })
        #expect(controller.captions.filter { $0.role == "user" }.map(\.text) == ["你好呀"])
        #expect(controller.captions.filter { $0.role == "assistant" }.map(\.text) == ["我再"])
        #expect(audio.clears == 0)
        link.finish()
        await controller.stop()
    }

    @Test @MainActor func bargeHoldDropsTailThenPlaysNextReplyAndStopDoesNotMute() async throws {
        let clock = CarLiveClock()
        clock.pin(10)
        let link = CarLiveHoldLink()
        let audio = CarLiveProbeAudio()
        let controller = CarLiveController(
            transport: CarLiveFixedReadyTransport(link: link),
            audio: audio,
            closeGrace: 0.05,
            bargeSustain: 0,
            bargeRelease: 0.02,
            clock: clock
        )
        let starting = Task { await controller.start(configuration: liveConfig()) }
        link.emit(.started(sessionID: "live-barge"))
        await starting.value
        link.emit(.outputAudio(Data([1, 0])))
        link.emit(.outputTranscript("先"))
        #expect(await waitUntil { controller.phase == .speaking && audio.enqueued == 1 })
        audio.emitLevel(input: 0.5, output: 0.2)
        #expect(await waitUntil { audio.holdBegins == 1 })
        audio.emitLevel(input: 0.6, output: 0)
        #expect(await waitUntil { controller.inputLevel == 0.6 })
        #expect(audio.holdBegins == 1)
        link.emit(.outputAudio(Data([2, 0])))
        link.emit(.inputTranscript("你"))
        link.emit(.inputTranscript("好"))
        try #require(await waitUntil { controller.captions.contains { $0.role == "user" && $0.text == "你好" } })
        #expect(audio.enqueued == 1)
        #expect(controller.captions.filter { $0.role == "user" }.count == 1)
        clock.pin(10.05)
        audio.emitLevel(input: 0.01, output: 0)
        #expect(await waitUntil { controller.inputLevel == 0.01 })
        clock.pin(10.08)
        audio.emitLevel(input: 0.02, output: 0)
        #expect(await waitUntil { controller.inputLevel == 0.02 })
        link.emit(.outputAudio(Data([3, 0])))
        link.emit(.outputTranscript("新"))
        #expect(await waitUntil { audio.enqueued == 2 })
        try #require(await waitUntil { controller.captions.contains { $0.role == "assistant" && $0.text == "先新" } })
        #expect(controller.captions.filter { $0.role == "assistant" }.count == 1)
        #expect(controller.isMuted == false)
        controller.interruptPlayback()
        controller.interruptPlayback()
        #expect(audio.holdBegins == 2)
        link.finish()
        await controller.stop()
        await controller.stop()
        let sent = link.sentSnapshot()
        let closes = sent.reduce(into: 0) { count, event in
            if case .close = event { count += 1 }
        }
        let mutes = sent.reduce(into: 0) { count, event in
            if case .mute = event { count += 1 }
        }
        #expect(closes == 1)
        #expect(mutes == 0)
        #expect(controller.isMuted == false)
    }

    @Test func controlCenterInactiveDoesNotRelinquishLive() {
        #expect(CarLiveScenePolicy.shouldRelinquish(.inactive) == false)
        #expect(CarLiveScenePolicy.shouldRelinquish(.active) == false)
        #expect(CarLiveScenePolicy.shouldRelinquish(.background))
    }

    @Test func idleErrorIsVisibleWithoutChangingPhase() {
        let idle = CarLiveFixture.idleErrorSnapshot()
        #expect(idle.phase == .idle)
        #expect(idle.hasVisibleError)
        #expect(CarLivePresentation.showsError(idle))
        #expect(CarLivePresentation.errorLine(idle) == CarLiveCopy.notConnected)
        let connected = CarLiveFixture.connectedSnapshot()
        #expect(connected.errorMessage == nil)
        #expect(CarLivePresentation.showsError(connected) == false)
        var blank = CarLiveSnapshot()
        blank.errorMessage = "   "
        #expect(blank.hasVisibleError == false)
        #expect(CarLivePresentation.showsError(blank) == false)
    }
}

private final class ToolHold: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume()
        }
    }
}

nonisolated private final class CarLiveFixedReadyTransport: CarLiveTransporting, @unchecked Sendable {
    var link: CarLiveHoldLink
    private(set) var openCount = 0

    init(link: CarLiveHoldLink) {
        self.link = link
    }

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        openCount += 1
        return link
    }
}

private final class CarLiveFreshTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var links: [CarLiveHoldLink] = []

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let link = CarLiveHoldLink()
        lock.withLock { links.append(link) }
        return link
    }

    func finishAll() {
        let pending = lock.withLock { links }
        for link in pending {
            link.finish()
        }
    }
}
