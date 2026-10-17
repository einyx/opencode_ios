import Foundation

nonisolated enum CarLiveProtocol {
    static let fixedVoiceModel = "gpt-live-1"
    static let fixedBackendModel = "gpt-6-luna"
    static let defaultVoice = "marin"
    static let sessionsPath = "/v1/audio/live/sessions"
    static let startedDeadline: TimeInterval = 20
    static let closeGrace: TimeInterval = 15
    static let maxAppendBytes = 2000
    static let maxFunctionOutputBytes = 64 * 1024
    static let maxAudioBytes = 480_000
    static let maxHistoryMessages = 128
    static let maxHistoryBytes = 8192

    static let frontendInstructions = "你是 OpenCode 的 Ambient Mode 语音入口。OpenCode 是运行 agent 的 harness。你可以查询、查看会话历史、开始、继续、停止、归档或取消归档 OpenCode 会话，也可以回答确认。这些能力可用。不要向用户朗读会话编号或目录路径。归档和取消归档只改状态并同步子代理，不停止正在执行的任务。语气短。先简短表示在听。用户打断时停下听。查询已有会话、查看历史、开始新工作、继续、停止、归档、取消归档、回答确认都交给已声明的函数。不要说已经完成，除非函数结果已经回来。不要把 OpenCode 会话说成 Process Launcher。"
    static var instructions: String { frontendInstructions }
    static var tools: [[String: Any]] { CarLiveToolSchema.tools() }

    static let backendInstructions = "你是 OpenCode 语音工作台的后端。OpenCode 是运行 agent 的 harness。job、session、会话指已有 OpenCode 会话，不是 Process Launcher 或 background process manager。管理查询和开始新工作是两件事：问已有会话、正在做哪些、最近 jobs，只调用 query_jobs，queryScope 用 recent；提到模型名也不要因此 start_job。recent 默认只列已归档根会话。archivedOnly 为 false 时包括归档和未归档根会话，不是只看未归档。不要筛子会话。下一页用结果里的 nextSkip 和相同 count。records 和 sessions 都含真实 id 和 directory。看这个会话最近对话、用户刚说了什么、AI怎么回复、或要历史记录时，调用 get_session_messages。不要为此 start_job 或 continue_job，也不要用 query_jobs 的最后一条摘要代替双方原文。get_session_messages 的 sessionID 为空表示当前跟踪会话。指定其他会话必须使用 query_jobs 返回的真实 id，先核对存在，未知 id 不要改查当前会话，也不要新建会话。skip 默认 0，表示从最近消息往前偏移；下一页用结果里的 nextSkip 和相同 count。count 默认 10。结果含用户和助手消息，按时间正序，时间戳来自服务端。口头只做摘要，不要逐条念时间戳或编号，原文留在函数结果里。继续时 continue_job 必须使用其中的精确 id，不要编造，也不要在不确定时新建任务。continue_job 的 text 就是直接送给目标 agent 的下一条 user message，原样送达。用户给出引号内正文时只提取引号内原文。不要加「请追加」「请在这个对话中追加以下内容」「作为本次prompt下的input」「转交以下内容」这类元包装，也不要替用户增加请求。用户任务里的真实研究指令保留原意，不要改写成转交说明。例子：追加：你好 => text 为 你好。continue_job 没有模型参数。即使用户说用 GPT、Sol、SoA 或 DeepSeek 追加，也不要改模型，沿用目标会话已有模型，并口头说明继续不能指定模型。只有用户明确要研究、写代码或执行新工作时才 start_job。停止用 stop_job，回答确认用 answer_pending。归档用 archive_job，取消归档用 unarchive_job。两者 sessionID 必填，必须是已核对的真实非空 id，不能省略，不能默认当前会话，不能编造。未知 id 不要改查当前会话，也不要 start_job。它们同步该会话和全部子代理，不只改根会话。归档先子后根，同一正毫秒时间戳。取消归档先根后子，客户端写 0，不能写 null。根已是目标状态也不能跳过仍要处理的子节点。这是发现时的子树快照，不是持续锁定。只改归档标记，不 abort、不 delete、不 prompt。正在执行的任务不要因此 stop_job。口头不要念会话编号。没有全部确认就不要说已经全部完成。别说了或只是让语音停下时不要调用函数。不要说已经完成，除非函数结果已经回来。不要自拟标题，标题由 OpenCode 自动生成。执行模型只有两个，且只在 start_job 里选择。start_job 的 requestedModel 只能是 ollama-cloud/deepseek-v4.1-flash、openai/gpt-6.1-sol 或 null。未指定或 null 表示常规研究，客户端默认 DeepSeek V4.1 Flash（ollama-cloud/deepseek-v4.1-flash）。复杂多步、难推理或要求高可靠时填 openai/gpt-6.1-sol（GPT-6.1 Sol）。口述 SoA 指 Sol。不要填写第三种模型。本阶段只有这八个手机执行的函数，不要调用 web_search、shell、code interpreter 或其他托管工具。不要在参数里写密钥、主机或账号。不要让语音朗读会话编号或目录。"

    static let defaultToolsJSON = CarLiveToolSchema.jsonData()
}

