import Foundation

nonisolated enum CarLiveTransportError: Error, Equatable, Sendable {
    case missingBuilderToken
    case unauthorized
    case forbidden
    case rejected
    case httpStatus(Int)
    case badResponse
    case rejectedWebSocket
    case socket
}

nonisolated protocol CarLiveSocket: Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func ping() async throws
    func close() async
    func noteSendTimeout()
}

nonisolated extension CarLiveSocket {
    func noteSendTimeout() {}
}

nonisolated protocol CarLiveSocketFactory: Sendable {
    func open(url: URL) async throws -> any CarLiveSocket
}

nonisolated protocol CarLiveLink: Sendable {
    var events: AsyncStream<CarLiveServerEvent> { get }
    func send(_ event: CarLiveClientEvent) async throws
    func send(_ event: CarLiveClientEvent, eventID: String) async throws
    func ping() async throws
    func close() async
    func noteSendTimeout()
}

nonisolated extension CarLiveLink {
    func noteSendTimeout() {}

    func send(_ event: CarLiveClientEvent, eventID: String) async throws {
        throw CarLiveTransportError.rejected
    }
}

nonisolated protocol CarLiveTransporting: Sendable {
    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink
}

nonisolated final class CarLiveRedirectRefuse: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        CarLiveSocketDiagnostics.note(webSocketTask, event: CarLiveLifecycleKind.socketOpened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Close reasons may contain server/user text. Keep only the numeric code.
        CarLiveSocketDiagnostics.note(webSocketTask, event: CarLiveLifecycleKind.socketClosed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let socket = task as? URLSessionWebSocketTask else { return }
        CarLiveSocketDiagnostics.note(socket, event: CarLiveLifecycleKind.socketCompleted, error: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

nonisolated enum CarLiveSocketDiagnostics {
    static func note(_ task: URLSessionWebSocketTask, event: String, error: Error? = nil) {
        #if os(watchOS)
        let ns = error as NSError?
        var record = CarLiveLifecycleRecord(
            runHash: CarLiveLifecycleLog.runHash(UInt64(task.taskIdentifier)),
            phase: "network", event: event,
            socketState: task.state.rawValue,
            socketCloseCode: task.closeCode.rawValue,
            networkErrorCode: ns?.code ?? 0,
            networkBytesSent: task.countOfBytesSent,
            networkBytesReceived: task.countOfBytesReceived
        )
        if let domain = ns?.domain {
            record.networkErrorDomain = [NSURLErrorDomain, NSPOSIXErrorDomain, NSCocoaErrorDomain].contains(domain) ? domain : "other"
        }
        CarLiveLifecycleLog.shared.note(record)
        #endif
    }
}

nonisolated enum CarLiveHTTP {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = CarLiveProtocol.startedDeadline
        config.timeoutIntervalForResource = CarLiveProtocol.startedDeadline
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: CarLiveRedirectRefuse(), delegateQueue: nil)
    }
}

nonisolated final class URLSessionCarLiveSocket: CarLiveSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ text: String) async throws {
        do {
            try await task.send(.string(text))
        } catch {
            CarLiveSocketDiagnostics.note(task, event: CarLiveLifecycleKind.socketSendFailed, error: error)
            throw error
        }
    }

    func receive() async throws -> String {
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            CarLiveSocketDiagnostics.note(task, event: CarLiveLifecycleKind.socketReceiveFailed, error: error)
            throw error
        }
        switch message {
        case .string(let text):
            return text
        case .data:
            throw CarLiveTransportError.socket
        @unknown default:
            throw CarLiveTransportError.socket
        }
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }

    func noteSendTimeout() {
        CarLiveSocketDiagnostics.note(task, event: CarLiveLifecycleKind.socketSendDeadline, error: task.error)
    }
}

nonisolated struct URLSessionCarLiveSocketFactory: CarLiveSocketFactory {
    var session: URLSession

    init(session: URLSession = CarLiveHTTP.makeSession()) {
        self.session = session
    }

    func open(url: URL) async throws -> any CarLiveSocket {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionCarLiveSocket(task: task)
    }
}

