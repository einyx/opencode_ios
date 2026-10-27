import Foundation
import SwiftUI

enum TurnStabilityFixture {
    static let argument = "UITEST_TURN_STABILITY_FIXTURE"
    static let sessionID = "w09-turn-session"
    static let firstID = "m1"
    static let secondID = "m2"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var mode: String {
        ProcessInfo.processInfo.environment["UITEST_TURN_STABILITY_MODE"] ?? "append"
    }

    static var showsAppendControls: Bool {
        isActive && mode == "append"
    }

    /// The "thinking" mode drives a live turn: the assistant message is
    /// still running, so the transcript has to show the thinking pill before
    /// any reasoning arrives.
    static var showsThinkingControls: Bool {
        isActive && mode == "thinking"
    }

    static func makeAppState() -> AppState {
        UITestFixtures.makeFixtureAppState(
            apiClient: StubClient(),
            label: "turn-stability"
        )
    }

    static func apply(to state: AppState) {
        state.isConnected = true
        state.selectedTab = RootTab.chat.rawValue
        state.sessions = [session(id: sessionID, title: "W09 Turn")]
        state.currentSessionID = sessionID
        switch mode {
        case "metadata":
            applyMetadata(to: state, laterHasModel: true)
        case "nomodel":
            applyMetadata(to: state, laterHasModel: false)
        case "thinking":
            applyThinking(to: state)
        default:
            applyAppend(to: state)
        }
    }

    /// Starts the turn: the assistant message exists but has produced
    /// nothing yet, so the thinking pill is the only signal.
    static func startThinking(to state: AppState) {
        state.messages = [
            MessageWithParts(
                info: user(id: "u1", text: "Why is the build slow?"),
                parts: [textPart(id: "u-text", messageID: "u1", text: "Why is the build slow?")]
            ),
            MessageWithParts(
                info: runningAssistant(id: firstID),
                parts: []
            ),
        ]
    }

    /// The reasoning arrives: the pill turns into the thinking card in place.
    static func fillReasoning(to state: AppState) {
        guard let index = state.messages.firstIndex(where: { $0.info.id == firstID }) else { return }
        var messages = state.messages
        messages[index].parts = [reasoningPart(id: "r1", messageID: firstID, text: "W09_THINK_WORDS")]
        state.messages = messages
    }

    /// The turn ends: the pill must be gone.
    static func completeThinking(to state: AppState) {
        guard let index = state.messages.firstIndex(where: { $0.info.id == firstID }) else { return }
        var messages = state.messages
        messages[index].info = completedAssistant(id: firstID)
        state.messages = messages
    }

    static func appendPart(to state: AppState) {
        guard let index = state.messages.firstIndex(where: { $0.info.id == firstID }) else { return }
        var messages = state.messages
        messages[index].parts.append(toolPart(id: "p2", messageID: firstID, title: "W09_TOOL_P2"))
        state.messages = messages
    }

    static func appendStep(to state: AppState) {
        var messages = state.messages
        messages.append(
            MessageWithParts(
                info: assistant(id: secondID, modelID: nil, error: nil, speech: nil, outputTokens: nil),
                parts: [toolPart(id: "p3", messageID: secondID, title: "W09_TOOL_M2")]
            )
        )
        state.messages = messages
    }

    nonisolated static func forkMarker(messageID: String) -> String {
        "W09_FORK_\(messageID)"
    }

    private static func applyThinking(to state: AppState) {
        startThinking(to: state)
    }

    private static func applyAppend(to state: AppState) {
        let thinking = UITestFixtures.decodePart([
            "id": "r1",
            "messageID": firstID,
            "sessionID": sessionID,
            "type": "reasoning",
            "text": "W09_THINK_OLD",
        ])
        state.messages = [
            MessageWithParts(
                info: assistant(id: firstID, modelID: nil, error: nil, speech: nil, outputTokens: nil),
                parts: [thinking, toolPart(id: "p1", messageID: firstID, title: "W09_TOOL_P1")]
            )
        ]
    }