nonisolated enum CarLiveHostedFunction {
    static let queryJobs = "query_jobs"
    static let getSessionMessages = "get_session_messages"
    static let startJob = "start_job"
    static let continueJob = "continue_job"
    static let stopJob = "stop_job"
    static let answerPending = "answer_pending"
    static let archiveJob = "archive_job"
    static let unarchiveJob = "unarchive_job"
    static let names = [queryJobs, getSessionMessages, startJob, continueJob, stopJob, answerPending, archiveJob, unarchiveJob]
}

nonisolated enum CarLiveToolDefaults {
    static let archivedOnly = true
    static let skip = 0
    static let count = 10
    static let deepseek = "ollama-cloud/deepseek-v4.1-flash"
    static let sol = "openai/gpt-6.1-sol"
    static let schemaRefs = [deepseek, sol]
}

nonisolated enum CarLiveShutdown {
    static let abortsOpenCode = false
}

nonisolated enum CarLiveToolSchema {
    static func jsonData() -> Data {
        let object = tools()
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("[]".utf8)
    }

    static func tools() -> [[String: Any]] {
        [
            function(
                name: CarLiveHostedFunction.queryJobs,
                description: "只读查询已有 OpenCode 根会话，不返回子会话。recent 默认 archivedOnly 为 true，只含已归档根会话；false 包括归档和未归档，不是只看未归档。skip 默认 0，count 默认 10。翻页用 nextSkip 和相同 count。specified 与 current 忽略这三个字段。不要新建任务。",
                properties: [
                    "queryScope": ["type": "string", "enum": ["recent", "current", "specified"]],
                    "sessionID": nullableString,
                    "text": ["type": "string"],
                    "archivedOnly": ["type": "boolean", "description": "省略时客户端填 true。true 只返回已归档根会话。false 返回归档和未归档根会话，不是只看未归档。"],
                    "skip": ["type": "integer", "description": "省略时客户端填 0。必须大于等于 0。"],
                    "count": ["type": "integer", "description": "省略时客户端填 10。必须是 1 到 50。不要改用子会话补页。"]
                ],
                required: ["queryScope", "sessionID", "text", "archivedOnly", "skip", "count"]
            ),
            function(
                name: CarLiveHostedFunction.getSessionMessages,
                description: "只读查看一个已有 OpenCode 会话的双方对话原文。sessionID 为空表示当前跟踪会话。未知编号不要改查当前会话。skip 从最近消息往前偏移，默认 0。count 默认 10，范围 1 到 50。结果按时间正序，含角色和时间戳。口头只摘要。",
                properties: [
                    "sessionID": nullableString,
                    "skip": ["type": "integer"],
                    "count": ["type": "integer"]
                ],
                required: ["sessionID", "skip", "count"]
            ),
            function(
                name: CarLiveHostedFunction.startJob,
                description: "开始新的研究或编码。text 是完整目标。requestedModel 只能是 ollama-cloud/deepseek-v4.1-flash、openai/gpt-6.1-sol 或 null。null 表示常规任务，客户端默认 DeepSeek。复杂多步用 Sol。不要自拟标题。",
                properties: [
                    "text": ["type": "string"],
                    "requestedModel": ["anyOf": [
                        ["type": "string", "enum": CarLiveToolDefaults.schemaRefs],
                        ["type": "null"]
                    ]]
                ],
                required: ["text", "requestedModel"]
            ),
            function(
                name: CarLiveHostedFunction.continueJob,
                description: "继续已有 OpenCode 会话。text 原样送达目标 agent。没有会话编号就传 null。不能指定模型，沿用目标会话已有设置。",
                properties: [
                    "text": ["type": "string"],
                    "sessionID": nullableString
                ],
                required: ["text", "sessionID"]
            ),
            function(
                name: CarLiveHostedFunction.stopJob,
                description: "停止已跟踪的 OpenCode 任务。只是让语音停下时不要调用。",
                properties: [
                    "sessionID": nullableString,
                    "text": ["type": "string"]
                ],
                required: ["sessionID", "text"]
            ),
            function(
                name: CarLiveHostedFunction.answerPending,
                description: "回答待确认的提问或权限。permissionReply 只能是 once、reject 或 null。",
                properties: [
                    "answers": ["type": "array", "items": ["type": "array", "items": ["type": "string"]]],
                    "permissionReply": ["anyOf": [
                        ["type": "string", "enum": ["once", "reject"]],
                        ["type": "null"]
                    ]],
                    "text": ["type": "string"]
                ],
                required: ["answers", "permissionReply", "text"]
            ),
            function(
                name: CarLiveHostedFunction.archiveJob,
                description: "归档一个已有 OpenCode 会话及其全部子代理。sessionID 必填，必须是真实非空编号。不要省略，不要默认当前会话，不要编造。未知编号不要改查别的会话，也不要新建。先处理子代理再处理根，只改归档状态，不停止、不删除、不追加。正在执行的任务不要因此调用 stop_job。这是发现时的快照。口头不要念编号。",
                properties: ["sessionID": ["type": "string"]],
                required: ["sessionID"]
            ),
            function(
                name: CarLiveHostedFunction.unarchiveJob,
                description: "取消一个已有 OpenCode 会话及其全部子代理的归档。sessionID 必填，必须是真实非空编号。不要省略，不要默认当前会话，不要编造。未知编号不要改查别的会话，也不要新建。先处理根再处理子代理。客户端把 archived 写成 0，不要传 null，也不要另传 text 或 model。只改状态，不停止、不删除、不新建、不追加。口头不要念编号。",
                properties: ["sessionID": ["type": "string"]],
                required: ["sessionID"]
            )
        ]
    }

    private static var nullableString: [String: Any] {
        ["type": ["string", "null"]]
    }

    private static func function(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "strict": true,
            "parameters": [
                "type": "object",
                "additionalProperties": false,
                "properties": properties,
                "required": required
            ]
        ]
    }
}

