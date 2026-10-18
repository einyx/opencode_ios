import Foundation
import Testing
@testable import OpenCodeClient

private final class CommentaryLegacyLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    private(set) var legacy: [CarLiveClientEvent] = []

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func send(_ event: CarLiveClientEvent) async throws {
        lock.withLock { legacy.append(event) }
    }

    func ping() async throws {}

    func close() async {
        continuation.finish()
    }

    func legacyCount() -> Int {
        lock.withLock { legacy.count }
    }
}

private final class CommentarySocket: CarLiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    private var receiveWaiter: CheckedContinuation<String, Error>?
    private var closed = false

    func send(_ text: String) async throws {
        lock.withLock { sent.append(text) }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let resume = lock.withLock { () -> Error? in
                if closed { return CarLiveTransportError.socket }
                receiveWaiter = continuation
                return nil
            }
            if let resume {
                continuation.resume(throwing: resume)
            }
        }
    }

    func ping() async throws {}

    func close() async {
        let waiter = lock.withLock { () -> CheckedContinuation<String, Error>? in
            closed = true
            let waiter = receiveWaiter
            receiveWaiter = nil
            return waiter
        }
        waiter?.resume(throwing: CarLiveTransportError.socket)
    }

    func snapshot() -> [String] {
        lock.withLock { sent }
    }
}

private final class CommentaryDeliveryLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    private var legacy: [CarLiveClientEvent] = []
    private var identified: [(CarLiveClientEvent, String)] = []
    private var hangWaiters: [CheckedContinuation<Void, Never>] = []
    var hangIdentified = false
    var failIdentified = false

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) {
        continuation.yield(event)
    }

    func send(_ event: CarLiveClientEvent) async throws {
        lock.withLock { legacy.append(event) }
    }

    func send(_ event: CarLiveClientEvent, eventID: String) async throws {
        if failIdentified { throw CarLiveTransportError.socket }
        if hangIdentified {
            await withCheckedContinuation { continuation in
                lock.withLock { hangWaiters.append(continuation) }
            }
        }
        if failIdentified { throw CarLiveTransportError.socket }
        lock.withLock { identified.append((event, eventID)) }
    }

    func ping() async throws {}

    func close() async {
        releaseHang()
        continuation.finish()
    }

    func identifiedStarted() -> Bool {
        lock.withLock { !hangWaiters.isEmpty }
    }

    func releaseHang() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let pending = hangWaiters
            hangWaiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume()
        }
    }

    func identifiedIDs() -> [String] {
        lock.withLock { identified.map(\.1) }
    }

    func legacyEvents() -> [CarLiveClientEvent] {
        lock.withLock { legacy }
    }
}

private struct CommentaryReadyTransport: CarLiveTransporting, Sendable {
    var link: CommentaryDeliveryLink
    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink { link }
}

