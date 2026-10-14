import Foundation
import Testing
@testable import OpenCodeClient

struct SSELifecycleTests {
    @Test @MainActor func cancelBeforeStartDoesNotBootstrapOrWatchdog() async {
        let api = HoldingMockAPIClient()
        let sse = ScriptedSSEClient()
        let state = makeIsolatedAppState(apiClient: api, sseClient: sse)
        state.currentSessionID = "s1"
        state.connectSSE()
        let task = state.sseTask
        state.disconnectSSE()
        await task?.value
        #expect(await api.messagesCallCount() == 0)
        #expect(await sse.connectCount == 0)
        #expect(state.sseWatchdogTask == nil)
        #expect(state.sseTask == nil)
    }

    @Test @MainActor func disconnectDuringBootstrapDoesNotCreateWatchdog() async {
        let api = HoldingMockAPIClient()
        await api.hold.arm()
        let sse = ScriptedSSEClient()
        await sse.setScripts([.finish])
        let state = makeIsolatedAppState(apiClient: api, sseClient: sse)
        state.currentSessionID = "s1"
        state.connectSSE()
        let task = state.sseTask
        await api.hold.waitUntilEntered()
        #expect(state.sseWatchdogTask == nil)
        state.disconnectSSE()
        await api.hold.release()
        await task?.value
        #expect(state.sseWatchdogTask == nil)
        #expect(state.sseTask == nil)
        #expect(await sse.connectCount == 1)
    }

    @Test @MainActor func hostChangeDuringBootstrapDoesNotCreateWatchdog() async {
        let api = HoldingMockAPIClient()
        await api.hold.arm()
        let sse = ScriptedSSEClient()
        await sse.setScripts([.finish])
        let state = makeIsolatedAppState(apiClient: api, sseClient: sse)
        state.currentSessionID = "s1"
        let host = state.captureHostRequestSnapshot()
        state.connectSSE()
        let task = state.sseTask
        await api.hold.waitUntilEntered()
        state.hostRequestGeneration &+= 1
        #expect(!state.isCurrentHostRequest(host))
        await api.hold.release()
        await task?.value
        #expect(state.sseWatchdogTask == nil)
        #expect(await sse.connectCount == 1)
    }

    @Test @MainActor func oldConnectionCleanupDoesNotCancelNewWatchdog() async {
        let api = HoldingMockAPIClient()
        await api.hold.arm()
        let sse = ScriptedSSEClient()
        let hold = SSEHold()
        await sse.setScripts([.finish, .hold(hold)])
        let state = makeIsolatedAppState(apiClient: api, sseClient: sse)
        state.currentSessionID = "s1"
        state.connectSSE()
        let first = state.sseTask
        await api.hold.waitUntilEntered()
        state.connectSSE()
        let second = state.sseTask
        for _ in 0..<200 where state.sseWatchdogTask == nil {
            await Task.yield()
        }
        let watchdog = state.sseWatchdogTask
        #expect(watchdog != nil)
        #expect(state.captureSSEConnectionToken() != 0)
        #expect(state.isCurrentSSEConnection(state.captureSSEConnectionToken()))
        await api.hold.release()
        await first?.value
        #expect(state.sseWatchdogTask != nil)
        #expect(state.sseTask != nil)
        state.disconnectSSE()
        hold.finish()
        await second?.value
        #expect(state.sseWatchdogTask == nil)
        #expect(await sse.connectCount == 2)
    }

    @Test @MainActor func cleanEOFBacksOffBeforeReconnect() async {
        let sse = ScriptedSSEClient()
        await sse.setScripts([.finish, .finish, .finish])
        let state = makeIsolatedAppState(sseClient: sse)
        var delays: [TimeInterval] = []
        state.sseReconnectSleep = { seconds in
            delays.append(seconds)
            if delays.count == 3 {
                await state.disconnectSSE()
            }
        }
        state.connectSSE()
        let task = state.sseTask
        await task?.value
        #expect(delays == [2, 4, 8])
        #expect(await sse.connectCount == 3)
        #expect(state.sseTask == nil)
    }