nonisolated enum CarLiveEndpoint {
    static func sessionURL(base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false), components.host != nil else { return nil }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        components.path = path + CarLiveProtocol.sessionsPath
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    static func resolveWebSocket(portalBase: URL, wsURL: String) -> URL? {
        let raw = wsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("\\"), raw.contains("@") == false else { return nil }
        if raw.hasPrefix("wss://") || raw.hasPrefix("ws://") || raw.hasPrefix("https://") || raw.hasPrefix("http://") {
            return absoluteWebSocket(portalBase: portalBase, raw: raw)
        }
        guard raw.hasPrefix("/"), var components = URLComponents(string: raw), queryIsTicketOnly(components) else { return nil }
        guard let base = URLComponents(url: portalBase, resolvingAgainstBaseURL: false), let host = base.host, let scheme = base.scheme else { return nil }
        components.scheme = scheme
        components.host = host
        components.port = base.port
        components.user = nil
        components.password = nil
        return websocketScheme(components.url)
    }

    private static func absoluteWebSocket(portalBase: URL, raw: String) -> URL? {
        guard var components = URLComponents(string: raw), queryIsTicketOnly(components) else { return nil }
        guard let base = URLComponents(url: portalBase, resolvingAgainstBaseURL: false),
              let portalScheme = base.scheme,
              let socketScheme = components.scheme,
              allowsSocketScheme(portalScheme: portalScheme, socketScheme: socketScheme),
              sameOrigin(base, components) else { return nil }
        components.scheme = secure(socketScheme) ? "wss" : "ws"
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func websocketScheme(_ url: URL?) -> URL? {
        guard var components = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        switch components.scheme?.lowercased() {
        case "https", "wss":
            components.scheme = "wss"
        case "http", "ws":
            components.scheme = "ws"
        default:
            return nil
        }
        return components.url
    }

    static func queryIsTicketOnly(_ components: URLComponents) -> Bool {
        if components.fragment != nil || components.user != nil || components.password != nil { return false }
        let items = components.queryItems ?? []
        guard items.count == 1, items[0].name == "ticket" else { return false }
        let value = items[0].value ?? ""
        return !value.isEmpty
    }

    static func ticketMatches(url: URL, ticket: String) -> Bool {
        guard !ticket.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              queryIsTicketOnly(components),
              let value = components.queryItems?.first?.value else { return false }
        return value == ticket
    }

    private static func allowsSocketScheme(portalScheme: String, socketScheme: String) -> Bool {
        if secure(portalScheme) { return secure(socketScheme) }
        switch portalScheme.lowercased() {
        case "http", "ws":
            return socketScheme.lowercased() == "http" || socketScheme.lowercased() == "ws"
        default:
            return false
        }
    }

    private static func sameOrigin(_ portal: URLComponents, _ socket: URLComponents) -> Bool {
        guard let portalHost = portal.host, let socketHost = socket.host,
              portalHost.caseInsensitiveCompare(socketHost) == .orderedSame,
              let portalPort = originPort(portal),
              let socketPort = originPort(socket) else { return false }
        return portalPort == socketPort
    }

    private static func originPort(_ components: URLComponents) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https", "wss":
            return 443
        case "http", "ws":
            return 80
        default:
            return nil
        }
    }

    private static func secure(_ scheme: String) -> Bool {
        let lowered = scheme.lowercased()
        return lowered == "https" || lowered == "wss"
    }
}

nonisolated struct CarLiveTicket: Equatable, Sendable {
    var portalSessionID: String
    var ticket: String
    var wsURL: String
    var expiry: String
}

