import Foundation
import Testing
@testable import OpenCodeClient

private struct CarLiveHTTPBox: Sendable {
    var status: Int
    var body: Data
}

private final class CarLiveHTTPRegistry: @unchecked Sendable {
    static let shared = CarLiveHTTPRegistry()
    private let lock = NSLock()
    private var stubs: [String: CarLiveHTTPBox] = [:]
    private var hits: [String: Int] = [:]
    private var bodies: [String: Data] = [:]

    func set(host: String, status: Int, body: Data) {
        lock.withLock { stubs[host] = CarLiveHTTPBox(status: status, body: body) }
    }

    func stub(host: String) -> CarLiveHTTPBox? {
        lock.withLock {
            hits[host, default: 0] += 1
            return stubs[host]
        }
    }

    func storeBody(host: String, body: Data) {
        lock.withLock { bodies[host] = body }
    }

    func hitCount(_ host: String) -> Int {
        lock.withLock { hits[host] ?? 0 }
    }

    func body(_ host: String) -> Data? {
        lock.withLock { bodies[host] }
    }
}

private final class CarLiveOfflineHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("car-live-") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let stub = CarLiveHTTPRegistry.shared.stub(host: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        CarLiveHTTPRegistry.shared.storeBody(host: host, body: Self.requestBody(request))
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody, !body.isEmpty { return body }
        guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let capacity = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: capacity)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return stream.read(base, maxLength: capacity)
            }
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}

private final class CarLiveScriptedSocket: CarLiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var outbound: [String] = []
    private var inbound: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []
    private var closed = false

    deinit {
        cancelWaiters()
    }

    func send(_ text: String) async throws {
        lock.withLock { outbound.append(text) }
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let action = lock.withLock { () -> Result<String, Error>? in
                if closed { return .failure(CarLiveTransportError.socket) }
                if !inbound.isEmpty { return .success(inbound.removeFirst()) }
                waiters.append(continuation)
                return nil
            }
            if let action {
                switch action {
                case .success(let next):
                    continuation.resume(returning: next)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func ping() async throws {}

    func close() async {
        cancelWaiters()
    }

    private func cancelWaiters() {
        let pending = lock.withLock { () -> [CheckedContinuation<String, Error>] in
            closed = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume(throwing: CarLiveTransportError.socket)
        }
    }

    func sent() -> [String] {
        lock.withLock { outbound }
    }
}

private final class CarLiveRecordingFactory: CarLiveSocketFactory, @unchecked Sendable {
    let socket = CarLiveScriptedSocket()
    private let lock = NSLock()
    private(set) var opened: [URL] = []

    func open(url: URL) async throws -> any CarLiveSocket {
        lock.withLock { opened.append(url) }
        return socket
    }

    func urls() -> [URL] {
        lock.withLock { opened }
    }
}

private func liveSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CarLiveOfflineHTTP.self]
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 2
    config.waitsForConnectivity = false
    return URLSession(configuration: config, delegate: CarLiveRedirectRefuse(), delegateQueue: nil)
}

private func host() -> String {
    "car-live-\(UUID().uuidString.lowercased()).invalid"
}

private func ticketBody(wsURL: String) -> Data {
    let object: [String: String] = [
        "portal_session_id": "live_sess_1",
        "ticket": "ticket_1",
        "ws_url": wsURL,
        "expiry": "2026-10-16T23:00:00+00:00"
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

private func waitSend(_ ready: () -> Bool) async -> Bool {
    for _ in 0..<40 {
        if ready() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return ready()
}

private func configuration(base: URL, token: String = "builder-test") -> CarLiveConfiguration {
    CarLiveConfiguration(portalBaseURL: base, builderToken: token, ownerToken: "owner-a")
}

private final class CarLiveHoldSocket: CarLiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var entered = 0
    private var gates: [CheckedContinuation<Void, Error>] = []

    func send(_ text: String) async throws {
        lock.withLock { entered += 1 }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { gates.append(continuation) }
        }
    }

    func receive() async throws -> String {
        throw CarLiveHoldSocketError.receiveUnavailable
    }

    func enteredCount() -> Int {
        lock.withLock { entered }
    }

    func releaseOne() {
        let gate = lock.withLock { gates.removeFirst() }
        gate.resume()
    }

    func ping() async throws {}
    func close() async {}

    func releaseAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let pending = gates
            gates.removeAll()
            return pending
        }
        for gate in pending {
            gate.resume(throwing: CarLiveHoldSocketError.receiveUnavailable)
        }
    }
}

private enum CarLiveHoldSocketError: Error {
    case receiveUnavailable
}

