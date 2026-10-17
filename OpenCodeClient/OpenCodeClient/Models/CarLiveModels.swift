import Foundation

nonisolated enum CarLivePhase: String, Equatable, Sendable {
    case idle
    case connecting
    case listening
    case speaking
    case closing
    case failed
}

nonisolated struct CarLiveCaption: Identifiable, Equatable, Sendable {
    var id: String
    var role: String
    var text: String
    var sequence: Int = 0
    var startMS: Int? = nil
    var endMS: Int? = nil
}

nonisolated struct CarLiveActivity: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var arguments: String
    var status: String
    var result: String
    var sequence: Int = 0
}

nonisolated struct CarLiveBackendUsage: Equatable, Sendable {
    var inputTokens: Int = 0
    var cachedRead: Int = 0
    var cacheWrite: Int = 0
    var outputTokens: Int = 0
    var responseCount: Int = 0
    var estimatedUSD: Double = 0
    var unpricedCount: Int = 0

    static let estimateNote = "标准价估算，不是账单"
}

nonisolated struct CarLiveHistoryTurn: Equatable, Sendable {
    var role: String
    var text: String
}

nonisolated struct CarLiveConfiguration: Equatable, Sendable {
    var portalBaseURL: URL
    var builderToken: String
    var history: [CarLiveHistoryTurn]
    var instructions: String
    var backendInstructions: String
    var voice: String
    var toolsJSON: Data
    var ownerToken: String

    init(
        portalBaseURL: URL,
        builderToken: String,
        history: [CarLiveHistoryTurn]? = nil,
        instructions: String = CarLiveProtocol.instructions,
        backendInstructions: String = CarLiveProtocol.backendInstructions,
        voice: String = CarLiveProtocol.defaultVoice,
        tools: [[String: Any]]? = nil,
        toolsJSON: Data? = nil,
        ownerToken: String = ""
    ) {
        self.portalBaseURL = portalBaseURL
        self.builderToken = builderToken
        self.history = history ?? []
        self.instructions = instructions
        self.backendInstructions = backendInstructions
        self.voice = voice
        if let tools, JSONSerialization.isValidJSONObject(tools), let data = try? JSONSerialization.data(withJSONObject: tools) {
            self.toolsJSON = data
        } else {
            self.toolsJSON = toolsJSON ?? CarLiveProtocol.defaultToolsJSON
        }
        self.ownerToken = ownerToken
    }
}

nonisolated struct CarLiveFunctionCall: Equatable, Sendable {
    var callID: String
    var name: String
    var arguments: String
    var ownerToken: String
}

nonisolated struct CarLiveToolResult: Equatable, Sendable {
    var output: String
    var acceptedSessionID: String?

    init(output: String, acceptedSessionID: String? = nil) {
        self.output = output
        self.acceptedSessionID = acceptedSessionID
    }
}

nonisolated enum CarLiveCopy {
    static let missingToken = "需要 AI Builder token"
    static let unauthorized = "AI Builder 登录已失效"
    static let forbidden = "没有使用实时语音的权限"
    static let notReady = "语音会话没有就绪"
    static let microphone = "需要麦克风权限"
    static let microphoneUnavailable = "麦克风不可用"
    static let disconnected = "语音连接已断开"
    static let notConnected = "语音未连接"
    static let rejected = "语音会话被拒绝"
    static let noFallback = "不会改走直连或转写"
}