nonisolated enum CarLiveTicketParser {
    static func parse(_ data: Data) -> CarLiveTicket? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let portal = string(object["portal_session_id"]),
              let ticket = string(object["ticket"]),
              let wsURL = string(object["ws_url"]),
              let expiry = string(object["expiry"]) else { return nil }
        return CarLiveTicket(portalSessionID: portal, ticket: ticket, wsURL: wsURL, expiry: expiry)
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

nonisolated enum CarLiveCreateBody {
    static func data(for configuration: CarLiveConfiguration) throws -> Data {
        let history = try historyPayload(configuration.history)
        let tools = try toolsPayload(configuration.toolsJSON)
        let object: [String: Any] = [
            "frontend_instructions": configuration.instructions,
            "backend_instructions": configuration.backendInstructions,
            "history": history,
            "voice": configuration.voice,
            "tools": tools
        ]
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw CarLiveTransportError.badResponse
        }
        return data
    }

    static func historyPayload(_ turns: [CarLiveHistoryTurn]) throws -> [[String: Any]] {
        guard turns.count <= CarLiveProtocol.maxHistoryMessages else { throw CarLiveTransportError.rejected }
        var bytes = 0
        var rows: [[String: Any]] = []
        for turn in turns {
            let role = turn.role == "assistant" ? "assistant" : (turn.role == "developer" ? "developer" : "user")
            let part = role == "assistant" ? "output_text" : "input_text"
            if !rows.isEmpty { bytes += 1 }
            bytes += turn.text.utf8.count
            rows.append([
                "type": "message",
                "role": role,
                "content": [["type": part, "text": turn.text]]
            ])
        }
        if bytes > CarLiveProtocol.maxHistoryBytes { throw CarLiveTransportError.rejected }
        return rows
    }

    static func toolsPayload(_ data: Data) throws -> [Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [Any] else { throw CarLiveTransportError.rejected }
        return object
    }

    static func accepts(status: Int) -> Bool {
        status == 200 || status == 201
    }
}

nonisolated enum CarLiveClientEvent: Equatable, Sendable {
    case audio(Data)
    case close
    case mute
    case unmute
    case commentary(String)
    case thinking(String)
    case functionOutput(callID: String, output: String)
    case continueResponse
}

nonisolated enum CarLiveWire {
    static let allowed: Set<String> = [
        "session.input_audio.append",
        "session.close",
        "session.input_audio.mute",
        "session.input_audio.unmute",
        "session.commentary.append",
        "session.thinking.append",
        "session.instructions.append",
        "response.item.create",
        "response.create"
    ]

    static func encode(_ event: CarLiveClientEvent, eventID: String = CarLiveWire.eventID()) -> String? {
        let object: [String: Any]
        switch event {
        case .audio(let pcm):
            let even = pcm.count - pcm.count % 2
            guard even >= 2, even <= CarLiveProtocol.maxAudioBytes else { return nil }
            object = ["type": "session.input_audio.append", "event_id": eventID, "audio": Data(pcm.prefix(even)).base64EncodedString()]
        case .close:
            object = ["type": "session.close", "event_id": eventID]
        case .mute:
            object = ["type": "session.input_audio.mute", "event_id": eventID]
        case .unmute:
            object = ["type": "session.input_audio.unmute", "event_id": eventID]
        case .commentary(let text):
            guard let clipped = clip(text) else { return nil }
            object = ["type": "session.commentary.append", "event_id": eventID, "delegation_id": NSNull(), "content": clipped]
        case .thinking(let text):
            guard let clipped = clip(text) else { return nil }
            object = ["type": "session.thinking.append", "event_id": eventID, "delegation_id": NSNull(), "content": clipped]
        case .functionOutput(let callID, let output):
            guard !callID.isEmpty, output.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes else { return nil }
            object = [
                "type": "response.item.create",
                "event_id": eventID,
                "item": ["type": "function_call_output", "call_id": callID, "output": output]
            ]
        case .continueResponse:
            object = ["type": "response.create", "event_id": eventID]
        }
        guard let type = object["type"] as? String, allowed.contains(type), forbidden(type) == false else { return nil }
        return json(object)
    }

    static func forbidden(_ type: String) -> Bool {
        type == "session.start" || type == "session.update"
    }

    static func eventType(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["type"] as? String
    }

    static func clip(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var bytes = Data()
        for scalar in trimmed.unicodeScalars {
            let next = Data(String(scalar).utf8)
            if bytes.count + next.count > CarLiveProtocol.maxAppendBytes { break }
            bytes.append(next)
        }
        guard !bytes.isEmpty, let clipped = String(data: bytes, encoding: .utf8), !clipped.isEmpty else { return nil }
        return clipped
    }

    static func eventID() -> String {
        "evt_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func json(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func errorOutput(code: String, message: String) -> String {
        let object: [String: Any] = ["ok": false, "error": code, "message": message]
        return json(object) ?? "{\"ok\":false,\"error\":\"encode\",\"message\":\"结果没有送出\"}"
    }
}

nonisolated struct CarLiveTranscriptFragment: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByExtendedGraphemeClusterLiteral, ExpressibleByUnicodeScalarLiteral {
    var text: String
    var eventID: String
    var utteranceID: String?
    var startMS: Int?
    var endMS: Int?

    init(text: String, eventID: String = "", utteranceID: String? = nil, startMS: Int? = nil, endMS: Int? = nil) {
        self.text = text
        self.eventID = eventID
        self.utteranceID = utteranceID
        self.startMS = startMS
        self.endMS = endMS
    }

    init(stringLiteral value: String) {
        self.init(text: value)
    }

    init(extendedGraphemeClusterLiteral value: Character) {
        self.init(text: String(value))
    }

    init(unicodeScalarLiteral value: Unicode.Scalar) {
        self.init(text: String(value))
    }
}

