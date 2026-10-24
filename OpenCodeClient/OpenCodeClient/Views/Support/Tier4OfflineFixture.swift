import Foundation
import SwiftUI

@MainActor
@Observable
final class Tier4OfflineGate {
    static let shared = Tier4OfflineGate()

    var health = "hold"
    var send = "hold"
    var promptMessageID = ""
    private var credentials: [String: String] = [:]
    var credential: String {
        guard let key = observedState?.currentHostProfile?.basicAuth?.keychainPasswordID else { return "uncommitted" }
        return credentials[key] ?? "uncommitted"
    }
    weak var observedState: AppState?

    func reset() {
        health = "hold"
        send = "hold"
        promptMessageID = ""
        credentials = [:]
    }

    func access() -> HostCredentialAccess {
        HostCredentialAccess(
            save: { value, key in
                MainActor.assumeIsolated {
                    Tier4OfflineGate.shared.credentials[key] = value
                }
            },
            load: { key in
                MainActor.assumeIsolated {
                    Tier4OfflineGate.shared.credentials[key]
                }
            },
            delete: { key in
                MainActor.assumeIsolated {
                    Tier4OfflineGate.shared.credentials.removeValue(forKey: key)
                }
            }
        )
    }
}

enum Tier4OfflineFixture {
    static let argument = "UITEST_TIER4_OFFLINE_FIXTURE"
    static let sessionID = "tier4-offline-session"
    static let priorMessageID = "tier4-prior-user"
    static let serverURL = "https://offline.example.invalid"
    @MainActor private static var cachedState: AppState?
    @MainActor private static var didApply = false

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    @MainActor
    static func makeAppState() -> AppState {
        // SwiftUI may evaluate ContentView.init again while retaining its @State.
        // Keep the fixture's gate and SSE producer attached to that same state.
        if let cachedState { return cachedState }
        Tier4OfflineGate.shared.reset()
        let state = UITestFixtures.makeFixtureAppState(
            apiClient: StubClient(),
            sseClient: Tier4OfflineSSE.shared,
            label: "tier4-offline",
            hostCredentialAccess: Tier4OfflineGate.shared.access()
        )
        Tier4OfflineGate.shared.observedState = state
        cachedState = state
        return state
    }

    @MainActor
    static func apply(to state: AppState) {
        guard !didApply else { return }
        didApply = true
        state.isCarModeEnabled = true
        state.selectedTab = RootTab.chat.rawValue
        state.serverURL = serverURL
        state.isConnected = true
        state.sessions = [session]
        state.currentSessionID = sessionID
        state.connectSSE()
    }