    private static func applyMetadata(to state: AppState, laterHasModel: Bool) {
        let firstSpeech = laterHasModel ? "W09_SPEECH_M1" : nil
        let first = MessageWithParts(
            info: assistant(
                id: firstID,
                modelID: "step-one",
                error: "W09_ERR_M1",
                speech: firstSpeech,
                outputTokens: laterHasModel ? 99 : nil
            ),
            parts: [toolPart(id: "p1", messageID: firstID, title: "W09_TOOL_P1")]
        )
        let second = MessageWithParts(
            info: assistant(
                id: secondID,
                modelID: laterHasModel ? "step-two" : nil,
                error: "W09_ERR_M2",
                speech: "W09_SPEECH_M2",
                outputTokens: laterHasModel ? 42 : nil
            ),
            parts: []
        )
        state.messages = [first, second]
        let start = Date(timeIntervalSince1970: 0)
        state.stepTimings = [
            firstID: MessageStore.StepTiming(
                sessionID: sessionID,
                firstVisibleAt: start,
                lastVisibleAt: start.addingTimeInterval(2),
                outputTokens: 40
            ),
            secondID: MessageStore.StepTiming(
                sessionID: sessionID,
                firstVisibleAt: start,
                lastVisibleAt: start.addingTimeInterval(10),
                outputTokens: 50
            ),
        ]
    }

    private static func session(id: String, title: String) -> Session {
        Session(
            id: id,
            slug: id,
            projectID: "p1",
            directory: "/tmp/w09-turn",
            parentID: nil,
            title: title,
            version: "1",
            time: .init(created: 1, updated: 2, archived: nil),
            share: nil,
            summary: nil
        )
    }