    @Test @MainActor func authenticationFailurePausesAutomaticRetry() async throws {
        let sse = ScriptedSSEClient()
        await sse.setScripts([.fail(.httpStatus(401))])
        let state = makeIsolatedAppState(sseClient: sse)
        state.isConnected = true
        var delays: [TimeInterval] = []
        state.sseReconnectSleep = { seconds in
            delays.append(seconds)
        }
        state.connectSSE()
        await state.sseTask?.value
        #expect(delays.isEmpty)
        #expect(await sse.connectCount == 1)
        #expect(state.isConnected == false)
        #expect(state.sseTask == nil)
        #expect(state.sseWatchdogTask == nil)
        #expect(state.connectionError == L10n.t(.hostConnectionErrorBasicAuthRejected))
        #expect(state.connectionDiagnostic?.phase == .failed)
        #expect(state.connectionDiagnostic?.recoveryHint == L10n.t(.hostDiagnosticHintVerifyHostConfig))

        await sse.setScripts([.finish])
        state.serverURL = "http://127.0.0.1:9"
        state.sseReconnectSleep = { _ in
            await state.disconnectSSE()
        }
        await state.testConnection()
        await state.sseTask?.value
        #expect(state.isConnected == true)
        #expect(state.connectionError == nil)
        #expect(state.connectionDiagnostic?.phase == .connected)
        #expect(await sse.connectCount == 2)
    }

    @Test @MainActor func forbiddenPausesWithHTTPStatusCopy() async {
        let sse = ScriptedSSEClient()
        await sse.setScripts([.fail(.httpStatus(403))])
        let state = makeIsolatedAppState(sseClient: sse)
        state.isConnected = true
        var delays: [TimeInterval] = []
        state.sseReconnectSleep = { seconds in delays.append(seconds) }
        state.connectSSE()
        await state.sseTask?.value
        #expect(delays.isEmpty)
        #expect(state.isConnected == false)
        #expect(state.connectionError == L10n.t(.hostConnectionErrorHTTPStatus, Int32(403)))
        #expect(state.connectionDiagnostic?.phase == .failed)

        await sse.setScripts([.finish])
        state.serverURL = "http://127.0.0.1:9"
        state.sseReconnectSleep = { _ in
            await state.disconnectSSE()
        }
        await state.refresh()
        await state.sseTask?.value
        #expect(state.isConnected == true)
        #expect(state.connectionError == nil)
        #expect(state.connectionDiagnostic?.phase == .connected)
        #expect(await sse.connectCount == 2)
        #expect(delays.isEmpty)
    }

    @Test @MainActor func retryableHTTPStatusBacksOff() async {
        let sse = ScriptedSSEClient()
        await sse.setScripts([.fail(.httpStatus(500)), .fail(.notEventStream)])
        let state = makeIsolatedAppState(sseClient: sse)
        state.isConnected = true
        var delays: [TimeInterval] = []
        state.sseReconnectSleep = { seconds in
            delays.append(seconds)
            if delays.count == 2 {
                await state.disconnectSSE()
            }
        }
        state.connectSSE()
        await state.sseTask?.value
        #expect(delays == [2, 4])
        #expect(await sse.connectCount == 2)
        #expect(state.isConnected == true)
        #expect(state.connectionError == nil)
    }

    @Test @MainActor func idleThenSnapshotConvergesActivityWithoutSecondIdle() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.sessionStatuses["s1"] = SessionStatus(type: "busy", attempt: 1, message: "Thinking", next: nil)
        state.sessionActivities["s1"] = SessionActivity(
            sessionID: "s1",
            state: .running,
            text: "Thinking",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            anchorMessageID: nil
        )
        state.messages = [try row(id: "a1", completed: nil)]
        await api.setMessagesResult([try row(id: "a1", completed: 130_000)])

        await state.applySSEEventForTesting(idleEvent)
        #expect(state.sessionActivities["s1"]?.state == .completed)
        #expect(state.sessionActivities["s1"]?.endedAt?.timeIntervalSince1970 == 130)
        #expect(state.sessionActivities["s1"]?.anchorMessageID == "a1")
        let calls = await api.messagesCallCount
        #expect(calls == 1)