nonisolated enum CarLiveServerEvent: Equatable, Sendable {
    case started(sessionID: String)
    case outputAudio(Data)
    case inputTranscript(CarLiveTranscriptFragment)
    case outputTranscript(CarLiveTranscriptFragment)
    case hosted(CarLiveHostedInbound)
    case voiceUsage(Double)
    case closed(Double?)
    case portalUsage(requestID: String, estimatedUSD: Double, confirmed: Bool, status: String)
    case usageUnconfirmed
    case failed(String)
    case ignored(String)
}

nonisolated enum CarLiveHostedInbound: Equatable, Sendable {
    case functionCall(callID: String, name: String, arguments: String)
    case lifecycle(CarLiveLifecycle)
    case ignored(String)
}

nonisolated struct CarLiveLifecycle: Equatable, Sendable {
    var type: String
    var responseID: String
    var model: String
    var outputCount: Int
    var usage: CarLiveParsedUsage?
}

nonisolated struct CarLiveParsedUsage: Equatable, Sendable {
    var inputTokens: Int
    var cachedRead: Int
    var cacheWrite: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var model: String
    var responseID: String
    var serviceTier: String
    var fieldsLegal: Bool
}

nonisolated enum CarLiveEventDecoder {
    static func decode(_ text: String) -> CarLiveServerEvent {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored("bad")
        }
        let type = json["type"] as? String ?? ""
        switch type {
        case "usage":
            guard let cost = finite(json["estimated_cost_usd"]) else { return .usageUnconfirmed }
            guard let requestID = json["request_id"] as? String, !requestID.isEmpty else { return .usageUnconfirmed }
            let confirmed = json["confirmed"] as? Bool == true
            return .portalUsage(requestID: requestID, estimatedUSD: cost, confirmed: confirmed, status: portalStatus(json["status"], confirmed: confirmed))
        case "error", "session.error":
            let code = errorCode(json)
            if code == "usage_unconfirmed" { return .usageUnconfirmed }
            return .failed(code)
        case "session.started":
            let session = json["session"] as? [String: Any]
            let id = (json["session_id"] as? String) ?? (session?["id"] as? String) ?? ""
            return .started(sessionID: id)
        case "session.output_audio.delta":
            return .outputAudio(pcm(json))
        case "session.input_transcript.delta":
            return .inputTranscript(fragment(json))
        case "session.output_transcript.delta":
            return .outputTranscript(fragment(json))
        case "response.event":
            return .hosted(hosted(json))
        case "session.usage.updated":
            guard let seconds = seconds(json) else { return .ignored(type) }
            return .voiceUsage(seconds)
        case "session.closed":
            return .closed(optionalSeconds(json))
        default:
            return .ignored(type)
        }
    }

    static func errorCode(_ json: [String: Any]) -> String {
        if let code = json["code"] as? String, !code.isEmpty { return code }
        if let nested = json["error"] as? [String: Any], let code = nested["code"] as? String, !code.isEmpty { return code }
        return "error"
    }

    static func portalStatus(_ value: Any?, confirmed: Bool) -> String {
        if let status = value as? String, ["confirmed", "provisional", "anomaly"].contains(status) {
            return confirmed ? "confirmed" : status
        }
        return confirmed ? "confirmed" : "provisional"
    }

    static func hosted(_ envelope: [String: Any]) -> CarLiveHostedInbound {
        guard let inner = envelope["event"] as? [String: Any] else { return .ignored("missing_event") }
        let type = inner["type"] as? String ?? ""
        switch type {
        case "response.output_item.done":
            guard let call = functionCall(inner) else { return .ignored(type) }
            return .functionCall(callID: call.0, name: call.1, arguments: call.2)
        case "response.completed", "response.failed", "response.incomplete":
            return .lifecycle(lifecycle(type: type, inner: inner))
        default:
            return .ignored(type)
        }
    }

    private static func functionCall(_ inner: [String: Any]) -> (String, String, String)? {
        let item = inner["item"] as? [String: Any] ?? inner
        guard (item["type"] as? String) == "function_call" else { return nil }
        let callID = item["call_id"] as? String ?? ""
        let name = item["name"] as? String ?? ""
        guard !callID.isEmpty, !name.isEmpty else { return nil }
        return (callID, name, argumentsText(item["arguments"]))
    }

    private static func argumentsText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let value, JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return ""
    }

    private static func lifecycle(type: String, inner: [String: Any]) -> CarLiveLifecycle {
        let response = inner["response"] as? [String: Any] ?? [:]
        let output = response["output"] as? [Any] ?? []
        let payload = response.isEmpty ? inner : response
        return CarLiveLifecycle(
            type: type,
            responseID: (response["id"] as? String) ?? (inner["response_id"] as? String) ?? "",
            model: (response["model"] as? String) ?? "",
            outputCount: output.count,
            usage: CarLiveUsageParser.parse(payload)
        )
    }

    private static func pcm(_ json: [String: Any]) -> Data {
        let raw = (json["delta"] as? String) ?? (json["audio"] as? String) ?? ""
        return Data(base64Encoded: raw) ?? Data()
    }

    private static func fragment(_ json: [String: Any]) -> CarLiveTranscriptFragment {
        let text = (json["delta"] as? String) ?? (json["text"] as? String) ?? ""
        let eventID = json["event_id"] as? String ?? ""
        return CarLiveTranscriptFragment(
            text: text,
            eventID: eventID,
            startMS: millis(json["start_ms"]),
            endMS: millis(json["end_ms"])
        )
    }

    private static func millis(_ value: Any?) -> Int? {
        if value is Bool { return nil }
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double <= Double(Int.max) else { return nil }
        return Int(double.rounded())
    }

    private static func seconds(_ json: [String: Any]) -> Double? {
        if let value = finite(json["seconds"]) { return value }
        if let usage = json["usage"] as? [String: Any] { return finite(usage["seconds"]) }
        return nil
    }

    private static func optionalSeconds(_ json: [String: Any]) -> Double? {
        if json["seconds"] == nil, (json["usage"] as? [String: Any])?["seconds"] == nil { return nil }
        return seconds(json)
    }

    private static func finite(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            guard double.isFinite, double >= 0 else { return nil }
            return double
        }
        return nil
    }
}

