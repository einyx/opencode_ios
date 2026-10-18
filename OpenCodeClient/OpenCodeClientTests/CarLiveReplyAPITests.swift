import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveReplyAPITests {
    @Test func opaqueCursorIsNotTrimmedOrRewritten() {
        let spaced = "  opaque+cursor%2F  "
        let header = HTTPURLResponse(
            url: URL(string: "https://replyapi-cursor.invalid/session/s/message")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["X-Next-Cursor": spaced, "Link": "<https://evil.example/message?before=other>; rel=\"next\""]
        )
        #expect(APIClient.historyNextCursor(header!) == spaced)
        #expect(APIClient.linkBeforeCursor("<https://evil.example/x?limit=1&before=%20keep%2Bplus%2Fslash%20>; rel=\"next\"") == " keep+plus/slash ")
        #expect(APIClient.linkBeforeCursor("<https://evil.example/x?before=>; rel=\"next\"") == "")
        #expect(APIClient.linkBeforeCursor("<https://evil.example/prev?before=skip>; rel=\"prev\", <https://evil.example/next?before=kept>; rel=next") == "kept")
        #expect(APIClient.linkBeforeCursor("<https://evil.example/next?before=cursor>") == nil)
    }

    @Test func blankCursorAndDirectoryStayOnTheRequest() async throws {
        let host = replyHost()
        let api = replyClient(host: host, body: Data("[]".utf8), headers: ["X-Next-Cursor": "  next  "])
        let token = await api.armLiveTransport()
        let page = try await api.messagePageForLive(
            sessionID: "s1",
            limit: 2,
            before: "   ",
            directory: "",
            transportToken: token
        )
        let url = try #require(ReplyAPIGate.shared.urls(host).first)
        #expect(url.host == host)
        #expect(queryValue(url, "before") == "   ")
        #expect(queryValue(url, "directory") == "")
        #expect(queryValue(url, "limit") == "2")
        #expect(page.nextCursor == "  next  ")
        #expect(page.hasDecodeGaps == false)
        #expect(page.hasOlder == true)
        #expect(ReplyAPIGate.shared.urls(host).count == 1)
    }

    @Test func nilCursorOmitsPaginationAndLinkDoesNotRedirect() async throws {
        let host = replyHost()
        let link = "<https://evil.example/session/s1/message?before=%20from-link%20>; rel=\"next\""
        let api = replyClient(host: host, body: Data("[]".utf8), headers: ["Link": link])
        let token = await api.armLiveTransport()
        let page = try await api.messagePageForLive(
            sessionID: "s1",
            limit: 1,
            before: nil,
            directory: nil,
            transportToken: token
        )
        let url = try #require(ReplyAPIGate.shared.urls(host).first)
        #expect(url.host == host)
        #expect(url.host != "evil.example")
        #expect(queryValue(url, "before") == nil)
        #expect(queryValue(url, "directory") == nil)
        #expect(page.nextCursor == " from-link ")
        #expect(page.hasDecodeGaps == false)
        #expect(ReplyAPIGate.shared.urls(host).count == 1)
    }

    @Test func directoryStatusIsNotDroppedWhenBlank() async throws {
        let host = replyHost()
        let body = Data(#"{"s1":{"type":"busy","attempt":2}}"#.utf8)
        let api = replyClient(host: host, body: body, headers: [:])
        let token = await api.armLiveTransport()
        let statuses = try await api.sessionStatusForLive(directory: "  /work  ", transportToken: token)
        let url = try #require(ReplyAPIGate.shared.urls(host).first)
        #expect(url.path == "/session/status")
        #expect(queryValue(url, "directory") == "  /work  ")
        #expect(statuses["s1"]?.type == "busy")
        #expect(statuses["s1"]?.attempt == 2)
    }

    @Test func decodeGapStaysVisibleBesideCursor() async throws {
        let host = replyHost()
        let body = Data(#"""
        [
          {"info":{"id":"m1","sessionID":"s1","role":"assistant","time":{"created":1},"agent":"research"},"parts":[]},
          {"info":{"role":"user","time":{"created":2}},"parts":[]}
        ]
        """#.utf8)
        let api = replyClient(host: host, body: body, headers: ["X-Next-Cursor": "opaque+keep%2F"])
        let token = await api.armLiveTransport()
        let page = try await api.messagePageForLive(sessionID: "s1", limit: 2, before: "opaque+keep%2F", directory: "/work", transportToken: token)
        let url = try #require(ReplyAPIGate.shared.urls(host).first)
        #expect(queryValue(url, "before") == "opaque+keep%2F")
        #expect(queryValue(url, "directory") == "/work")
        #expect(page.nextCursor == "opaque+keep%2F")
        #expect(page.hasDecodeGaps == true)
        #expect(page.messages.map(\.info.id) == ["m1"])
        #expect(page.messages.first?.info.agent == "research")
    }

    @Test func protocolFallbackRejectsScopedParameters() async throws {
        let stub = ReplyFallbackStub()
        await #expect(throws: CarLiveAPIUnsupported.history) {
            try await stub.messagePageForLive(sessionID: "s", limit: 1, before: "   ", directory: nil, transportToken: 1)
        }
        await #expect(throws: CarLiveAPIUnsupported.history) {
            try await stub.messagePageForLive(sessionID: "s", limit: 1, before: nil, directory: "", transportToken: 1)
        }
        await #expect(throws: CarLiveAPIUnsupported.status) {
            try await stub.sessionStatusForLive(directory: " ", transportToken: 1)
        }
        #expect(await stub.unscopedHistoryCalls == 0)
        #expect(await stub.unscopedStatusCalls == 0)
        let sameScope = try await stub.messagePageForLive(sessionID: "s", limit: 1, before: nil, directory: nil, transportToken: 1)
        #expect(sameScope.nextCursor == "unscoped")
        #expect(await stub.unscopedHistoryCalls == 1)
    }

    @Test func legacyMessageAgentStaysOptional() throws {
        let missing = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"a","sessionID":"s","role":"assistant","time":{"created":1},"model":{"providerID":"openai","modelID":"gpt"}}"#.utf8))
        #expect(missing.agent == nil)
        #expect(missing.model?.modelID == "gpt")
        let assistant = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"a","sessionID":"s","role":"assistant","time":{"created":1},"agent":" research "}"#.utf8))
        #expect(assistant.agent == "research")
        let blank = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"a","sessionID":"s","role":"assistant","time":{"created":1},"agent":"  "}"#.utf8))
        #expect(blank.agent == nil)
        let user = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"u","sessionID":"s","role":"user","time":{"created":1},"agent":"build"}"#.utf8))
        #expect(user.agent == nil)
        let weird = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"a","sessionID":"s","role":"assistant","time":{"created":1},"agent":1}"#.utf8))
        #expect(weird.agent == nil)
        let constructed = Message(
            id: "a", sessionID: "s", role: "assistant", parentID: nil, providerID: nil, modelID: nil,
            model: nil, error: nil, time: .init(created: 1, completed: nil), finish: nil, tokens: nil, cost: nil
        )
        #expect(constructed.agent == nil)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(constructed)) as? [String: Any]
        #expect(encoded?["agent"] == nil)
        let kept = try JSONSerialization.jsonObject(with: JSONEncoder().encode(assistant)) as? [String: Any]
        #expect(kept?["agent"] as? String == "research")
    }
}

private func replyHost() -> String {
    "replyapi-\(UUID().uuidString.lowercased()).invalid"
}

private func replyClient(host: String, body: Data, headers: [String: String]) -> APIClient {
    ReplyAPIGate.shared.set(host: host, body: body, headers: headers)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ReplyAPIHTTP.self]
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    return APIClient(baseURL: "https://\(host)", username: "u", password: "p", session: URLSession(configuration: config))
}

private func queryValue(_ url: URL, _ name: String) -> String? {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard let item = items.first(where: { $0.name == name }) else { return nil }
    return item.value
}

private final class ReplyAPIGate: @unchecked Sendable {
    static let shared = ReplyAPIGate()
    private let lock = NSLock()
    private var bodies: [String: Data] = [:]
    private var headers: [String: [String: String]] = [:]
    private var hits: [String: [URL]] = [:]

    func set(host: String, body: Data, headers: [String: String]) {
        lock.lock()
        bodies[host] = body
        self.headers[host] = headers
        hits[host] = []
        lock.unlock()
    }

    func record(_ url: URL) -> (Data, [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        let host = url.host ?? ""
        hits[host, default: []].append(url)
        return (bodies[host] ?? Data("[]".utf8), headers[host] ?? [:])
    }

    func urls(_ host: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return hits[host] ?? []
    }
}

private final class ReplyAPIHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("replyapi-") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://replyapi-missing.invalid/")!
        let (body, headers) = ReplyAPIGate.shared.record(url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor ReplyFallbackStub: APIClientProtocol {
    private(set) var unscopedHistoryCalls = 0
    private(set) var unscopedStatusCalls = 0

    func configure(baseURL: String, username: String?, password: String?) {}
    func health() async throws -> HealthResponse { fatalError("unused") }
    func projects() async throws -> [Project] { fatalError("unused") }
    func projectCurrent() async throws -> Project? { fatalError("unused") }
    func sessions(directory: String?, limit: Int) async throws -> [Session] { fatalError("unused") }
    func session(sessionID: String) async throws -> Session { fatalError("unused") }
    func createSession(title: String?, directory: String?) async throws -> Session { fatalError("unused") }
    func updateSession(sessionID: String, title: String) async throws -> Session { fatalError("unused") }
    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session { fatalError("unused") }
    func deleteSession(sessionID: String) async throws { fatalError("unused") }
    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { fatalError("unused") }
    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws { fatalError("unused") }
    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts { fatalError("unused") }
    func abort(sessionID: String) async throws { fatalError("unused") }
    func sessionStatus() async throws -> [String: SessionStatus] { fatalError("unused") }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { fatalError("unused") }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws { fatalError("unused") }
    func pendingQuestions() async throws -> [QuestionRequest] { fatalError("unused") }
    func replyQuestion(requestID: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String) async throws { fatalError("unused") }
    func providers() async throws -> ProvidersResponse { fatalError("unused") }
    func providerRegistry() async throws -> ProviderRegistryResponse { fatalError("unused") }
    func agents() async throws -> [AgentInfo] { fatalError("unused") }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] { fatalError("unused") }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { fatalError("unused") }
    func fileList(path: String, directory: String?) async throws -> [FileNode] { fatalError("unused") }
    func fileContent(path: String, directory: String?) async throws -> FileContent { fatalError("unused") }
    func findFile(query: String, limit: Int) async throws -> [String] { fatalError("unused") }
    func fileStatus() async throws -> [FileStatusEntry] { fatalError("unused") }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session { fatalError("unused") }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session { fatalError("unused") }

    func messagePageForLive(sessionID: String, limit: Int, transportToken: UInt64) async throws -> CarLiveMessagePage {
        unscopedHistoryCalls += 1
        return CarLiveMessagePage(messages: [], hasOlder: false, requestedLimit: limit, nextCursor: "unscoped", hasDecodeGaps: false)
    }

    func sessionStatusForLive(transportToken: UInt64) async throws -> [String: SessionStatus] {
        unscopedStatusCalls += 1
        return ["unscoped": SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)]
    }
}