        await state.applySSEEventForTesting(idleEvent)
        #expect(await api.messagesCallCount == calls)
        #expect(state.sessionActivities["s1"]?.state == .completed)
    }

    @Test @MainActor func completedSnapshotStaysRunningWhileToolOpenOrUnfinished() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        let running = runningActivity(sessionID: "s1")
        let busy = SessionStatus(type: "busy", attempt: 1, message: "Thinking", next: nil)

        state.sessionStatuses["s1"] = busy
        state.sessionActivities["s1"] = running
        var completed = try row(id: "a1", completed: 130_000)
        completed.parts = [try toolPart(status: "running")]
        await api.setMessagesResult([completed])
        await state.applySSEEventForTesting(idleEvent)
        #expect(state.sessionActivities["s1"]?.state == .running)
        #expect(state.sessionActivities["s1"]?.endedAt == nil)

        state.sessionStatuses["s1"] = busy
        state.sessionActivities["s1"] = running
        completed.parts = [try toolPart(status: "pending")]
        await api.setMessagesResult([completed])
        await state.applySSEEventForTesting(idleEvent)
        #expect(state.sessionActivities["s1"]?.state == .running)
        #expect(state.sessionActivities["s1"]?.endedAt == nil)

        state.sessionStatuses["s1"] = busy
        state.sessionActivities["s1"] = running
        await api.setMessagesResult([try row(id: "a1", completed: nil)])
        await state.applySSEEventForTesting(idleEvent)
        #expect(state.sessionActivities["s1"]?.state == .running)
        #expect(state.sessionActivities["s1"]?.endedAt == nil)
    }

    @Test @MainActor func otherSessionIdleDoesNotCompleteFromCurrentWindow() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.currentSessionID = "s1"
        state.messages = [try row(id: "a1", completed: 130_000)]
        state.sessionStatuses["s2"] = SessionStatus(type: "busy", attempt: 1, message: "Thinking", next: nil)
        state.sessionActivities["s2"] = runningActivity(sessionID: "s2")
        let calls = await api.messagesCallCount

        await state.applySSEEventForTesting(otherSessionIdleEvent)

        #expect(state.sessionActivities["s2"]?.state == .running)
        #expect(state.sessionActivities["s2"]?.endedAt == nil)
        #expect(await api.messagesCallCount == calls)
    }

    @Test func acceptHTTPRequiresSuccessAndEventStream() throws {
        try SSEClient.acceptHTTP(statusCode: 200, contentType: "text/event-stream")
        try SSEClient.acceptHTTP(statusCode: 200, contentType: "text/event-stream; charset=utf-8")
        #expect(throws: SSEStreamFailure.httpStatus(401)) {
            try SSEClient.acceptHTTP(statusCode: 401, contentType: "text/html")
        }
        #expect(SSEStreamFailure.httpStatus(401).pausesAutomaticRetry)
        #expect(SSEStreamFailure.httpStatus(403).pausesAutomaticRetry)
        #expect(!SSEStreamFailure.httpStatus(500).pausesAutomaticRetry)
        #expect(throws: SSEStreamFailure.notEventStream) {
            try SSEClient.acceptHTTP(statusCode: 200, contentType: "text/html")
        }
        #expect(!SSEStreamFailure.notEventStream.pausesAutomaticRetry)
    }

    @Test func connectRejectsAuthAndHTMLBeforeYieldingEvents() async throws {
        let opener = RecordingSSEOpener()
        opener.statusCode = 401
        opener.contentType = "text/html"
        opener.body = Data("data: {\"payload\":{\"type\":\"server.heartbeat\"}}\n\n".utf8)
        let client = SSEClient(opener: opener)
        let denied = await client.connect(baseURL: "http://127.0.0.1:9", username: nil, password: nil)
        await #expect(throws: SSEStreamFailure.httpStatus(401)) {
            for try await _ in denied {}
        }
        #expect(opener.lastRequest?.url?.absoluteString == "http://127.0.0.1:9/global/event")
        #expect(opener.cancelCount == 1)

        opener.statusCode = 200
        opener.contentType = "text/html"
        opener.cancelCount = 0
        let html = await client.connect(baseURL: "http://127.0.0.1:9", username: nil, password: nil)
        await #expect(throws: SSEStreamFailure.notEventStream) {
            for try await _ in html {}
        }
        #expect(opener.cancelCount == 1)
    }

    @Test func connectYieldsEventStreamFrame() async throws {
        let opener = RecordingSSEOpener()
        opener.body = Data("data: {\"payload\":{\"type\":\"server.heartbeat\"}}\n\n".utf8)
        let client = SSEClient(opener: opener)
        let stream = await client.connect(baseURL: "127.0.0.1:9", username: "u", password: "p")
        var types: [String] = []
        for try await event in stream {
            types.append(event.payload.type)
        }
        #expect(types == ["server.heartbeat"])
        #expect(opener.lastRequest?.url?.absoluteString == "http://127.0.0.1:9/global/event")
        #expect(opener.lastRequest?.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let auth = opener.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Basic \(Data("u:p".utf8).base64EncodedString())")
    }

    @Test @MainActor func disconnectDuringBootstrapCancelsOldProducerOnly() async {
        let api = HoldingMockAPIClient()
        await api.hold.arm()
        let opener = TrackingSSEOpener()
        opener.frame = Data(#"data: {"payload":{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"idle"}}}}"#.utf8 + Data("\n\n".utf8))
        let sse = SSEClient(opener: opener)
        let state = makeIsolatedAppState(apiClient: api, sseClient: sse)
        state.serverURL = "http://127.0.0.1:9"
        state.currentSessionID = "s1"
        state.connectSSE()
        let first = state.sseTask
        await api.hold.waitUntilEntered()
        await opener.waitUntilOpenCount(1)
        state.disconnectSSE()
        await opener.waitUntilCancelled(1)
        #expect(opener.isCancelled(1))
        #expect(opener.openCount == 1)

        state.connectSSE()
        let second = state.sseTask
        await opener.waitUntilOpenCount(2)
        #expect(opener.isCancelled(1))
        #expect(!opener.isCancelled(2))
        #expect(opener.requestURL?.absoluteString == "http://127.0.0.1:9/global/event")

        await api.hold.release()
        await first?.value
        #expect(opener.openCount == 2)
        #expect(opener.isCancelled(1))
        #expect(!opener.isCancelled(2))
        #expect(state.sessionStatuses["s1"] == nil)
        state.disconnectSSE()
        opener.finish(2)
        await second?.value
    }

    @Test func burstFramesPreserveOrderAndUnicode() async throws {
        let opener = RecordingSSEOpener()
        let expected = (0..<512).map { "片段\($0) 🌙\nnext line" }
        opener.body = try expected.reduce(into: Data()) { body, text in
            let json = try JSONSerialization.data(withJSONObject: [
                "payload": ["type": "message.part.delta", "properties": ["delta": text]]
            ])
            body.append(Data("data: ".utf8))
            body.append(json)
            body.append(Data("\r\n\r\n".utf8))
        }
        let client = SSEClient(opener: opener)
        var received: [String] = []
        for try await event in await client.connect(baseURL: "http://127.0.0.1:9") {
            if let text = event.payload.properties?["delta"]?.value as? String {
                received.append(text)
            }
        }
        #expect(received == expected)
        #expect(opener.cancelCount == 1)
    }

    @Test func detachedReaderCancelledBeforeRegistrationStillStops() async {
        let owner = SSEConnectionCancel()
        let response = TrackedSSEResponse()
        owner.cancel()
        owner.bindResponse { response.cancel() }
        let reader = Task.detached {
            while !Task.isCancelled { await Task.yield() }
        }
        owner.bindProducer(reader)
        #expect(reader.isCancelled)
        #expect(response.isCancelled)
        // Ensure a failed expectation cannot leave a spinning test task.
        reader.cancel()
        await reader.value
    }

    @Test func detachedReaderAndResponseCancelTogether() async {
        let owner = SSEConnectionCancel()
        let response = TrackedSSEResponse()
        let reader = Task.detached {
            while !Task.isCancelled { await Task.yield() }
        }
        owner.bindResponse { response.cancel() }
        owner.bindProducer(reader)
        owner.cancel()
        owner.cancel()
        #expect(reader.isCancelled)
        #expect(response.isCancelled)
        reader.cancel()
        await reader.value
    }

    @Test func lateOpenClosesReturnedResource() async throws {
        let opener = LateOpenSSEOpener()
        await opener.gate.arm()
        let client = SSEClient(opener: opener)
        let lease = await client.connectLease(baseURL: "http://127.0.0.1:9", username: nil, password: nil)
        await opener.gate.waitUntilEntered()
        lease.cancel()
        #expect(opener.cancelCount == 0)
        await opener.gate.release()
        await opener.waitUntilCancelled()
        #expect(opener.openCount == 1)
        #expect(opener.cancelCount == 1)
        var yielded = 0
        for try await _ in lease.events {
            yielded += 1
        }
        #expect(yielded == 0)
    }
}