nonisolated enum CarLiveRates {
    static let modelID = "gpt-6-luna"
    static let longContextInput = 272_000
    static let input = 0.10
    static let cachedRead = 0.01
    static let cacheWrite = 0.125
    static let output = 0.50
    static let longInputMultiplier = 2.0
    static let longOutputMultiplier = 1.5
    static let standardTiers: Set<String> = ["default", "standard", "auto"]

    static func prices(_ model: String) -> Bool {
        let token = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token.isEmpty || token == modelID || token.hasPrefix(modelID + "-")
    }
}

nonisolated struct CarLiveQuote: Equatable, Sendable {
    var ordinaryInputTokens: Int
    var estimatedUSD: Double
}

nonisolated enum CarLiveQuoteMaker {
    static func make(_ usage: CarLiveParsedUsage) -> CarLiveQuote? {
        guard usage.fieldsLegal else { return nil }
        guard CarLiveRates.prices(usage.model) else { return nil }
        let tier = usage.serviceTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !tier.isEmpty && !CarLiveRates.standardTiers.contains(tier) { return nil }
        let ordinary = usage.inputTokens - usage.cachedRead - usage.cacheWrite
        guard ordinary >= 0 else { return nil }
        let long = usage.inputTokens > CarLiveRates.longContextInput
        let inputScale = long ? CarLiveRates.longInputMultiplier : 1
        let outputScale = long ? CarLiveRates.longOutputMultiplier : 1
        let usd = (
            Double(ordinary) * CarLiveRates.input * inputScale
                + Double(usage.cachedRead) * CarLiveRates.cachedRead * inputScale
                + Double(usage.cacheWrite) * CarLiveRates.cacheWrite * inputScale
                + Double(usage.outputTokens) * CarLiveRates.output * outputScale
        ) / 1_000_000
        return CarLiveQuote(ordinaryInputTokens: ordinary, estimatedUSD: usd)
    }
}

nonisolated enum CarLiveUsageParser {
    static func parse(_ object: [String: Any]) -> CarLiveParsedUsage? {
        guard let usage = object["usage"] as? [String: Any] else { return nil }
        let model = object["model"] as? String ?? ""
        let responseID = object["id"] as? String ?? ""
        let tier = object["service_tier"] as? String ?? ""
        let reasoning = reasoningCount(usage)
        guard let input = whole(usage["input_tokens"]), let output = whole(usage["output_tokens"]) else {
            return CarLiveParsedUsage(inputTokens: 0, cachedRead: 0, cacheWrite: 0, outputTokens: 0, reasoningTokens: reasoning, model: model, responseID: responseID, serviceTier: tier, fieldsLegal: false)
        }
        let read: Int?
        let write: Int?
        if usage["input_tokens_details"] == nil || usage["input_tokens_details"] is NSNull {
            read = 0
            write = 0
        } else if let details = usage["input_tokens_details"] as? [String: Any] {
            read = optionalCount(details, key: "cached_tokens")
            write = optionalCount(details, key: "cache_write_tokens")
        } else {
            read = nil
            write = nil
        }
        let legal = read != nil && write != nil && (read ?? 0) + (write ?? 0) <= input
        return CarLiveParsedUsage(
            inputTokens: input,
            cachedRead: read ?? 0,
            cacheWrite: write ?? 0,
            outputTokens: output,
            reasoningTokens: reasoning,
            model: model,
            responseID: responseID,
            serviceTier: tier,
            fieldsLegal: legal
        )
    }

    private static func reasoningCount(_ usage: [String: Any]) -> Int {
        guard let details = usage["output_tokens_details"] as? [String: Any] else { return 0 }
        return whole(details["reasoning_tokens"]) ?? 0
    }

    private static func optionalCount(_ object: [String: Any], key: String) -> Int? {
        guard object.keys.contains(key), !(object[key] is NSNull) else { return 0 }
        return whole(object[key])
    }

    private static func whole(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double <= Double(Int.max), double == double.rounded() else { return nil }
        return number.intValue
    }
}