private final class CommentaryAudio: CarLiveAudioEngine, @unchecked Sendable {
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

private func commentaryConfig(owner: String = "owner-a") -> CarLiveConfiguration {
    CarLiveConfiguration(
        portalBaseURL: URL(string: "https://space.example/backend")!,
        builderToken: "builder-test",
        ownerToken: owner
    )
}

private func waitUntil(_ ready: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<50 {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await MainActor.run(body: ready)
}

private func jsonObject(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

struct CarLiveCommentaryDeliveryTests {
    @Test func wireKeepsKnownIDAndNullDelegation() throws {
        let text = try #require(CarLiveWire.encode(.commentary("阶段回复"), eventID: "evt_known"))
        let object = try #require(jsonObject(text))
        #expect(object["type"] as? String == "session.commentary.append")
        #expect(object["event_id"] as? String == "evt_known")
        #expect(object["content"] as? String == "阶段回复")
        #expect(object["delegation_id"] is NSNull)
        #expect(CarLiveWire.encodedEventID(text) == "evt_known")
    }

    @Test func legacyEncodeStillEmitsNullDelegation() throws {
        let text = try #require(CarLiveWire.encode(.commentary("旧接口")))
        let object = try #require(jsonObject(text))
        let eventID = try #require(object["event_id"] as? String)
        #expect(eventID.isEmpty == false)
        #expect(object["delegation_id"] is NSNull)
        #expect(object["type"] as? String == "session.commentary.append")
    }

    @Test func defaultOverloadRejectsInsteadOfDroppingKnownID() async {
        let link = CommentaryLegacyLink()
        do {
            try await link.send(.commentary("不能丢"), eventID: "evt_keep")
            Issue.record("known id was not rejected")
        } catch let error as CarLiveTransportError {
            #expect(error == .rejected)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(link.legacyCount() == 0)
        try? await link.send(.commentary("旧入口"))
        #expect(link.legacyCount() == 1)
    }

    @Test func socketLinkKeepsKnownIDOnExistential() async throws {
        let socket = CommentarySocket()
        let opened = CarLiveSocketLink(socket: socket)
        let link: any CarLiveLink = opened
        defer { Task { await opened.close() } }
        try await link.send(.commentary("阶段回复"), eventID: "evt_socket")
        let text = try #require(socket.snapshot().first)
        let object = try #require(jsonObject(text))
        #expect(object["event_id"] as? String == "evt_socket")
        #expect(object["delegation_id"] is NSNull)
        #expect(object["type"] as? String == "session.commentary.append")
        do {
            try await link.send(.commentary("空号"), eventID: " ")
            Issue.record("blank id was sent")
        } catch let error as CarLiveTransportError {
            #expect(error == .rejected)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(socket.snapshot().count == 1)
        try await link.send(.commentary("旧入口"))
        #expect(socket.snapshot().count == 2)
        let legacyID = try #require(jsonObject(socket.snapshot()[1])?["event_id"] as? String)
        #expect(legacyID != "evt_socket")
        #expect(legacyID.isEmpty == false)
        await opened.close()
    }

    @Test func invalidAckIDIsNotLegalAck() {
        let valid = CarLiveEventDecoder.decode("{\"type\":\"session.commentary.appended\",\"client_event_id\":\"evt_ok\"}")
        guard case .commentaryAppended(let id) = valid else {
            Issue.record("valid ack missing")
            return
        }
        #expect(id == "evt_ok")
        let invalid = [
            "{\"type\":\"session.commentary.appended\"}",
            "{\"type\":\"session.commentary.appended\",\"client_event_id\":null}",
            "{\"type\":\"session.commentary.appended\",\"client_event_id\":\"\"}",
            "{\"type\":\"session.commentary.appended\",\"client_event_id\":\"  \"}",
            "{\"type\":\"session.commentary.appended\",\"client_event_id\":12}",
            "{\"type\":\"session.commentary.appended\",\"client_event_id\":true}"
        ]
        for text in invalid {
            if case .commentaryAppended = CarLiveEventDecoder.decode(text) {
                Issue.record("invalid ack treated as legal: \(text)")
            }
        }
    }

    @Test @MainActor func currentOwnerSubmitsKnownIDWithoutImplyingAck() async {
        let link = CommentaryDeliveryLink()
        let controller = CarLiveController(transport: CommentaryReadyTransport(link: link), audio: CommentaryAudio(), closeGrace: 0.05)
        var acks: [String] = []
        controller.onCommentaryAppended = { acks.append($0) }
        let starting = Task { await controller.start(configuration: commentaryConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        #expect(controller.phase == .listening)
        let wrong = await controller.appendCommentary("别人的", eventID: "evt_wrong", expectedOwner: "owner-b")
        #expect(wrong == false)
        #expect(link.identifiedIDs().isEmpty)
        let blank = await controller.appendCommentary("空", eventID: " ", expectedOwner: "owner-a")
        #expect(blank == false)
        let submitted = await controller.appendCommentary("阶段", eventID: "evt_owner", expectedOwner: "owner-a")
        #expect(submitted == true)
        #expect(link.identifiedIDs() == ["evt_owner"])
        #expect(acks.isEmpty)
        await controller.appendCommentary("旧接口")
        let legacy = link.legacyEvents()
        #expect(legacy.contains { event in
            if case .commentary(let text) = event { return text == "旧接口" }
            return false
        })
        await controller.stop()
    }

    @Test @MainActor func sendThrowReturnsFalseAndDoesNotAck() async {
        let link = CommentaryDeliveryLink()
        link.failIdentified = true
        let controller = CarLiveController(transport: CommentaryReadyTransport(link: link), audio: CommentaryAudio(), closeGrace: 0.05)
        var acks: [String] = []
        controller.onCommentaryAppended = { acks.append($0) }
        let starting = Task { await controller.start(configuration: commentaryConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        let submitted = await controller.appendCommentary("失败", eventID: "evt_fail", expectedOwner: "owner-a")
        #expect(submitted == false)
        #expect(acks.isEmpty)
        #expect(link.identifiedIDs().isEmpty)
        await controller.stop()
    }

    @Test @MainActor func earlyAckForwardsBeforeSendReturns() async {
        let link = CommentaryDeliveryLink()
        link.hangIdentified = true
        let controller = CarLiveController(transport: CommentaryReadyTransport(link: link), audio: CommentaryAudio(), closeGrace: 0.05)
        var acks: [String] = []
        controller.onCommentaryAppended = { acks.append($0) }
        let starting = Task { await controller.start(configuration: commentaryConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        let sending = Task { await controller.appendCommentary("早到", eventID: "evt_early", expectedOwner: "owner-a") }
        #expect(await waitUntil { link.identifiedStarted() })
        link.emit(.commentaryAppended(clientEventID: "evt_early"))
        #expect(await waitUntil { acks == ["evt_early"] })
        link.releaseHang()
        let submitted = await sending.value
        #expect(submitted == true)
        #expect(acks == ["evt_early"])
        #expect(link.identifiedIDs() == ["evt_early"])
        await controller.stop()
    }

    @Test @MainActor func lateRunAndClosingDropAckAndRejectSubmit() async {
        let link = CommentaryDeliveryLink()
        link.hangIdentified = true
        let controller = CarLiveController(transport: CommentaryReadyTransport(link: link), audio: CommentaryAudio(), closeGrace: 0.05)
        var acks: [String] = []
        controller.onCommentaryAppended = { acks.append($0) }
        let starting = Task { await controller.start(configuration: commentaryConfig()) }
        link.emit(.started(sessionID: "live"))
        await starting.value
        let sending = Task { await controller.appendCommentary("迟到", eventID: "evt_late", expectedOwner: "owner-a") }
        #expect(await waitUntil { link.identifiedStarted() })
        let stopping = Task { await controller.stop() }
        #expect(await waitUntil { controller.isClosingForPolicy || controller.phase == .idle })
        link.emit(.commentaryAppended(clientEventID: "evt_late"))
        link.emit(.commentaryAppended(clientEventID: ""))
        link.emit(.commentaryAppended(clientEventID: "  "))
        link.emit(.closed(1))
        try? await Task.sleep(for: .milliseconds(40))
        #expect(acks.isEmpty)
        link.releaseHang()
        let submitted = await sending.value
        await stopping.value
        link.emit(.commentaryAppended(clientEventID: "evt_late"))
        try? await Task.sleep(for: .milliseconds(40))
        #expect(submitted == false)
        #expect(acks.isEmpty)
        #expect(controller.phase == .idle)
    }
}