private let idleEvent = try! JSONDecoder().decode(SSEEvent.self, from: Data("""
{"payload":{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"idle"}}}}
""".utf8))

private let otherSessionIdleEvent = try! JSONDecoder().decode(SSEEvent.self, from: Data("""
{"payload":{"type":"session.status","properties":{"sessionID":"s2","status":{"type":"idle"}}}}
""".utf8))

private func runningActivity(sessionID: String) -> SessionActivity {
    SessionActivity(
        sessionID: sessionID,
        state: .running,
        text: "Running commands",
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: nil,
        anchorMessageID: nil
    )
}

private func toolPart(status: String) throws -> Part {
    try JSONDecoder().decode(Part.self, from: Data("""
    {"id":"p1","messageID":"a1","sessionID":"s1","type":"tool","tool":"bash","callID":"c1","state":{"status":"\(status)"}}
    """.utf8))
}

private func row(id: String, completed: Int?) throws -> MessageWithParts {
    let message = Message(
        id: id,
        sessionID: "s1",
        role: "assistant",
        parentID: nil,
        providerID: nil,
        modelID: nil,
        model: nil,
        error: nil,
        time: .init(created: 110_000, completed: completed),
        finish: nil,
        tokens: nil,
        cost: nil
    )
    return MessageWithParts(info: message, parts: [])
}

