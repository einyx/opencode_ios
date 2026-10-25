import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveBackgroundReturnTests {
    @Test func deadlineDoesNotJoinHungWork() async {
        let hang = ReturnHang()
        defer { hang.release() }
        let started = ContinuousClock.now
        let finished = await CarLiveDeadlineHandle.run(until: started.advanced(by: .milliseconds(40))) {
            await hang.wait()
        }
        let elapsed = started.duration(to: .now)
        #expect(finished == false)
        #expect(elapsed < .milliseconds(500))
    }

    @Test func cancelledDeadlineReturnsWithoutSpinning() async {
        let started = ContinuousClock.now
        let task = Task { () -> Bool in
            await CarLiveDeadlineHandle.run(until: started.advanced(by: .seconds(30))) {
                try? await Task.sleep(for: .seconds(30))
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        let finished = await task.value
        #expect(finished == false)
        #expect(started.duration(to: .now) < .milliseconds(500))
    }

    @Test func closeBudgetTreatsSuspendedElapsedAsSpent() {
        let start = ContinuousClock.now
        let deadline = start.advanced(by: .seconds(15))
        let later = start.advanced(by: .seconds(30))
        #expect(CarLiveCloseBudget.exceeded(now: later, deadline: deadline))
        #expect(CarLiveCloseBudget.remainingMS(now: later, deadline: deadline) == 0)
        #expect(CarLiveCloseBudget.exceeded(now: start, deadline: deadline) == false)
    }

    @Test @MainActor func hungCloseSendFinishesByGraceAndCanRestart() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let first = await listen(controller, transport)
        first.hangCloseSend = true
        let stopping = Task { await controller.stop() }
        let idle = await waitUntil(0.8) { controller.phase == .idle }
        #expect(idle)
        #expect(controller.usageUnconfirmed)
        if idle {
            await stopping.value
        } else {
            first.release()
            stopping.cancel()
        }
        #expect(await audio.stopCallsSnapshot() == [1])
        let restart = Task { await controller.start(configuration: returnConfig()) }
        #expect(await waitUntil(0.8) { transport.count() == 2 })
        let second = transport.link(1)
        second?.emit(.started(sessionID: "again"))
        await restart.value
        #expect(controller.phase == .listening)
        #expect(await audio.currentGeneration() != 0)
        #expect(await audio.stopCallsSnapshot().contains(await audio.currentGeneration()) == false)
        first.release()
        await controller.stop()
    }

    @Test @MainActor func repeatStopJoinsWithoutDeadlock() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let link = await listen(controller, transport)
        let first = Task { await controller.stop() }
        let second = Task { await controller.stop() }
        link.emit(.closed(1))
        await first.value
        await second.value
        #expect(controller.phase == .idle)
        #expect(await audio.stopCallsSnapshot() == [1])
        #expect(link.closeCount() <= 2)
    }

    @Test @MainActor func cancelledStopFinalizesWithoutBusyLoop() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 5)
        let link = await listen(controller, transport)
        link.hangCloseSend = true
        let stopping = Task { await controller.stop() }
        try? await Task.sleep(for: .milliseconds(30))
        stopping.cancel()
        let idle = await waitUntil(0.5) { controller.phase == .idle }
        #expect(idle)
        #expect(controller.usageUnconfirmed)
        if idle {
            await stopping.value
        } else {
            link.release()
            stopping.cancel()
        }
        link.release()
    }

    @Test @MainActor func elapsedBudgetFinalizesImmediatelyAndMarksUnconfirmed() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 15)
        let link = await listen(controller, transport)
        link.hangCloseSend = true
        let started = ContinuousClock.now
        let stopping = Task {
            await controller.stop(requestedAt: started.advanced(by: .seconds(-30)))
        }
        let idle = await waitUntil(0.4) { controller.phase == .idle }
        #expect(idle)
        #expect(controller.usageUnconfirmed)
        #expect(started.duration(to: .now) < .milliseconds(400))
        if idle {
            await stopping.value
        } else {
            link.release()
            stopping.cancel()
        }
        link.release()
    }

    @Test @MainActor func normalCloseStillCollectsFinalUsage() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.4)
        let link = await listen(controller, transport)
        let stopping = Task { await controller.stop() }
        #expect(await waitUntil(0.4) { link.sentClose() })
        link.emit(.portalUsage(requestID: "voice-1", estimatedUSD: 0.04, confirmed: true, status: "confirmed"))
        link.emit(.closed(2.5))
        await stopping.value
        #expect(controller.phase == .idle)
        #expect(controller.voiceSeconds == 2.5)
        #expect(controller.portalEstimatedUSD == 0.04)
        #expect(controller.usageUnconfirmed == false)
        #expect(controller.errorMessage == nil)
    }

    @Test @MainActor func oldCloseDoesNotStopNewCapture() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let first = await listen(controller, transport)
        first.hangSocketClose = true
        let stopping = Task { await controller.stop() }
        #expect(await waitUntil(0.8) { controller.phase == .idle })
        await stopping.value
        let restart = Task { await controller.start(configuration: returnConfig()) }
        #expect(await waitUntil(0.8) { transport.count() == 2 })
        transport.link(1)?.emit(.started(sessionID: "new"))
        await restart.value
        let generation = audio.currentGeneration()
        #expect(controller.phase == .listening)
        #expect(generation != 0)
        first.release()
        try? await Task.sleep(for: .milliseconds(40))
        #expect(await audio.currentGeneration() == generation)
        #expect(await audio.stopCallsSnapshot().contains(generation) == false)
        await controller.stop()
    }

    @Test @MainActor func backgroundCloseDoesNotAbortAndAllowsRestart() async {
        let audio = ReturnAudio()
        let transport = ReturnTransport()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.carLive = controller
        state.isConnected = true
        state.aiBuilderToken = "token"
        state.aiBuilderBaseURL = "https://portal.example"
        let starting = Task { await state.startCarLive() }
        #expect(await waitUntil(0.8) { transport.count() == 1 })
        transport.link(0)?.emit(.started(sessionID: "background"))
        await starting.value
        #expect(controller.phase == .listening)
        state.isConnected = false
        #expect(await waitUntil(0.8) { controller.phase == .idle })
        #expect(transport.count() == 1)
        #expect(await api.abortSessionIDs.isEmpty)
        state.isConnected = true
        let restart = Task { await state.startCarLive() }
        #expect(await waitUntil(0.8) { transport.count() == 2 })
        transport.link(1)?.emit(.started(sessionID: "restart"))
        await restart.value
        #expect(controller.phase == .listening)
        #expect(await api.abortSessionIDs.isEmpty)
        #expect(await audio.stopCallsSnapshot().contains(await audio.currentGeneration()) == false)
        await state.stopCarLive()
    }

    @Test func lifecycleLogRejectsSecretsAndTrims() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("carlive-log-\(UUID().uuidString)", isDirectory: true)
        let log = CarLiveLifecycleLog(directory: directory, maxBytes: 4_096)
        let secret = "Bearer sk-live-secret https://host.example/path?ticket=abc"
        let poisoned = CarLiveLifecycleRecord(
            phase: secret,
            event: secret,
            errorCode: secret,
            networkErrorDomain: secret
        )
        let object = CarLiveLifecycleLog.jsonObject(for: poisoned)
        #expect(Set(object.keys) == CarLiveLifecycleLog.allowedKeys)
        let encoded = try JSONSerialization.data(withJSONObject: object)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("sk-live-secret") == false)
        #expect(text.contains("ticket=") == false)
        #expect(text.contains("https://") == false)
        #expect(text.contains("Bearer") == false)
        #expect(object["event"] as? String == "other")
        #expect(object["phase"] as? String == "other")
        #expect(object["errorCode"] as? String == "other")
        #expect(object["networkErrorDomain"] as? String == "other")
        #expect(CarLiveLifecycleKind.relativePath == "Library/Application Support/CarLiveLifecycle/events.jsonl")
        log.note(poisoned)
        for _ in 0..<40 {
            log.note(CarLiveLifecycleRecord(phase: "closing", event: CarLiveLifecycleKind.closeEnd, errorCode: "none"))
        }
        await log.flush()
        let file = try Data(contentsOf: log.fileURL)
        #expect(file.count <= 4_096)
        let body = String(decoding: file, as: UTF8.self)
        #expect(body.contains("sk-live-secret") == false)
        #expect(body.contains("close_end"))
        for line in body.split(separator: "\n") where line.isEmpty == false {
            let row = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            #expect(Set(row.keys) == CarLiveLifecycleLog.allowedKeys)
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

private func returnConfig() -> CarLiveConfiguration {
    CarLiveConfiguration(
        portalBaseURL: URL(string: "https://portal.example/backend")!,
        builderToken: "builder-test",
        ownerToken: "owner-a"
    )
}

@MainActor
private func listen(_ controller: CarLiveController, _ transport: ReturnTransport) async -> ReturnLink {
    let starting = Task { await controller.start(configuration: returnConfig()) }
    #expect(await waitUntil(0.8) { transport.count() == 1 })
    let link = transport.link(0)!
    link.emit(.started(sessionID: "live"))
    await starting.value
    #expect(controller.phase == .listening)
    return link
}

private func waitUntil(_ seconds: TimeInterval, _ ready: @MainActor () -> Bool) async -> Bool {
    let steps = max(1, Int(seconds / 0.02))
    for _ in 0..<steps {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await MainActor.run(body: ready)
}

private final class ReturnHang: @unchecked Sendable {
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

private final class ReturnLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    var hangCloseSend = false
    var hangSocketClose = false
    private var sent: [CarLiveClientEvent] = []
    private var closes = 0
    private var gates: [CheckedContinuation<Void, Never>] = []

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) {
        continuation.yield(event)
    }

    func send(_ event: CarLiveClientEvent) async throws {
        let hang = lock.withLock { () -> Bool in
            sent.append(event)
            return hangCloseSend && event == .close
        }
        if hang {
            await withCheckedContinuation { continuation in
                lock.withLock { gates.append(continuation) }
            }
        }
    }

    func ping() async throws {}

    func close() async {
        let hang = lock.withLock { () -> Bool in
            closes += 1
            return hangSocketClose
        }
        if hang {
            await withCheckedContinuation { continuation in
                lock.withLock { gates.append(continuation) }
            }
        }
        continuation.finish()
    }

    func sentClose() -> Bool {
        lock.withLock { sent.contains(.close) }
    }

    func closeCount() -> Int {
        lock.withLock { closes }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let pending = gates
            gates.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume()
        }
    }
}