actor CarLiveSendSerializer {
    private let socket: any CarLiveSocket
    private var tail: Task<Void, Error>?
    private var closed = false
    private var generation: UInt64 = 0

    init(socket: any CarLiveSocket) {
        self.socket = socket
    }

    func send(_ text: String) async throws {
        let socket = socket
        try await enqueue {
            try await socket.send(text)
        }
    }

    func ping() async throws {
        let socket = socket
        try await enqueue {
            try await socket.ping()
        }
    }

    func close() async {
        closed = true
        generation &+= 1
        let previous = tail
        tail = nil
        previous?.cancel()
        await socket.close()
    }

    private func enqueue(_ body: @escaping @Sendable () async throws -> Void) async throws {
        if closed { throw CarLiveTransportError.socket }
        let generation = generation
        let previous = tail
        let job = Task {
            if let previous {
                try await previous.value
            }
            try Task.checkCancellation()
            guard await self.owns(generation) else { throw CarLiveTransportError.socket }
            try await body()
        }
        tail = job
        do {
            try await job.value
        } catch {
            await fail(generation)
            throw error
        }
    }

    private func owns(_ generation: UInt64) -> Bool {
        !closed && self.generation == generation
    }

    private func fail(_ generation: UInt64) {
        guard self.generation == generation, !closed else { return }
        self.generation &+= 1
        tail?.cancel()
        tail = nil
    }
}

nonisolated final class CarLiveSocketLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let sender: CarLiveSendSerializer
    private let socket: any CarLiveSocket
    private let reader: Task<Void, Never>
    private let state = CarLiveLinkState()

    init(socket: any CarLiveSocket) {
        self.socket = socket
        let sender = CarLiveSendSerializer(socket: socket)
        self.sender = sender
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { captured = $0 }
        let outbound = captured!
        continuation = outbound
        let box = state
        reader = Task {
            do {
                while !Task.isCancelled {
                    let text = try await socket.receive()
                    outbound.yield(CarLiveEventDecoder.decode(text))
                }
            } catch {
                if await box.isIntentional() == false {
                    outbound.yield(.failed("connection_lost"))
                }
            }
            outbound.finish()
        }
    }

    func send(_ event: CarLiveClientEvent) async throws {
        try await transmit(event, eventID: CarLiveWire.eventID())
    }

    func send(_ event: CarLiveClientEvent, eventID: String) async throws {
        guard CarLiveWire.commentaryClientEventID(eventID) == eventID else {
            throw CarLiveTransportError.rejected
        }
        try await transmit(event, eventID: eventID)
    }

    private func transmit(_ event: CarLiveClientEvent, eventID: String) async throws {
        guard let text = CarLiveWire.encode(event, eventID: eventID),
              let type = CarLiveWire.eventType(text),
              CarLiveWire.forbidden(type) == false,
              CarLiveWire.encodedEventID(text) == eventID else {
            throw CarLiveTransportError.rejected
        }
        try await sender.send(text)
    }

    func ping() async throws {
        try await sender.ping()
    }

    func noteSendTimeout() {
        socket.noteSendTimeout()
    }

    func close() async {
        await state.markClosed()
        reader.cancel()
        await sender.close()
        continuation.finish()
    }
}

private actor CarLiveLinkState {
    var intentionalClose = false

    func markClosed() {
        intentionalClose = true
    }

    func isIntentional() -> Bool {
        intentionalClose
    }
}

nonisolated struct CarLiveTransport: CarLiveTransporting {
    var session: URLSession
    var sockets: any CarLiveSocketFactory

    init(session: URLSession = CarLiveHTTP.makeSession(), sockets: (any CarLiveSocketFactory)? = nil) {
        self.session = session
        self.sockets = sockets ?? URLSessionCarLiveSocketFactory(session: session)
    }

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let token = configuration.builderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw CarLiveTransportError.missingBuilderToken }
        guard let url = CarLiveEndpoint.sessionURL(base: configuration.portalBaseURL) else {
            throw CarLiveTransportError.rejected
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = CarLiveProtocol.startedDeadline
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try CarLiveCreateBody.data(for: configuration)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CarLiveTransportError.socket
        }
        guard let http = response as? HTTPURLResponse else { throw CarLiveTransportError.badResponse }
        if http.statusCode == 401 { throw CarLiveTransportError.unauthorized }
        if http.statusCode == 403 { throw CarLiveTransportError.forbidden }
        guard CarLiveCreateBody.accepts(status: http.statusCode) else {
            throw CarLiveTransportError.httpStatus(http.statusCode)
        }
        guard let ticket = CarLiveTicketParser.parse(data),
              let wsURL = CarLiveEndpoint.resolveWebSocket(portalBase: configuration.portalBaseURL, wsURL: ticket.wsURL),
              CarLiveEndpoint.ticketMatches(url: wsURL, ticket: ticket.ticket) else {
            throw CarLiveTransportError.rejectedWebSocket
        }
        let socket: any CarLiveSocket
        do {
            socket = try await sockets.open(url: wsURL)
        } catch {
            throw CarLiveTransportError.socket
        }
        return CarLiveSocketLink(socket: socket)
    }
}