actor BootstrapHold {
    private var armed = false
    private var consumed = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []

    func arm() {
        armed = true
        consumed = false
    }

    func enter() async {
        guard armed, !consumed else { return }
        consumed = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiter = cont
            let pending = observers
            observers.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    func waitUntilEntered() async {
        if waiter != nil { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if waiter != nil {
                cont.resume()
            } else {
                observers.append(cont)
            }
        }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}

actor HoldingMockAPIClient: APIClientProtocol {
    let hold = BootstrapHold()
    private let inner = MockAPIClient()

    func messagesCallCount() async -> Int {
        await inner.messagesCallCount
    }

    func configure(baseURL: String, username: String?, password: String?) {}

    func health() async throws -> HealthResponse {
        try await inner.health()
    }

    func projects() async throws -> [Project] {
        try await inner.projects()
    }

    func projectCurrent() async throws -> Project? {
        try await inner.projectCurrent()
    }

    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        try await inner.sessions(directory: directory, limit: limit)
    }

    func session(sessionID: String) async throws -> Session {
        try await inner.session(sessionID: sessionID)
    }

    func createSession(title: String?, directory: String?) async throws -> Session {
        try await inner.createSession(title: title, directory: directory)
    }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        try await inner.updateSession(sessionID: sessionID, title: title)
    }

    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        try await inner.updateSessionArchived(sessionID: sessionID, archived: archived)
    }

    func deleteSession(sessionID: String) async throws {
        try await inner.deleteSession(sessionID: sessionID)
    }

    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
        await hold.enter()
        return try await inner.messages(sessionID: sessionID, limit: limit)
    }

    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
        try await inner.promptAsync(sessionID: sessionID, messageID: messageID, text: text, attachments: attachments, agent: agent, model: model, directory: directory)
    }

    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
        try await inner.promptStructured(sessionID: sessionID, messageID: messageID, text: text, system: system, format: format, agent: agent, model: model)
    }

    func abort(sessionID: String) async throws {
        try await inner.abort(sessionID: sessionID)
    }

    func sessionStatus() async throws -> [String: SessionStatus] {
        try await inner.sessionStatus()
    }

    func pendingPermissions() async throws -> [APIClient.PermissionRequest] {
        try await inner.pendingPermissions()
    }

    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {
        try await inner.respondPermission(sessionID: sessionID, permissionID: permissionID, response: response)
    }

    func pendingQuestions() async throws -> [QuestionRequest] {
        try await inner.pendingQuestions()
    }

    func replyQuestion(requestID: String, answers: [[String]]) async throws {
        try await inner.replyQuestion(requestID: requestID, answers: answers)
    }

    func rejectQuestion(requestID: String) async throws {
        try await inner.rejectQuestion(requestID: requestID)
    }

    func providers() async throws -> ProvidersResponse {
        try await inner.providers()
    }

    func providerRegistry() async throws -> ProviderRegistryResponse {
        try await inner.providerRegistry()
    }

    func agents() async throws -> [AgentInfo] {
        try await inner.agents()
    }

    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        try await inner.sessionDiff(sessionID: sessionID)
    }

    func sessionTodos(sessionID: String) async throws -> [TodoItem] {
        try await inner.sessionTodos(sessionID: sessionID)
    }

    func fileList(path: String, directory: String?) async throws -> [FileNode] {
        try await inner.fileList(path: path, directory: directory)
    }

    func fileContent(path: String, directory: String?) async throws -> FileContent {
        try await inner.fileContent(path: path, directory: directory)
    }

    func findFile(query: String, limit: Int) async throws -> [String] {
        try await inner.findFile(query: query, limit: limit)
    }

    func fileStatus() async throws -> [FileStatusEntry] {
        try await inner.fileStatus()
    }

    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        try await inner.forkSession(sessionID: sessionID, messageID: messageID)
    }

    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        try await inner.revertSession(sessionID: sessionID, messageID: messageID, partID: partID)
    }
}