    static var session: Session {
        Session(
            id: sessionID,
            slug: sessionID,
            projectID: "p1",
            directory: "/tmp/tier4-offline",
            parentID: nil,
            title: "Tier4 Offline",
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
    }

    @MainActor
    static func emitUserAck(messageID: String) {
        emitUserMessage(id: messageID)
    }

    @MainActor
    static func emitUnrelatedAck() {
        emitUserMessage(id: "tier4-unrelated-ack")
    }

    @MainActor
    private static func emitUserMessage(id: String) {
        let json = """
        {"payload":{"type":"message.updated","properties":{"sessionID":"\(sessionID)","info":{"id":"\(id)","sessionID":"\(sessionID)","role":"user","time":{"created":1,"completed":1}}}}}
        """
        guard let event = try? JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8)) else { return }
        Task { await Tier4OfflineSSE.shared.emit(event) }
    }

    actor StubClient: APIClientProtocol {
        func configure(baseURL: String, username: String?, password: String?) {}

        func health() async throws -> HealthResponse {
            while true {
                let decision = await MainActor.run { Tier4OfflineGate.shared.health }
                if decision == "failed" {
                    await MainActor.run { Tier4OfflineGate.shared.health = "hold" }
                    throw APIError.httpError(statusCode: 503, data: Data("offline-health".utf8))
                }
                if decision == "connected" {
                    await MainActor.run { Tier4OfflineGate.shared.health = "hold" }
                    return HealthResponse(healthy: true, version: "offline")
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        func currentGeneration() -> ServerGeneration { .auto }

        func projects() async throws -> [Project] { [] }
        func projectCurrent() async throws -> Project? { nil }
        func sessions(directory: String?, limit: Int) async throws -> [Session] { [Tier4OfflineFixture.session] }
        func session(sessionID: String) async throws -> Session {
            guard sessionID == Tier4OfflineFixture.sessionID else {
                throw APIError.httpError(statusCode: 404, data: Data())
            }
            return Tier4OfflineFixture.session
        }
        func createSession(title: String?, directory: String?) async throws -> Session { Tier4OfflineFixture.session }
        func updateSession(sessionID: String, title: String) async throws -> Session { Tier4OfflineFixture.session }
        func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session { Tier4OfflineFixture.session }
        func deleteSession(sessionID: String) async throws {}
        func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { [] }

        func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
            await MainActor.run {
                Tier4OfflineGate.shared.promptMessageID = messageID
            }
            while true {
                let decision = await MainActor.run { Tier4OfflineGate.shared.send }
                if decision == "failed" {
                    await MainActor.run {
                        Tier4OfflineGate.shared.send = "hold"
                    }
                    throw APIError.httpError(statusCode: 500, data: Data("offline-send".utf8))
                }
                if decision == "http" {
                    await MainActor.run {
                        Tier4OfflineGate.shared.send = "hold"
                    }
                    return
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func abort(sessionID: String) async throws {}
        func sessionStatus() async throws -> [String: SessionStatus] { [:] }
        func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
        func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
        func pendingQuestions() async throws -> [QuestionRequest] { [] }
        func replyQuestion(requestID: String, answers: [[String]]) async throws {}
        func rejectQuestion(requestID: String) async throws {}
        func providers() async throws -> ProvidersResponse {
            try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
        }
        func providerRegistry() async throws -> ProviderRegistryResponse {
            ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
        }
        func agents() async throws -> [AgentInfo] { [] }
        func sessionDiff(sessionID: String) async throws -> [FileDiff] { [] }
        func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
        func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }
        func fileContent(path: String, directory: String?) async throws -> FileContent {
            FileContent(type: "text", content: "")
        }
        func findFile(query: String, limit: Int) async throws -> [String] { [] }
        func fileStatus() async throws -> [FileStatusEntry] { [] }
        func forkSession(sessionID: String, messageID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
    }
}

actor Tier4OfflineSSE: SSEClientProtocol {
    static let shared = Tier4OfflineSSE()
    private var continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation?

    func connect(baseURL: String, username: String?, password: String?) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.store(continuation) }
        }
    }

    private func store(_ continuation: AsyncThrowingStream<SSEEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func emit(_ event: SSEEvent) {
        continuation?.yield(event)
    }
}

struct Tier4OfflineControls: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Tier4CredentialSentinel()
            Button("Health OK") {
                Tier4OfflineGate.shared.health = "connected"
            }
                .accessibilityIdentifier("tier4-release-health-connected")
            Button("Health Fail") {
                Tier4OfflineGate.shared.health = "failed"
            }
                .accessibilityIdentifier("tier4-release-health-failed")
            Button("Send Fail") {
                Tier4OfflineGate.shared.send = "failed"
            }
                .accessibilityIdentifier("tier4-release-send-fail")
            Button("Send HTTP") {
                Tier4OfflineGate.shared.send = "http"
            }
                .accessibilityIdentifier("tier4-release-send-http")
            Button("Send Ack") {
                let id = Tier4OfflineGate.shared.promptMessageID
                Tier4OfflineFixture.emitUserAck(messageID: id)
            }
                .accessibilityIdentifier("tier4-release-send-ack")
            Button("Send Other") {
                Tier4OfflineFixture.emitUnrelatedAck()
            }
                .accessibilityIdentifier("tier4-release-send-other")
        }
        .font(.caption2)
        .buttonStyle(.bordered)
        .padding(6)
    }
}

struct Tier4CredentialSentinel: View {
    var body: some View {
        Text(Tier4OfflineGate.shared.credential)
            .font(.caption2)
            .accessibilityIdentifier("host-credential-record")
            .accessibilityValue(Tier4OfflineGate.shared.credential)
    }
}