struct CarLiveTransportTests {
    @Test func sendsStayOrderedAcrossActorReentry() async {
        let socket = CarLiveHoldSocket()
        defer { socket.releaseAll() }
        let serializer = CarLiveSendSerializer(socket: socket)
        let first = Task { try await serializer.send("a") }
        #expect(await waitSend { socket.enteredCount() == 1 })
        let second = Task { try await serializer.send("b") }
        try? await Task.sleep(for: .milliseconds(40))
        #expect(socket.enteredCount() == 1)
        socket.releaseOne()
        #expect(await waitSend { socket.enteredCount() == 2 })
        socket.releaseOne()
        _ = try? await first.value
        _ = try? await second.value
    }

    @Test func relativeBackendPathResolvesOnOrigin() {
        let base = URL(string: "https://space.ai-builders.com/backend")!
        let resolved = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "/backend/v1/audio/live/ws?ticket=ticket_1")
        #expect(resolved?.absoluteString == "wss://space.ai-builders.com/backend/v1/audio/live/ws?ticket=ticket_1")
    }

    @Test func relativePathUsesOriginNotBasePath() {
        let base = URL(string: "https://space.ai-builders.com/backend")!
        let resolved = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "/v1/audio/live/ws?ticket=ticket_1")
        #expect(resolved?.absoluteString == "wss://space.ai-builders.com/v1/audio/live/ws?ticket=ticket_1")
        #expect(resolved?.absoluteString.contains("/backend/backend") == false)
    }

    @Test func absoluteSameOriginBecomesWSSAndForeignOriginRejected() {
        let base = URL(string: "https://space.ai-builders.com/backend")!
        let same = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "https://space.ai-builders.com/backend/v1/audio/live/ws?ticket=ticket_1")
        #expect(same?.scheme == "wss")
        #expect(same?.host == "space.ai-builders.com")
        let foreign = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "https://api.openai.com/v1/live/sessions?ticket=ticket_1")
        #expect(foreign == nil)
    }

    @Test func socketResolverKeepsSecureOriginAndSingleTicket() {
        let https = URL(string: "https://portal.example/backend")!
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "ws://portal.example/v1/audio/live/ws?ticket=ticket_1") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "http://portal.example/v1/audio/live/ws?ticket=ticket_1") == nil)
        let explicitPort = URL(string: "https://portal.example:443/backend")!
        let sameOrigin = CarLiveEndpoint.resolveWebSocket(
            portalBase: explicitPort,
            wsURL: "wss://portal.example/v1/audio/live/ws?ticket=ticket_1"
        )
        #expect(sameOrigin?.scheme == "wss")
        #expect(sameOrigin?.port == nil)
        let dev = URL(string: "http://127.0.0.1:8787")!
        let allowed = CarLiveEndpoint.resolveWebSocket(
            portalBase: dev,
            wsURL: "ws://127.0.0.1:8787/v1/audio/live/ws?ticket=ticket_1"
        )
        #expect(allowed?.scheme == "ws")
        #expect(allowed?.host == "127.0.0.1")
        #expect(allowed?.port == 8787)
        let relative = CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/backend/v1/audio/live/ws?ticket=ticket_1")
        #expect(relative?.absoluteString == "wss://portal.example/backend/v1/audio/live/ws?ticket=ticket_1")
        #expect(relative?.absoluteString.contains("/backend/backend") == false)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?ticket=ticket_1&password=fixture_value") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?ticket=ticket_1#section") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?ticket=ticket_1&ticket=ticket_1") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?other=fixture_value") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?ticket=") == nil)
        #expect(CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "wss://user@portal.example/v1/audio/live/ws?ticket=ticket_1") == nil)
        let matched = CarLiveEndpoint.resolveWebSocket(portalBase: https, wsURL: "/v1/audio/live/ws?ticket=ticket_1")
        let url = matched
        #expect(url != nil)
        if let url {
            #expect(CarLiveEndpoint.ticketMatches(url: url, ticket: "ticket_1"))
            #expect(CarLiveEndpoint.ticketMatches(url: url, ticket: "other") == false)
        }
    }

    @Test func credentialQueryRejectedTicketAllowed() {
        let base = URL(string: "https://space.ai-builders.com/backend")!
        let leaked = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "/v1/audio/live/ws?ticket=ticket_1&token=sk-secret")
        #expect(leaked == nil)
        let ticket = CarLiveEndpoint.resolveWebSocket(portalBase: base, wsURL: "/v1/audio/live/ws?ticket=ticket_1")
        #expect(ticket?.query?.contains("ticket=ticket_1") == true)
        #expect(ticket?.query?.contains("token=") == false)
    }

    @Test func createAccepts200And201AndDoesNotSendSessionStart() async throws {
        for status in [200, 201] {
            let name = host()
            let base = URL(string: "https://\(name)/backend")!
            CarLiveHTTPRegistry.shared.set(host: name, status: status, body: ticketBody(wsURL: "/backend/v1/audio/live/ws?ticket=ticket_1"))
            let factory = CarLiveRecordingFactory()
            let transport = CarLiveTransport(session: liveSession(), sockets: factory)
            let link = try await transport.open(configuration(base: base))
            do {
                let opened = factory.urls()
                #expect(opened.count == 1)
                #expect(opened[0].absoluteString == "wss://\(name)/backend/v1/audio/live/ws?ticket=ticket_1")
                #expect(opened[0].absoluteString.contains("/backend/backend") == false)
                #expect(factory.socket.sent().contains { $0.contains("session.start") || $0.contains("session.update") } == false)
                let body = try #require(CarLiveHTTPRegistry.shared.body(name))
                let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["model"] == nil)
                #expect(json["instructions"] == nil)
                #expect(json["frontend_instructions"] != nil)
                #expect(json["backend_instructions"] != nil)
                #expect(json["tools"] != nil)
            } catch {
                await link.close()
                await factory.socket.close()
                throw error
            }
            await link.close()
            await factory.socket.close()
        }
    }

    @Test func unauthorizedAndForbiddenDoNotOpenSocket() async {
        for status in [401, 403] {
            let name = host()
            let base = URL(string: "https://\(name)/backend")!
            CarLiveHTTPRegistry.shared.set(host: name, status: status, body: Data("{}".utf8))
            let factory = CarLiveRecordingFactory()
            let transport = CarLiveTransport(session: liveSession(), sockets: factory)
            do {
                _ = try await transport.open(configuration(base: base))
                Issue.record("expected rejection")
            } catch let error as CarLiveTransportError {
                #expect(status == 401 ? error == .unauthorized : error == .forbidden)
            } catch {
                Issue.record("unexpected \(error)")
            }
            #expect(factory.urls().isEmpty)
        }
    }

    @Test func missingTokenDoesNotHitNetwork() async {
        let name = host()
        let base = URL(string: "https://\(name)/backend")!
        let factory = CarLiveRecordingFactory()
        let transport = CarLiveTransport(session: liveSession(), sockets: factory)
        do {
            _ = try await transport.open(configuration(base: base, token: "  "))
            Issue.record("expected missing token")
        } catch let error as CarLiveTransportError {
            #expect(error == .missingBuilderToken)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(CarLiveHTTPRegistry.shared.hitCount(name) == 0)
        #expect(factory.urls().isEmpty)
    }

    @Test func firstSendFailureDropsLateSend() async {
        let socket = CarLiveFailingSocket()
        defer { socket.fail() }
        let serializer = CarLiveSendSerializer(socket: socket)
        let first = Task { try? await serializer.send("a") }
        #expect(await waitSend { socket.enteredCount() == 1 })
        let second = Task { try? await serializer.send("b") }
        try? await Task.sleep(for: .milliseconds(40))
        socket.fail()
        _ = await first.value
        _ = await second.value
        #expect(socket.enteredCount() == 1)
    }

    @Test func serializerCloseDoesNotWaitForHungSend() async {
        let socket = CarLiveHoldSocket()
        defer { socket.releaseAll() }
        let serializer = CarLiveSendSerializer(socket: socket)
        let first = Task { try? await serializer.send("a") }
        #expect(await waitSend { socket.enteredCount() == 1 })
        let box = CloseFlag()
        let closing = Task {
            await serializer.close()
            await box.mark()
        }
        try? await Task.sleep(for: .milliseconds(200))
        let finished = await box.isDone()
        if finished == false {
            socket.releaseAll()
            _ = await closing.value
        }
        #expect(finished)
        #expect(socket.enteredCount() == 1)
    }
}

private final class CarLiveFailingSocket: CarLiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var entered = 0
    private var gates: [CheckedContinuation<Void, Error>] = []

    func send(_ text: String) async throws {
        lock.withLock { entered += 1 }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { gates.append(continuation) }
        }
    }

    func fail() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let pending = gates
            gates.removeAll()
            return pending
        }
        for gate in pending {
            gate.resume(throwing: CarLiveTransportError.socket)
        }
    }

    func receive() async throws -> String { throw CarLiveTransportError.socket }
    func ping() async throws {}
    func close() async {}

    func enteredCount() -> Int {
        lock.withLock { entered }
    }
}

private actor CloseFlag {
    private var done = false

    func mark() { done = true }

    func isDone() -> Bool { done }
}