actor ScriptedSSEClient: SSEClientProtocol {
    enum Script: Sendable {
        case finish
        case fail(SSEStreamFailure)
        case hold(SSEHold)
    }

    private var scripts: [Script] = [.finish]
    private(set) var connectCount = 0

    func setScripts(_ scripts: [Script]) {
        self.scripts = scripts
    }

    func connect(baseURL: String, username: String?, password: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        connectCount += 1
        let script = scripts.isEmpty ? Script.finish : scripts.removeFirst()
        switch script {
        case .finish:
            return AsyncThrowingStream { $0.finish() }
        case .fail(let error):
            return AsyncThrowingStream { $0.finish(throwing: error) }
        case .hold(let hold):
            return AsyncThrowingStream { continuation in
                hold.store(continuation)
            }
        }
    }
}

final class SSEHold: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation?

    func store(_ continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

final class RecordingSSEOpener: SSEHTTPOpener, @unchecked Sendable {
    var statusCode = 200
    var contentType: String? = "text/event-stream"
    var body = Data()
    var lastRequest: URLRequest?
    var cancelCount = 0

    func open(_ request: URLRequest) async throws -> SSEHTTPResponse {
        lastRequest = request
        let payload = body
        return SSEHTTPResponse(
            statusCode: statusCode,
            contentType: contentType,
            bytes: AsyncThrowingStream { continuation in
                for byte in payload {
                    continuation.yield(byte)
                }
                continuation.finish()
            },
            cancel: { [weak self] in
                self?.cancelCount += 1
            }
        )
    }
}

final class TrackedSSEResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<UInt8, Error>.Continuation?
    private var cancelled = false
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func hold(_ continuation: AsyncThrowingStream<UInt8, Error>.Continuation) {
        lock.lock()
        let already = cancelled
        if !already {
            self.continuation = continuation
        }
        lock.unlock()
        if already {
            continuation.finish()
        }
    }

    func cancel() {
        lock.lock()
        if cancelled {
            lock.unlock()
            return
        }
        cancelled = true
        let continuation = self.continuation
        self.continuation = nil
        let waiters = cancelWaiters
        cancelWaiters.removeAll()
        lock.unlock()
        continuation?.finish()
        waiters.forEach { $0.resume() }
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }

    func waitUntilCancelled() async {
        lock.lock()
        if cancelled {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if cancelled {
                lock.unlock()
                cont.resume()
                return
            }
            cancelWaiters.append(cont)
            lock.unlock()
        }
    }
}