nonisolated struct CarLiveUsageLedger: Equatable, Sendable {
    var usage = CarLiveBackendUsage()
    private var seen: Set<String> = []

    mutating func record(_ life: CarLiveLifecycle) -> Bool {
        let id = life.responseID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty {
            if seen.contains(id) { return false }
            seen.insert(id)
        }
        usage.responseCount += 1
        guard var parsed = life.usage else {
            usage.unpricedCount += 1
            return true
        }
        if parsed.responseID.isEmpty { parsed.responseID = id }
        if parsed.model.isEmpty { parsed.model = life.model }
        guard parsed.fieldsLegal, let quote = CarLiveQuoteMaker.make(parsed) else {
            usage.unpricedCount += 1
            return true
        }
        usage.inputTokens += quote.ordinaryInputTokens
        usage.cachedRead += parsed.cachedRead
        usage.cacheWrite += parsed.cacheWrite
        usage.outputTokens += parsed.outputTokens
        usage.estimatedUSD += quote.estimatedUSD
        return true
    }
}

nonisolated struct CarLivePortalEntry: Equatable, Sendable {
    var estimatedUSD: Double
    var confirmed: Bool
    var status: String
}

nonisolated struct CarLivePortalLedger: Equatable, Sendable {
    private var byRequest: [String: CarLivePortalEntry] = [:]

    mutating func replace(requestID: String, estimatedUSD: Double, confirmed: Bool, status: String) {
        guard !requestID.isEmpty, estimatedUSD.isFinite, estimatedUSD >= 0 else { return }
        let normalized = ["confirmed", "provisional", "anomaly"].contains(status) ? status : (confirmed ? "confirmed" : "provisional")
        byRequest[requestID] = CarLivePortalEntry(
            estimatedUSD: estimatedUSD,
            confirmed: confirmed && normalized == "confirmed",
            status: normalized
        )
    }

    var total: Double? {
        let rows = byRequest.values.filter { $0.status != "anomaly" }
        guard !rows.isEmpty else { return nil }
        return rows.map(\.estimatedUSD).reduce(0, +)
    }

    var settled: Bool {
        let rows = byRequest.values.filter { $0.status != "anomaly" }
        return !rows.isEmpty && rows.allSatisfy { $0.confirmed && $0.status == "confirmed" }
    }
}

nonisolated struct CarLiveVoiceNote: Equatable, Sendable {
    var seconds: Double = 0
    var hasSnapshot = false
    var unconfirmed = false

    mutating func replace(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        self.seconds = seconds
        hasSnapshot = true
    }

    mutating func close(_ seconds: Double?) {
        if let seconds, seconds.isFinite, seconds >= 0 {
            self.seconds = seconds
            hasSnapshot = true
            return
        }
        unconfirmed = true
    }
}

nonisolated struct CarLiveCallBook: Sendable {
    var generation: UInt64
    var accepting = true
    private(set) var pending: [(callID: String, name: String)] = []
    private var seen: Set<String> = []

    init(generation: UInt64) {
        self.generation = generation
    }

    mutating func bind(_ next: UInt64) {
        generation = next
        accepting = true
        pending.removeAll()
        seen.removeAll()
    }

    mutating func collect(callID: String, name: String) {
        guard !callID.isEmpty else { return }
        if pending.contains(where: { $0.callID == callID }) || seen.contains(callID) { return }
        pending.append((callID, name))
    }

    mutating func claim(callID: String, generation now: UInt64) -> CarLiveClaim {
        guard accepting, now == generation, !callID.isEmpty else { return .rejected }
        if seen.contains(callID) { return .duplicate }
        seen.insert(callID)
        pending.removeAll { $0.callID == callID }
        return .accepted
    }

    mutating func noteLifecycle(outputCount: Int) {
        _ = outputCount
    }

    var keptCalls: Int { pending.count }
}

nonisolated enum CarLiveClaim: Equatable, Sendable {
    case accepted
    case duplicate
    case rejected
}

nonisolated enum CarLiveCaptionWrite: Equatable, Sendable {
    case ignored
    case appended
    case opened
}