    private static func assistant(
        id: String,
        modelID: String?,
        error: String?,
        speech: String?,
        outputTokens: Int?
    ) -> Message {
        let tokens = outputTokens.map { count in
            try! JSONDecoder().decode(
                Message.TokenInfo.self,
                from: Data("{\"input\":0,\"output\":\(count),\"reasoning\":0,\"total\":\(count)}".utf8)
            )
        }
        let model = modelID.map { Message.ModelInfo(providerID: "w09", modelID: $0) }
        let messageError = error.map { Message.MessageError(name: "Error", data: ["message": AnyCodable($0)]) }
        if let speech {
            return try! Message(
                id: id,
                sessionID: sessionID,
                role: "assistant",
                parentID: nil,
                providerID: nil,
                modelID: nil,
                model: model,
                error: messageError,
                time: .init(created: 0, completed: 1_000),
                finish: nil,
                tokens: tokens,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: speech,
                    confirmation: nil,
                    clientActions: []
                )
            )
        }
        return Message(
            id: id,
            sessionID: sessionID,
            role: "assistant",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: model,
            error: messageError,
            time: .init(created: 0, completed: 1_000),
            finish: nil,
            tokens: tokens,
            cost: nil
        )
    }

    private static func toolPart(id: String, messageID: String, title: String) -> Part {
        UITestFixtures.decodePart([
            "id": id,
            "messageID": messageID,
            "sessionID": sessionID,
            "type": "tool",
            "tool": "bash",
            "callID": "call-\(id)",
            "state": [
                "status": "completed",
                "title": title,
                "input": ["command": title],
                "output": title,
            ],
        ])
    }

    private static func reasoningPart(id: String, messageID: String, text: String) -> Part {
        UITestFixtures.decodePart([
            "id": id,
            "messageID": messageID,
            "sessionID": sessionID,
            "type": "reasoning",
            "text": text,
        ])
    }

    private static func textPart(id: String, messageID: String, text: String) -> Part {
        UITestFixtures.decodePart([
            "id": id,
            "messageID": messageID,
            "sessionID": sessionID,
            "type": "text",
            "text": text,
        ])
    }

    private static func user(id: String, text: String) -> Message {
        Message(
            id: id,
            sessionID: sessionID,
            role: "user",
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: nil,
            error: nil,
            time: .init(created: 0, completed: 1),
            finish: nil,
            tokens: nil,
            cost: nil
        )
    }

    /// An assistant message whose turn is still running: `completed` is nil.
    private static func runningAssistant(id: String) -> Message {
        Message(
            id: id,
            sessionID: sessionID,
            role: "assistant",
            parentID: "u1",
            providerID: "w09",
            modelID: "step",
            model: nil,
            error: nil,
            time: .init(created: 1, completed: nil),
            finish: nil,
            tokens: nil,
            cost: nil
        )
    }

    private static func completedAssistant(id: String) -> Message {
        Message(
            id: id,
            sessionID: sessionID,
            role: "assistant",
            parentID: "u1",
            providerID: "w09",
            modelID: "step",
            model: nil,
            error: nil,
            time: .init(created: 1, completed: 2),
            finish: nil,
            tokens: nil,
            cost: nil
        )
    }

    actor StubClient: APIClientProtocol {
        func configure(baseURL: String, username: String?, password: String?) {}
        func health() async throws -> HealthResponse {
            HealthResponse(healthy: true, version: "fixture")
        }
        func currentGeneration() -> ServerGeneration { .auto }
        func projects() async throws -> [Project] { [] }
        func projectCurrent() async throws -> Project? { nil }
        func sessions(directory: String?, limit: Int) async throws -> [Session] { [] }
        func session(sessionID: String) async throws -> Session {
            throw APIError.httpError(statusCode: 404, data: Data())
        }
        func createSession(title: String?, directory: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func updateSession(sessionID: String, title: String) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
        func deleteSession(sessionID: String) async throws {}
        func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
            guard sessionID.hasPrefix("forked-") else { return [] }
            let messageID = String(sessionID.dropFirst("forked-".count))
            let marker = TurnStabilityFixture.forkMarker(messageID: messageID)
            let info = Message(
                id: "fork-text",
                sessionID: sessionID,
                role: "assistant",
                parentID: nil,
                providerID: nil,
                modelID: nil,
                model: nil,
                error: nil,
                time: .init(created: 1, completed: 2),
                finish: nil,
                tokens: nil,
                cost: nil
            )
            let part = UITestFixtures.decodePart([
                "id": "fork-part",
                "messageID": info.id,
                "sessionID": sessionID,
                "type": "text",
                "text": marker,
            ])
            return [MessageWithParts(info: info, parts: [part])]
        }
        func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {}
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
            let id = messageID ?? "nil"
            return Session(
                id: "forked-\(id)",
                slug: "forked-\(id)",
                projectID: "p1",
                directory: "/tmp/w09-turn",
                parentID: sessionID,
                title: TurnStabilityFixture.forkMarker(messageID: id),
                version: "1",
                time: .init(created: 3, updated: 4, archived: nil),
                share: nil,
                summary: nil
            )
        }
        func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
            throw APIError.httpError(statusCode: 501, data: Data())
        }
    }
}

struct TurnStabilityAppendControls: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Button("W09_APPEND_PART") {
                TurnStabilityFixture.appendPart(to: state)
            }
            .accessibilityIdentifier("w09-turn-append-part")
            Button("W09_APPEND_STEP") {
                TurnStabilityFixture.appendStep(to: state)
            }
            .accessibilityIdentifier("w09-turn-append-step")
        }
        .font(.caption2)
        .buttonStyle(.bordered)
    }
}

/// Drives the thinking fixture: the turn starts, the reasoning arrives, the
/// turn ends. The transcript has to show the pill at every step.
struct TurnStabilityThinkingControls: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Button("W09_FILL_REASONING") {
                TurnStabilityFixture.fillReasoning(to: state)
            }
            .accessibilityIdentifier("w09-turn-fill-reasoning")
            Button("W09_COMPLETE_TURN") {
                TurnStabilityFixture.completeThinking(to: state)
            }
            .accessibilityIdentifier("w09-turn-complete")
        }
        .font(DesignTypography.micro)
        .buttonStyle(.bordered)
    }
}