final class TrackingSSEOpener: SSEHTTPOpener, @unchecked Sendable {
    var frame = Data()
    private let lock = NSLock()
    private var openCountStorage = 0
    private var requestURLStorage: URL?
    private var responses: [Int: TrackedSSEResponse] = [:]
    private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var openCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return openCountStorage
    }

    var requestURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return requestURLStorage
    }

    func open(_ request: URLRequest) async throws -> SSEHTTPResponse {
        let tracked = TrackedSSEResponse()
        let id: Int
        let payload: Data
        lock.lock()
        openCountStorage += 1
        id = openCountStorage
        requestURLStorage = request.url
        responses[id] = tracked
        payload = id == 1 ? frame : Data()
        let ready = openWaiters.filter { id >= $0.0 }.map(\.1)
        openWaiters.removeAll { id >= $0.0 }
        lock.unlock()
        ready.forEach { $0.resume() }
        return SSEHTTPResponse(
            statusCode: 200,
            contentType: "text/event-stream",
            bytes: AsyncThrowingStream { continuation in
                for byte in payload {
                    continuation.yield(byte)
                }
                tracked.hold(continuation)
            },
            cancel: { tracked.cancel() }
        )
    }

    func isCancelled(_ id: Int) -> Bool {
        lock.lock()
        let tracked = responses[id]
        lock.unlock()
        return tracked?.isCancelled ?? false
    }

    func waitUntilOpenCount(_ count: Int) async {
        lock.lock()
        if openCountStorage >= count {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if openCountStorage >= count {
                lock.unlock()
                cont.resume()
                return
            }
            openWaiters.append((count, cont))
            lock.unlock()
        }
    }

    func waitUntilCancelled(_ id: Int) async {
        let tracked: TrackedSSEResponse?
        lock.lock()
        tracked = responses[id]
        lock.unlock()
        await tracked?.waitUntilCancelled()
    }

    func finish(_ id: Int) {
        lock.lock()
        let tracked = responses[id]
        lock.unlock()
        tracked?.finish()
    }
}

final class LateOpenSSEOpener: SSEHTTPOpener, @unchecked Sendable {
    let gate = BootstrapHold()
    private let lock = NSLock()
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var openCount = 0
    private(set) var cancelCount = 0

    func open(_ request: URLRequest) async throws -> SSEHTTPResponse {
        lock.lock()
        openCount += 1
        lock.unlock()
        await gate.enter()
        let payload = Data("data: {\"payload\":{\"type\":\"server.heartbeat\"}}\n\n".utf8)
        return SSEHTTPResponse(
            statusCode: 200,
            contentType: "text/event-stream",
            bytes: AsyncThrowingStream { continuation in
                for byte in payload {
                    continuation.yield(byte)
                }
                continuation.finish()
            },
            cancel: { [weak self] in
                self?.noteCancel()
            }
        )
    }

    func waitUntilCancelled() async {
        lock.lock()
        if cancelCount > 0 {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if cancelCount > 0 {
                lock.unlock()
                cont.resume()
                return
            }
            cancelWaiters.append(cont)
            lock.unlock()
        }
    }

    private func noteCancel() {
        lock.lock()
        if cancelCount > 0 {
            lock.unlock()
            return
        }
        cancelCount = 1
        let waiters = cancelWaiters
        cancelWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
    }
}