nonisolated struct CarLiveCaptionBook: Equatable, Sendable {
    static let speechGapThresholdMS = 2_000
    private(set) var captions: [CarLiveCaption] = []
    private(set) var clock = 0
    private var openIndex: [String: Int] = [:]

    mutating func reset(history: [CarLiveHistoryTurn]) {
        clock = 0
        openIndex.removeAll()
        var seeded: [CarLiveCaption] = []
        for turn in history {
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            clock += 1
            let role = turn.role.trimmingCharacters(in: .whitespacesAndNewlines)
            seeded.append(CarLiveCaption(
                id: "history-\(clock)",
                role: role.isEmpty ? "user" : role,
                text: turn.text,
                sequence: clock
            ))
        }
        captions = seeded
    }

    mutating func append(role: String, text: String, startMS: Int? = nil, endMS: Int? = nil) -> CarLiveCaptionWrite {
        guard !text.isEmpty else { return .ignored }
        if let index = openIndex[role], captions.indices.contains(index),
           splitsForSpeechGap(previousEnd: captions[index].endMS, nextStart: startMS) == false {
            captions[index].text += text
            captions[index].startMS = mergedStart(captions[index].startMS, startMS)
            captions[index].endMS = mergedEnd(captions[index].endMS, endMS)
            return .appended
        }
        clock += 1
        captions.append(CarLiveCaption(
            id: UUID().uuidString,
            role: role,
            text: text,
            sequence: clock,
            startMS: startMS,
            endMS: endMS
        ))
        openIndex[role] = captions.count - 1
        trim()
        return .opened
    }

    mutating func closeAll() {
        openIndex.removeAll()
    }

    private func splitsForSpeechGap(previousEnd: Int?, nextStart: Int?) -> Bool {
        guard let previousEnd, let nextStart else { return false }
        return nextStart - previousEnd > Self.speechGapThresholdMS
    }

    private func mergedStart(_ current: Int?, _ next: Int?) -> Int? {
        switch (current, next) {
        case let (current?, next?):
            return min(current, next)
        case let (current?, nil):
            return current
        case let (nil, next?):
            return next
        case (nil, nil):
            return nil
        }
    }

    private func mergedEnd(_ current: Int?, _ next: Int?) -> Int? {
        switch (current, next) {
        case let (current?, next?):
            return max(current, next)
        case let (current?, nil):
            return current
        case let (nil, next?):
            return next
        case (nil, nil):
            return nil
        }
    }

    mutating func advance() -> Int {
        clock += 1
        return clock
    }

    func openID(role: String) -> String? {
        guard let index = openIndex[role], captions.indices.contains(index) else { return nil }
        return captions[index].id
    }

    private mutating func trim() {
        guard captions.count > 200 else { return }
        let drop = captions.count - 200
        captions.removeFirst(drop)
        var nextOpen: [String: Int] = [:]
        for (role, index) in openIndex {
            let moved = index - drop
            guard moved >= 0 else { continue }
            nextOpen[role] = moved
        }
        openIndex = nextOpen
    }
}

nonisolated struct CarLiveBargeGate: Equatable, Sendable {
    var sustain: TimeInterval = 0.18
    var releaseAfter: TimeInterval = 0.45
    var threshold: Double = 0.08
    private(set) var holding = false
    private(set) var clears = 0
    private var hotSince: TimeInterval?
    private var quietSince: TimeInterval?

    enum Action: Equatable, Sendable {
        case none
        case begin
        case end
    }

    mutating func noteInput(level: Double, outputActive: Bool, now: TimeInterval) -> Action {
        if level >= threshold {
            quietSince = nil
            if holding { return .none }
            guard outputActive else {
                hotSince = nil
                return .none
            }
            if hotSince == nil { hotSince = now }
            let started = hotSince ?? now
            guard now - started >= sustain else { return .none }
            return begin(now: now, quietFromNow: false)
        }
        hotSince = nil
        guard holding else { return .none }
        if quietSince == nil { quietSince = now }
        let since = quietSince ?? now
        guard now - since >= releaseAfter else { return .none }
        holding = false
        quietSince = nil
        hotSince = nil
        return .end
    }

    mutating func beginManual(now: TimeInterval) -> Action {
        guard !holding else { return .none }
        return begin(now: now, quietFromNow: true)
    }

    mutating func stop() {
        holding = false
        hotSince = nil
        quietSince = nil
    }

    private mutating func begin(now: TimeInterval, quietFromNow: Bool) -> Action {
        holding = true
        clears += 1
        hotSince = nil
        quietSince = quietFromNow ? now : nil
        return .begin
    }
}

nonisolated struct CarLiveFlightBook: Equatable, Sendable {
    var inFlight = 0
    var blocked = false
    var continuations = 0

    mutating func begin() {
        inFlight += 1
    }

    mutating func finish(outputSent: Bool, accepting: Bool) -> Bool {
        if !outputSent { blocked = true }
        inFlight = max(0, inFlight - 1)
        guard outputSent, !blocked, inFlight == 0, accepting else { return false }
        continuations += 1
        return true
    }
}

nonisolated enum CarLivePCM {
    static let sampleRate = 24_000

    static func silence(byteCount: Int) -> Data {
        let even = byteCount - (byteCount % 2)
        return Data(count: max(0, even))
    }

    static func rms(_ pcm: Data) -> Double {
        guard pcm.count >= 2 else { return 0 }
        var sum = 0.0
        var count = 0
        pcm.withUnsafeBytes { raw in
            for sample in raw.bindMemory(to: Int16.self) {
                let value = Double(sample) / 32768
                sum += value * value
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        return min(1, (sum / Double(count)).squareRoot())
    }
}