private final class ReturnTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var links: [ReturnLink] = []

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let link = ReturnLink()
        lock.withLock { links.append(link) }
        return link
    }

    func count() -> Int {
        lock.withLock { links.count }
    }

    func link(_ index: Int) -> ReturnLink? {
        lock.withLock { links.indices.contains(index) ? links[index] : nil }
    }
}

private final class ReturnAudio: CarLiveAudioEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var next: UInt64 = 0
    private var generation: UInt64 = 0
    private var stops: [UInt64] = []
    private var stream: CarLiveFrameStream?

    func requestRecordPermission() async -> Bool { true }

    func startCapture() async throws -> CarLiveCaptureHandle {
        let token = lock.withLock { () -> UInt64 in
            next &+= 1
            generation = next
            return next
        }
        let opened = CarLiveFrameStream(generation: token)
        lock.withLock { stream = opened }
        return CarLiveCaptureHandle(generation: token, frames: opened.frames) { opened.finish() }
    }

    func stopCapture(generation token: UInt64) async {
        let opened = lock.withLock { () -> CarLiveFrameStream? in
            stops.append(token)
            guard token == generation else { return nil }
            let opened = stream
            stream = nil
            generation = 0
            return opened
        }
        opened?.finish()
    }

    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}

    func currentGeneration() -> UInt64 {
        lock.withLock { generation }
    }

    func stopCallsSnapshot() -> [UInt64] {
        lock.withLock { stops }
    }
}
