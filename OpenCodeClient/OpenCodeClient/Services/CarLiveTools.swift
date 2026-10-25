import Foundation

enum CarLiveAPIUnsupported: Error, Equatable {
    case experimentalSessionPage
    case sessionLookup
    case history
    case children
    case createSession
    case prompt
    case abort
    case status
    case providerRegistry
    case pending
    case answer
    case archive
    case closed
}

enum CarLiveToolName {
    static let queryJobs = CarLiveHostedFunction.queryJobs
    static let getSessionMessages = CarLiveHostedFunction.getSessionMessages
    static let startJob = CarLiveHostedFunction.startJob
    static let continueJob = CarLiveHostedFunction.continueJob
    static let stopJob = CarLiveHostedFunction.stopJob
    static let answerPending = CarLiveHostedFunction.answerPending
    static let archiveJob = CarLiveHostedFunction.archiveJob
    static let unarchiveJob = CarLiveHostedFunction.unarchiveJob
    static let native = CarLiveHostedFunction.names
}

enum CarLiveModelError: Error, Equatable {
    case unknownModel

    var code: String {
        switch self {
        case .unknownModel: return "unknown_model"
        }
    }
}

struct CarLiveTransportLease: Equatable {
    var issued: UInt64 = 0
    var active: UInt64 = 0
}

enum CarLiveTransportGate {
    static func arm(_ lease: CarLiveTransportLease) -> (lease: CarLiveTransportLease, token: UInt64) {
        let next = lease.issued &+ 1
        guard next != 0, next != lease.active else { return (lease, 0) }
        var updated = lease
        updated.issued = next
        updated.active = next
        return (updated, next)
    }

    static func retire(_ lease: CarLiveTransportLease, token: UInt64) -> CarLiveTransportLease {
        guard lease.active == token else { return lease }
        var updated = lease
        updated.active = 0
        return updated
    }

    static func invalidate(_ lease: CarLiveTransportLease) -> CarLiveTransportLease {
        var updated = lease
        updated.active = 0
        return updated
    }

    static func allows(_ lease: CarLiveTransportLease, token: UInt64) -> Bool {
        token != 0 && lease.active == token
    }
}

enum CarLiveRunOwner {
    static func shouldClose(current: CarLiveLease?, owned: CarLiveLease) -> Bool {
        current == owned
    }
}

enum CarLiveModel {
    static let deepseek = "ollama-cloud/deepseek-v4.1-flash"
    static let sol = "openai/gpt-6.1-sol"
    static let refs = [deepseek, sol]

    static func canonicalize(_ raw: String?) -> Result<String, CarLiveModelError> {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .success(deepseek) }
        if refs.contains(trimmed) { return .success(trimmed) }
        let folded = trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        if ["deepseek", "deepseekv41flash", "ollamaclouddeepseekv41flash"].contains(folded) {
            return .success(deepseek)
        }
        if ["gpt", "gpt61", "gpt61sol", "sol", "soa", "openaigpt61sol"].contains(folded) {
            return .success(sol)
        }
        return .failure(.unknownModel)
    }

    static func split(_ ref: String) -> (providerID: String, modelID: String)? {
        guard let slash = ref.firstIndex(of: "/") else { return nil }
        let provider = String(ref[..<slash])
        let model = String(ref[ref.index(after: slash)...])
        guard !provider.isEmpty, !model.isEmpty else { return nil }
        return (provider, model)
    }
}

enum CarLivePromptWire {
    static func sessionCreateData(title: String?) throws -> Data {
        let body = title.map { ["title": $0] } ?? [:]
        return try JSONEncoder().encode(body)
    }

    static func sessionPageQuery(cursor: Int?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "roots", value: "true"),
            URLQueryItem(name: "archived", value: "true"),
            URLQueryItem(name: "limit", value: "50"),
        ]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: String(cursor)))
        }
        return items
    }

    static func startData(messageID: String, text: String, agent: String, model: Message.ModelInfo) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "messageID": messageID,
            "parts": [["type": "text", "text": text]],
            "agent": agent,
            "model": ["providerID": model.providerID, "modelID": model.modelID],
        ])
    }

    static func continueData(messageID: String, text: String, agent: String?, variant: String?) throws -> Data {
        var body: [String: Any] = [
            "messageID": messageID,
            "parts": [["type": "text", "text": text]],
        ]
        let named = agent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !named.isEmpty {
            body["agent"] = named
        }
        if let variant {
            body["variant"] = variant
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

nonisolated enum CarLiveToolJSON {
    static func error(code: String, message: String, httpStatus: Int? = nil) -> String {
        var object: [String: Any] = ["ok": false, "error": code, "message": message]
        if let httpStatus { object["http_status"] = httpStatus }
        return json(object)
    }

    static func accepted(sessionID: String, messageID: String, model: String?) -> String {
        var object: [String: Any] = [
            "ok": true,
            "status": "accepted",
            "sessionID": sessionID,
            "messageID": messageID,
        ]
        if let model, !model.isEmpty {
            object["model"] = model
        }
        return json(object)
    }

    static func stopped() -> String {
        json(["ok": true, "status": "cancelled", "message": "已确认停止，任务不在执行"])
    }

    static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"encode\",\"message\":\"结果没有送出\"}"
        }
        return text
    }
}

struct CarLiveSessionPage: Equatable, Sendable {
    var rows: [Session]
    var nextCursor: Int?
}

struct CarLiveMessagePage: Sendable {
    var messages: [MessageWithParts]
    var hasOlder: Bool
    var requestedLimit: Int
    var nextCursor: String?
    var hasDecodeGaps: Bool

    init(
        messages: [MessageWithParts],
        hasOlder: Bool,
        requestedLimit: Int,
        nextCursor: String? = nil,
        hasDecodeGaps: Bool = false
    ) {
        self.messages = messages
        self.hasOlder = hasOlder
        self.requestedLimit = requestedLimit
        self.nextCursor = nextCursor
        self.hasDecodeGaps = hasDecodeGaps
    }
}

struct CarLiveListItem: Equatable {
    var id: String
    var title: String
    var directory: String
    var status: String
    var updated: Int
    var archivedAt: Int
    var parentID: String
}

struct CarLiveListPage: Equatable {
    var rows: [CarLiveListItem]
    var nextCursor: Int?
}

struct CarLiveListWindow: Equatable {
    var records: [CarLiveListItem]
    var skip: Int
    var count: Int
    var returned: Int
    var hasMore: Bool?
    var nextSkip: Int?
    var partial: Bool
    var fetchMore: Bool
}

enum CarLiveSessionWalk {
    static let pageLimit = 50
    static let maxPages = 8

    static func include(_ item: CarLiveListItem, archivedOnly: Bool) -> Bool {
        if !item.parentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if archivedOnly { return item.archivedAt > 0 }
        return true
    }

    static func walk(pages: [CarLiveListPage], archivedOnly: Bool, skip: Int, count: Int, maxPages: Int = maxPages) -> CarLiveListWindow {
        var seen = Set<String>()
        var qualified: [CarLiveListItem] = []
        var cursor: Int?
        var fetched = 0
        var exhausted = false
        var stalled = false
        for page in pages.prefix(maxPages) {
            fetched += 1
            if let cursor, page.nextCursor == cursor { stalled = true }
            for row in page.rows where seen.insert(row.id).inserted && include(row, archivedOnly: archivedOnly) {
                qualified.append(row)
            }
            if qualified.count >= skip + count + 1 { break }
            if stalled { break }
            if page.nextCursor == nil {
                exhausted = true
                break
            }
            cursor = page.nextCursor
        }
        let need = skip + count + 1
        let cursorRemains = cursor != nil && !exhausted && !stalled
        let fetchMore = cursorRemains && qualified.count < need && fetched < maxPages
        let partial = !exhausted && qualified.count < need && !fetchMore
        let start = min(max(skip, 0), qualified.count)
        let end = min(start + count, qualified.count)
        let records = Array(qualified[start..<end])
        let known = !partial && !fetchMore
        let hasMore: Bool? = known ? qualified.count > skip + count : nil
        return CarLiveListWindow(
            records: records,
            skip: skip,
            count: count,
            returned: records.count,
            hasMore: hasMore,
            nextSkip: hasMore == true ? skip + count : nil,
            partial: partial,
            fetchMore: fetchMore
        )
    }
}

enum CarLiveHistory {
    static let bound = 200

    struct Draft: Equatable {
        var id: String
        var role: String
        var createdMS: Int?
        var completedMS: Int?
        var text: String
        var synthetic: Bool
    }

    static func drafts(from messages: [MessageWithParts]) -> [Draft] {
        messages.compactMap { row in
            let role = row.info.role
            guard role == "user" || role == "assistant", !row.info.id.isEmpty else { return nil }
            let text = row.parts.filter(\.isText).compactMap(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
            return Draft(
                id: row.info.id,
                role: role,
                createdMS: row.info.time.created,
                completedMS: row.info.time.completed,
                text: text,
                synthetic: row.parts.contains(where: \.isSyntheticText) && !row.parts.contains { $0.isText && $0.synthetic != true && !($0.text ?? "").isEmpty }
            )
        }
    }

    static func render(sessionID: String, title: String, directory: String, drafts: [Draft], skip: Int, count: Int, hasOlder: Bool) -> String {
        let ordered = drafts.sorted { lhs, rhs in
            switch (lhs.createdMS, rhs.createdMS) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return true
            case (.some, nil): return false
            default: return lhs.id < rhs.id
            }
        }
        let end = ordered.count - max(skip, 0)
        let slice: [Draft]
        let hasMore: Bool?
        let nextSkip: Int?
        if end <= 0 {
            slice = []
            hasMore = hasOlder ? nil : false
            nextSkip = nil
        } else {
            let start = max(0, end - count)
            slice = Array(ordered[start..<end])
            if start > 0 || hasOlder {
                hasMore = true
                nextSkip = skip + slice.count
            } else {
                hasMore = false
                nextSkip = nil
            }
        }
        return bounded(
            sessionID: sessionID,
            title: title,
            directory: directory,
            messages: slice,
            skip: skip,
            count: count,
            hasMore: hasMore,
            nextSkip: nextSkip
        )
    }

    static func bounded(
        sessionID: String,
        title: String,
        directory: String,
        messages: [Draft],
        skip: Int,
        count: Int,
        hasMore: Bool?,
        nextSkip: Int?
    ) -> String {
        var limit = textByteLimit
        var drop = 0
        var last = CarLiveToolJSON.error(code: "failed", message: "会话记录没有送出")
        while drop <= messages.count {
            let kept = Array(messages.dropFirst(drop))
            let json = payload(
                sessionID: sessionID,
                title: clip(title, limit: 240).text,
                directory: clip(directory, limit: 240).text,
                messages: kept,
                skip: skip,
                count: count,
                hasMore: hasMore,
                nextSkip: nextSkip,
                textLimit: limit,
                dropped: drop > 0
            )
            last = json
            if json.utf8.count <= outputByteLimit { return json }
            if limit > 160 {
                limit /= 2
                continue
            }
            drop += 1
            limit = textByteLimit
        }
        return last
    }

    private static func payload(
        sessionID: String,
        title: String,
        directory: String,
        messages: [Draft],
        skip: Int,
        count: Int,
        hasMore: Bool?,
        nextSkip: Int?,
        textLimit: Int,
        dropped: Bool
    ) -> String {
        var truncated = dropped
        let rows: [[String: Any]] = messages.map { item in
            let clipped = clip(item.text, limit: textLimit)
            if clipped.truncated { truncated = true }
            var row: [String: Any] = [
                "id": item.id,
                "role": item.role,
                "created_at": item.createdMS.map(iso) ?? NSNull(),
                "created_at_ms": item.createdMS ?? NSNull(),
                "completed_at": item.completedMS.map(iso) ?? NSNull(),
                "text": clipped.text,
            ]
            if item.synthetic { row["synthetic"] = true }
            if clipped.truncated { row["truncated"] = true }
            return row
        }
        var pagination: [String: Any] = ["skip": skip, "count": count, "returned": rows.count]
        if let hasMore { pagination["hasMore"] = hasMore }
        if let nextSkip { pagination["nextSkip"] = nextSkip }
        if truncated { pagination["partial"] = true }
        return CarLiveToolJSON.json([
            "ok": true,
            "session": ["id": sessionID, "title": title.isEmpty ? sessionID : title, "directory": directory],
            "messages": rows,
            "pagination": pagination,
        ])
    }

    static let outputByteLimit = CarLiveProtocol.maxFunctionOutputBytes
    static let textByteLimit = 8_000

    static func iso(_ ms: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    static func clip(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        if text.utf8.count <= limit { return (text, false) }
        var result = ""
        var used = 0
        for character in text {
            let next = String(character).utf8.count
            if used + next > limit { break }
            result.append(character)
            used += next
        }
        return (result, true)
    }
}

enum CarLiveOutputBound {
    static func json(_ object: [String: Any]) -> String {
        var rows = object["records"] as? [[String: String]] ?? object["sessions"] as? [[String: String]] ?? []
        var limit = 512
        var dropped = 0
        var last = CarLiveToolJSON.error(code: "failed", message: "查询结果没有送出")
        while true {
            let kept = dropped < rows.count ? Array(rows.dropLast(dropped)) : []
            var copy = object
            let clipped: [[String: String]] = kept.map { row in
                var next = row
                for key in ["title", "directory", "status"] {
                    if let value = next[key] {
                        next[key] = CarLiveHistory.clip(value, limit: limit).text
                    }
                }
                return next
            }
            copy["records"] = clipped
            copy["sessions"] = clipped
            var pagination = copy["pagination"] as? [String: Any] ?? [:]
            pagination["returned"] = clipped.count
            if dropped > 0 || limit < 512 { pagination["partial"] = true }
            copy["pagination"] = pagination
            let json = CarLiveToolJSON.json(copy)
            last = json
            if json.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes { return json }
            if limit > 32 {
                limit /= 2
                continue
            }
            if dropped >= rows.count { return last }
            dropped += 1
            limit = 512
        }
    }
}

enum CarLiveStopJudge {
    static func isActive(_ status: String?) -> Bool {
        status == "busy" || status == "retry" || status == "queued"
    }

    static func isIdle(_ status: String?) -> Bool {
        status == nil || status == "idle"
    }

    static func confirm(
        abort: () async throws -> Void,
        status: () async throws -> String?,
        childrenActive: () async throws -> Bool,
        sleep: () async -> Void
    ) async throws -> String {
        try await abort()
        for attempt in 0..<4 {
            let current = try await status()
            let children = try await childrenActive()
            if isIdle(current) && !children {
                return CarLiveToolJSON.stopped()
            }
            if attempt == 3 {
                return CarLiveToolJSON.error(code: "not_confirmed", message: "停止尚未确认")
            }
            if current == "queued" {
                try await abort()
            }
            await sleep()
        }
        return CarLiveToolJSON.error(code: "not_confirmed", message: "停止尚未确认")
    }
}

struct CarLiveLookup: Equatable {
    var session: Session?
    var httpStatus: Int
    var transport: Bool

    var found: Bool { session != nil && httpStatus == 200 }
    var clearsBinding: Bool { httpStatus == 404 }
}

struct CarLiveToolContext {
    var trackedSessionID: String?
    var directory: String?
    var startAgent: String
    var allows: () async -> Bool
    var reserveReply: ((CarLiveReplyReservation) async -> Void)? = nil
    var rollbackReply: ((String) async -> Void)? = nil
}

struct CarLiveToolEffect: Equatable {
    var output: String
    var sessionID: String?
    var messageID: String?
    var directory: String?
    var model: String?
    var clearSessionID: String?
    var poll: Bool = false
    var prepareToken: String? = nil
}

protocol CarLiveToolClient: Actor {
    func bindOwner(_ allows: @escaping () async -> Bool) async
    func listed(archivedOnly: Bool, skip: Int, count: Int) async throws -> CarLiveListWindow
    func lookup(id: String, directory: String?) async -> CarLiveLookup
    func history(sessionID: String, directory: String, skip: Int, count: Int) async -> String
    func connectedRefs() async throws -> Set<String>
    func create(directory: String?) async throws -> Session
    func startPrompt(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?) async throws -> Data
    func continuePrompt(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?) async throws -> Data
    func confirmStop(sessionID: String) async throws -> String
    func answer(sessionID: String, answers: [[String]], permissionReply: String?) async throws
    func setArchived(sessionID: String, archived: Int) async throws -> Int
    func children(sessionID: String) async throws -> [Session]
    func round(sessionID: String, messageID: String) async throws -> CarLiveRoundSnapshot
}

struct CarLiveRoundSnapshot: Equatable {
    var assistantText: String?
    var finalFinish: Bool
    var openTools: Bool
    var childrenActive: Bool
    var pending: Bool
    var failed: Bool
}

enum CarLiveRound {
    static func commentary(_ snapshot: CarLiveRoundSnapshot) -> String? {
        guard snapshot.finalFinish, !snapshot.openTools, !snapshot.childrenActive, !snapshot.pending, !snapshot.failed else { return nil }
        let text = snapshot.assistantText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func isFinal(_ finish: String?) -> Bool {
        guard let finish, !finish.isEmpty, finish != "unknown" else { return false }
        return finish != "tool-calls" && finish != "tool_calls"
    }
}

enum CarLiveToolHandler {
    static func run(_ name: String, arguments: String, client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        guard await context.allows() else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
        }
        guard let object = jsonObject(arguments) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        switch name {
        case CarLiveToolName.queryJobs:
            return await query(object, client: client, context: context)
        case CarLiveToolName.getSessionMessages:
            return await history(object, client: client, context: context)
        case CarLiveToolName.startJob:
            return await start(object, client: client, context: context)
        case CarLiveToolName.continueJob:
            return await continueJob(object, client: client, context: context)
        case CarLiveToolName.stopJob:
            return await stop(object, client: client, context: context)
        case CarLiveToolName.answerPending:
            return await answer(object, client: client, context: context)
        case CarLiveToolName.archiveJob:
            return await archive(object, client: client, context: context, archiving: true)
        case CarLiveToolName.unarchiveJob:
            return await archive(object, client: client, context: context, archiving: false)
        default:
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "unknown_function", message: "未知函数"))
        }
    }

    private static func query(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        let scope = object["queryScope"] as? String ?? ""
        guard ["recent", "current", "specified"].contains(scope) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        if scope == "specified" {
            guard let id = string(object["sessionID"]), !id.isEmpty else {
                return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "needs_input", message: "需要明确的会话编号"))
            }
            return await lookupEffect(id, explicit: id, client: client, context: context) { session in
                CarLiveToolJSON.json([
                    "ok": true,
                    "query_ok": true,
                    "sessions": [["id": session.id, "title": session.title, "directory": session.directory]],
                    "session": ["id": session.id, "directory": session.directory],
                ])
            }
        }
        if scope == "current" {
            guard let id = context.trackedSessionID, !id.isEmpty else {
                return CarLiveToolEffect(output: CarLiveToolJSON.json(["ok": true, "query_ok": true, "current": ["id": "", "exists": false]]))
            }
            let lookup = await client.lookup(id: id, directory: nil)
            if lookup.clearsBinding {
                return CarLiveToolEffect(output: CarLiveToolJSON.json(["ok": true, "query_ok": true, "current": ["id": id, "exists": false]]), clearSessionID: id)
            }
            guard lookup.found, let session = lookup.session else {
                return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "lookup_failed", message: "会话没有核对成功", httpStatus: lookup.httpStatus))
            }
            return CarLiveToolEffect(output: CarLiveToolJSON.json([
                "ok": true,
                "query_ok": true,
                "current": ["id": session.id, "exists": true, "directory": session.directory],
            ]))
        }
        guard let params = listParams(object) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        do {
            guard let window = try await stage(context, { try await client.listed(archivedOnly: params.archivedOnly, skip: params.skip, count: params.count) }) else {
                return stale()
            }
            let rows: [[String: String]] = window.records.map { ["id": $0.id, "title": $0.title, "directory": $0.directory, "status": $0.status] }
            var pagination: [String: Any] = ["skip": window.skip, "count": window.count, "returned": window.returned]
            if let hasMore = window.hasMore { pagination["hasMore"] = hasMore }
            if let nextSkip = window.nextSkip { pagination["nextSkip"] = nextSkip }
            if window.partial { pagination["partial"] = true }
            return CarLiveToolEffect(output: CarLiveOutputBound.json(["ok": true, "query_ok": true, "records": rows, "sessions": rows, "pagination": pagination]))
        } catch {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "查询没有成功"))
        }
    }

    private static func history(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        guard let window = skipCount(object) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        guard let chosen = choose(explicit: string(object["sessionID"]), tracked: context.trackedSessionID) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "needs_input", message: "需要先查询并指定会话编号"))
        }
        let explicit = string(object["sessionID"]) ?? ""
        return await lookupEffect(chosen, explicit: explicit, client: client, context: context) { session in
            await client.history(sessionID: session.id, directory: session.directory, skip: window.skip, count: window.count)
        }
    }

    private static func start(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        let text = object["text"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "missing_text", message: "需要任务内容"))
        }
        switch requestedModel(object) {
        case .failure(let error):
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: error.code, message: "未找到请求的模型"))
        case .success(let ref):
            guard let spec = CarLiveModel.split(ref) else {
                return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "unknown_model", message: "未找到请求的模型"))
            }
            do {
                guard let connected = try await stage(context, { try await client.connectedRefs() }) else {
                    return stale()
                }
                guard connected.contains(ref) else {
                    return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "model_not_connected", message: "所选模型未连接"))
                }
                guard let session = try await stage(context, { try await client.create(directory: context.directory) }) else {
                    return stale()
                }
                let messageID = newMessageID()
                let agent = context.startAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "build" : context.startAgent
                let reserved = await reserveReply(context, sessionID: session.id, directory: session.directory, userMessageID: messageID, title: session.title, isNewSession: true)
                if case .stale = reserved { return stale() }
                do {
                    guard let _ = try await stage(context, {
                        try await client.startPrompt(
                        sessionID: session.id,
                        messageID: messageID,
                        text: text,
                        agent: agent,
                        model: Message.ModelInfo(providerID: spec.providerID, modelID: spec.modelID),
                        directory: context.directory
                    )
                    }) else {
                        await rollback(reserved, context)
                        return stale()
                    }
                } catch {
                    await rollback(reserved, context)
                    return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "任务没有提交成功"))
                }
                return CarLiveToolEffect(
                    output: CarLiveToolJSON.accepted(sessionID: session.id, messageID: messageID, model: ref),
                    sessionID: session.id,
                    messageID: messageID,
                    directory: session.directory,
                    model: ref,
                    poll: true,
                    prepareToken: token(reserved)
                )
            } catch {
                return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "任务没有提交成功"))
            }
        }
    }

    private static func continueJob(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        let text = object["text"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "missing_text", message: "需要任务内容"))
        }
        guard let chosen = choose(explicit: string(object["sessionID"]), tracked: context.trackedSessionID) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "needs_input", message: "需要先查询并指定会话编号"))
        }
        guard let lookup = await stage(context, { await client.lookup(id: chosen, directory: nil) }) else {
            return stale()
        }
        if lookup.clearsBinding {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "session_not_found", message: "会话不存在"), clearSessionID: chosen)
        }
        guard lookup.found, let session = lookup.session else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "lookup_failed", message: "会话没有核对成功", httpStatus: lookup.httpStatus))
        }
        let directory = session.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "directory_unknown", message: "会话目录没有核对"))
        }
        let messageID = newMessageID()
        let reserved = await reserveReply(context, sessionID: session.id, directory: directory, userMessageID: messageID, title: session.title, isNewSession: false)
        if case .stale = reserved { return stale() }
        do {
            guard let _ = try await stage(context, {
                try await client.continuePrompt(
                    sessionID: session.id,
                    messageID: messageID,
                    text: text,
                    agent: nil,
                    variant: nil,
                    directory: directory
                )
            }) else {
                await rollback(reserved, context)
                return stale()
            }
            return CarLiveToolEffect(
                output: CarLiveToolJSON.accepted(sessionID: session.id, messageID: messageID, model: nil),
                sessionID: session.id,
                messageID: messageID,
                directory: directory,
                poll: true,
                prepareToken: token(reserved)
            )
        } catch {
            await rollback(reserved, context)
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "任务没有提交成功"))
        }
    }

    private static func stop(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        guard let chosen = choose(explicit: string(object["sessionID"]), tracked: context.trackedSessionID) else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "needs_input", message: "需要先查询并指定会话编号"))
        }
        guard let lookup = await stage(context, { await client.lookup(id: chosen, directory: nil) }) else {
            return stale()
        }
        if lookup.clearsBinding {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "session_not_found", message: "会话不存在"), clearSessionID: chosen)
        }
        guard lookup.found else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "lookup_failed", message: "会话没有核对成功", httpStatus: lookup.httpStatus))
        }
        do {
            guard let output = try await stage(context, { try await client.confirmStop(sessionID: lookup.session?.id ?? chosen) }) else {
                return stale()
            }
            return CarLiveToolEffect(output: output, sessionID: chosen)
        } catch {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "停止请求没有成功"))
        }
    }

    private static func answer(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext) async -> CarLiveToolEffect {
        guard let sessionID = context.trackedSessionID, !sessionID.isEmpty else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "needs_input", message: "没有待确认项"))
        }
        let reply = object["permissionReply"] as? String
        if let reply, reply != "once", reply != "reject" {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        let answers = (object["answers"] as? [Any])?.compactMap { row in
            (row as? [Any])?.compactMap { $0 as? String }
        } ?? []
        do {
            guard await context.allows() else {
                return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
            }
            try await client.answer(sessionID: sessionID, answers: answers, permissionReply: reply)
            return CarLiveToolEffect(output: CarLiveToolJSON.accepted(sessionID: sessionID, messageID: "", model: ""))
        } catch {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "failed", message: "答复没有送出"))
        }
    }

    private struct ArchiveSnapshot {
        var nodes: [String: Session]
        var children: [String: [String]]
        var order: [String]
    }

    private enum ArchiveWalk {
        case ready(ArchiveSnapshot)
        case stale
        case failed(Int?)
        case limited
    }

    private static func archive(_ object: [String: Any], client: any CarLiveToolClient, context: CarLiveToolContext, archiving: Bool) async -> CarLiveToolEffect {
        guard let sessionID = CarLiveArchiveTools.requiredSessionID(object) else {
            return CarLiveToolEffect(output: CarLiveArchiveTools.outcome(ok: false, status: "needs_input", sessionID: "", title: "", archived: false, error: "needs_input", message: "需要真实的会话编号"))
        }
        guard let lookup = await stage(context, { await client.lookup(id: sessionID, directory: nil) }) else {
            return stale()
        }
        if lookup.clearsBinding {
            return CarLiveToolEffect(
                output: CarLiveArchiveTools.outcome(ok: false, status: "session_not_found", sessionID: sessionID, title: "", archived: false, error: "session_not_found", message: "会话不存在", httpStatus: lookup.httpStatus),
                clearSessionID: sessionID
            )
        }
        guard lookup.found, let session = lookup.session, session.id == sessionID else {
            return CarLiveToolEffect(output: CarLiveArchiveTools.outcome(ok: false, status: "lookup_failed", sessionID: sessionID, title: "", archived: false, error: "lookup_failed", message: "会话没有核对成功", httpStatus: lookup.httpStatus == 0 ? nil : lookup.httpStatus))
        }
        let directory = session.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else {
            return CarLiveToolEffect(output: CarLiveArchiveTools.outcome(ok: false, status: "directory_unknown", sessionID: session.id, title: session.title, archived: CarLiveArchiveTools.isArchived(session.time.archived), error: "directory_unknown", message: "会话目录没有核对"))
        }
        let walked = await discover(root: session, client: client, context: context, parentFirst: !archiving)
        let snapshot: ArchiveSnapshot
        switch walked {
        case .stale:
            return stale()
        case .failed(let status):
            return CarLiveToolEffect(output: CarLiveArchiveTools.outcome(ok: false, status: "lookup_failed", sessionID: session.id, title: session.title, archived: CarLiveArchiveTools.isArchived(session.time.archived), error: "lookup_failed", message: "子树没有读全", httpStatus: status))
        case .limited:
            return CarLiveToolEffect(output: CarLiveArchiveTools.partial(
                sessionID: session.id,
                title: session.title,
                archived: CarLiveArchiveTools.isArchived(session.time.archived),
                verified: [],
                failed: [],
                pending: [],
                error: "partial",
                message: "子树超过快照上限，不要说已经全部完成"
            ))
        case .ready(let ready):
            snapshot = ready
        }
        let stamp = archiving ? CarLiveArchiveTools.archiveMillis() : 0
        var verified: [String] = []
        var patched = false
        var rootArchived = CarLiveArchiveTools.isArchived(session.time.archived)
        for id in snapshot.order {
            guard let node = snapshot.nodes[id] else { continue }
            if desired(node.time.archived, archiving: archiving) {
                if id == session.id { rootArchived = archiving }
                verified.append(id)
                continue
            }
            let written = await writeNode(id, expectedDirectory: node.directory, stamp: stamp, rootID: sessionID, title: session.title, archived: CarLiveArchiveTools.isArchived(session.time.archived), verified: verified, orderCount: snapshot.order.count, client: client, context: context)
            switch written {
            case .stale:
                return stale()
            case .stop(let effect):
                return effect
            case .verified:
                if id == session.id { rootArchived = archiving }
                verified.append(id)
                patched = true
            }
        }
        let reconciled = await reconcile(snapshot, client: client, context: context)
        switch reconciled {
        case .stale:
            return stale()
        case .changed(let pending):
            return CarLiveToolEffect(output: CarLiveArchiveTools.partial(
                sessionID: session.id,
                title: session.title,
                archived: rootArchived,
                verified: verified,
                failed: [],
                pending: pending,
                error: "partial",
                message: "子树在快照之后又变了，不要说已经全部完成"
            ))
        case .failed:
            return CarLiveToolEffect(output: CarLiveArchiveTools.partial(
                sessionID: session.id,
                title: session.title,
                archived: rootArchived,
                verified: verified,
                failed: [],
                pending: [],
                error: "not_confirmed",
                message: "子树复读没有完成，不要说已经全部完成"
            ))
        case .stable:
            break
        }
        return CarLiveToolEffect(output: CarLiveArchiveTools.outcome(
            ok: true,
            status: patched ? (archiving ? "archived" : "unarchived") : (archiving ? "already_archived" : "already_unarchived"),
            sessionID: session.id,
            title: session.title,
            archived: archiving,
            snapshot: true
        ))
    }

    private enum NodeWrite {
        case verified
        case stale
        case stop(CarLiveToolEffect)
    }

    private enum Reconcile {
        case stable
        case stale
        case failed
        case changed([String])
    }

    private static func desired(_ archived: Int?, archiving: Bool) -> Bool {
        archiving ? CarLiveArchiveTools.isArchived(archived) : CarLiveArchiveTools.isUnarchived(archived)
    }

    private static func discover(root: Session, client: any CarLiveToolClient, context: CarLiveToolContext, parentFirst: Bool) async -> ArchiveWalk {
        var nodes = [root.id: root]
        var children: [String: [String]] = [:]
        var depth = [root.id: 0]
        var pending = [root.id]
        while !pending.isEmpty {
            if nodes.count > CarLiveArchiveTools.maxNodes { return .limited }
            let id = pending.removeFirst()
            let listed: [Session]
            do {
                guard let page = try await stage(context, { try await client.children(sessionID: id) }) else { return .stale }
                listed = page
            } catch CarLiveAPIUnsupported.closed {
                return .stale
            } catch APIError.httpError(let status, _) {
                return .failed(status)
            } catch {
                return .failed(nil)
            }
            var childIDs: [String] = []
            for child in listed {
                let parent = child.parentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let childDirectory = child.directory.trimmingCharacters(in: .whitespacesAndNewlines)
                if child.id.isEmpty || parent != id || childDirectory.isEmpty { return .failed(nil) }
                if childIDs.contains(child.id) { continue }
                childIDs.append(child.id)
                if nodes[child.id] != nil { continue }
                let nextDepth = (depth[id] ?? 0) + 1
                if nextDepth > CarLiveArchiveTools.maxDepth || nodes.count >= CarLiveArchiveTools.maxNodes { return .limited }
                nodes[child.id] = child
                depth[child.id] = nextDepth
                pending.append(child.id)
            }
            children[id] = childIDs
        }
        let order = CarLiveArchiveTools.ids(root: root.id, children: children, parentFirst: parentFirst)
        return .ready(ArchiveSnapshot(nodes: nodes, children: children, order: order))
    }

    private static func writeNode(_ id: String, expectedDirectory: String, stamp: Int, rootID: String, title: String, archived: Bool, verified: [String], orderCount: Int, client: any CarLiveToolClient, context: CarLiveToolContext) async -> NodeWrite {
        do {
            guard let _ = try await stage(context, { try await client.setArchived(sessionID: id, archived: stamp) }) else {
                return .stale
            }
        } catch CarLiveAPIUnsupported.closed {
            return .stale
        } catch APIError.httpError(let status, _) where status == 404 {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: archived, verified: verified, failed: [id], orderCount: orderCount, error: "session_not_found", message: "会话不存在", clearRoot: id == rootID))
        } catch APIError.httpError {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: archived, verified: verified, failed: [id], orderCount: orderCount, error: "failed", message: "归档状态没有改成", clearRoot: false))
        } catch {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: archived, verified: verified, failed: [id], orderCount: orderCount, error: "failed", message: "归档状态没有改成", clearRoot: false))
        }
        guard let readback = await stage(context, { await client.lookup(id: id, directory: nil) }) else {
            return .stale
        }
        if readback.clearsBinding {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: archived, verified: verified, failed: [id], orderCount: orderCount, error: "session_not_found", message: "会话不存在", clearRoot: id == rootID))
        }
        guard readback.found, let confirmed = readback.session, confirmed.id == id, confirmed.directory == expectedDirectory else {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: archived, verified: verified, failed: [id], orderCount: orderCount, error: "not_confirmed", message: "回读仍是原来的归档状态", clearRoot: false))
        }
        let flag = stamp == 0 ? CarLiveArchiveTools.isUnarchived(confirmed.time.archived) : CarLiveArchiveTools.isArchived(confirmed.time.archived)
        guard flag else {
            return .stop(stopped(id: id, rootID: rootID, title: title, archived: CarLiveArchiveTools.isArchived(confirmed.time.archived), verified: verified, failed: [id], orderCount: orderCount, error: "not_confirmed", message: "回读仍是原来的归档状态", clearRoot: false))
        }
        return .verified
    }

    private static func reconcile(_ snapshot: ArchiveSnapshot, client: any CarLiveToolClient, context: CarLiveToolContext) async -> Reconcile {
        var known = Set(snapshot.order)
        var pending: [String] = []
        for id in snapshot.order {
            let listed: [Session]
            do {
                guard let page = try await stage(context, { try await client.children(sessionID: id) }) else { return .stale }
                listed = page
            } catch CarLiveAPIUnsupported.closed {
                return .stale
            } catch {
                return .failed
            }
            for child in listed where !child.id.isEmpty && known.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return pending.isEmpty ? .stable : .changed(pending)
    }

    private static func stopped(id: String, rootID: String, title: String, archived: Bool, verified: [String], failed: [String], orderCount: Int, error: String, message: String, clearRoot: Bool) -> CarLiveToolEffect {
        if orderCount <= 1 && verified.isEmpty {
            return CarLiveToolEffect(
                output: CarLiveArchiveTools.outcome(ok: false, status: error == "not_confirmed" ? "not_confirmed" : error, sessionID: rootID, title: title, archived: archived, error: error, message: message),
                clearSessionID: clearRoot ? rootID : nil
            )
        }
        return CarLiveToolEffect(
            output: CarLiveArchiveTools.partial(sessionID: rootID, title: title, archived: archived, verified: verified, failed: failed, pending: [], error: error == "not_confirmed" ? "not_confirmed" : "partial", message: message),
            clearSessionID: clearRoot ? rootID : nil
        )
    }

    private static func lookupEffect(_ id: String, explicit: String, client: any CarLiveToolClient, context: CarLiveToolContext, body: (Session) async -> String) async -> CarLiveToolEffect {
        guard let lookup = await stage(context, { await client.lookup(id: id, directory: nil) }) else {
            return stale()
        }
        if !explicit.isEmpty, explicit != id {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "session_not_found", message: "会话不存在"))
        }
        if lookup.clearsBinding {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "session_not_found", message: "会话不存在"), clearSessionID: id)
        }
        guard lookup.found, let session = lookup.session else {
            return CarLiveToolEffect(output: CarLiveToolJSON.error(code: "lookup_failed", message: "会话没有核对成功", httpStatus: lookup.httpStatus))
        }
        guard let output = await stage(context, { await body(session) }) else {
            return stale()
        }
        return CarLiveToolEffect(output: output, sessionID: session.id, directory: session.directory)
    }

    static func requestedModel(_ object: [String: Any]) -> Result<String, CarLiveModelError> {
        guard object.keys.contains("requestedModel") else { return CarLiveModel.canonicalize(nil) }
        let value = object["requestedModel"]
        if value == nil || value is NSNull { return CarLiveModel.canonicalize(nil) }
        guard let text = value as? String else { return .failure(.unknownModel) }
        return CarLiveModel.canonicalize(text)
    }

    private static func stale() -> CarLiveToolEffect {
        CarLiveToolEffect(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
    }

    private enum Reserved {
        case skipped
        case token(String)
        case stale
    }

    private static func reserveReply(_ context: CarLiveToolContext, sessionID: String, directory: String, userMessageID: String, title: String, isNewSession: Bool) async -> Reserved {
        guard context.reserveReply != nil else { return .skipped }
        guard await context.allows() else { return .stale }
        let token = UUID().uuidString
        await context.reserveReply?(CarLiveReplyReservation(token: token, sessionID: sessionID, directory: directory, userMessageID: userMessageID, title: title, isNewSession: isNewSession))
        guard await context.allows() else {
            await context.rollbackReply?(token)
            return .stale
        }
        return .token(token)
    }

    private static func token(_ reserved: Reserved) -> String? {
        if case .token(let token) = reserved { return token }
        return nil
    }

    private static func rollback(_ reserved: Reserved, _ context: CarLiveToolContext) async {
        guard let token = token(reserved) else { return }
        await context.rollbackReply?(token)
    }

    private static func stage<T>(_ context: CarLiveToolContext, _ work: () async throws -> T) async throws -> T? {
        guard await context.allows() else { return nil }
        let value = try await work()
        guard await context.allows() else { return nil }
        return value
    }

    private static func stage<T>(_ context: CarLiveToolContext, _ work: () async -> T) async -> T? {
        guard await context.allows() else { return nil }
        let value = await work()
        guard await context.allows() else { return nil }
        return value
    }

    static func choose(explicit: String?, tracked: String?) -> String? {
        let asked = explicit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !asked.isEmpty { return asked }
        let known = tracked?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return known.isEmpty ? nil : known
    }

    static func newMessageID() -> String {
        "msg_" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))
    }

    private static func jsonObject(_ arguments: String) -> [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func string(_ value: Any?) -> String? {
        if value == nil || value is NSNull { return nil }
        return value as? String
    }

    private static func listParams(_ object: [String: Any]) -> (archivedOnly: Bool, skip: Int, count: Int)? {
        let archivedOnly: Bool
        if object.keys.contains("archivedOnly") {
            guard let value = boolean(object["archivedOnly"]) else { return nil }
            archivedOnly = value
        } else {
            archivedOnly = true
        }
        guard let window = skipCount(object) else { return nil }
        return (archivedOnly, window.skip, window.count)
    }

    private static func skipCount(_ object: [String: Any]) -> (skip: Int, count: Int)? {
        guard let skip = whole(object, key: "skip", missing: 0, valid: { $0 >= 0 }),
              let count = whole(object, key: "count", missing: 10, valid: { (1...50).contains($0) }) else { return nil }
        return (skip, count)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func whole(_ object: [String: Any], key: String, missing: Int, valid: (Int) -> Bool) -> Int? {
        guard object.keys.contains(key) else { return missing }
        guard let value = object[key], let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, double <= Double(Int.max), double >= Double(Int.min) else { return nil }
        let parsed = number.intValue
        guard valid(parsed) else { return nil }
        return parsed
    }
}

extension CarLiveToolClient {
    func bindOwner(_ allows: @escaping () async -> Bool) async {}
    func setArchived(sessionID: String, archived: Int) async throws -> Int {
        throw CarLiveAPIUnsupported.archive
    }
    func children(sessionID: String) async throws -> [Session] {
        throw CarLiveAPIUnsupported.children
    }
}

actor CarLiveAPIBox: CarLiveToolClient {
    private let api: any APIClientProtocol
    private let sleepNanoseconds: UInt64
    private var allows: () async -> Bool = { true }
    private var transportToken: UInt64 = 0

    init(_ api: any APIClientProtocol, sleepNanoseconds: UInt64 = 200_000_000) {
        self.api = api
        self.sleepNanoseconds = sleepNanoseconds
    }

    func bindOwner(_ allows: @escaping () async -> Bool) {
        self.allows = allows
    }

    func bindTransport(_ token: UInt64) {
        transportToken = token
    }

    private func guarded<T>(_ work: () async throws -> T) async throws -> T {
        guard await allows() else { throw CarLiveAPIUnsupported.closed }
        let value = try await work()
        guard await allows() else { throw CarLiveAPIUnsupported.closed }
        return value
    }

    func listed(archivedOnly: Bool, skip: Int, count: Int) async throws -> CarLiveListWindow {
        var pages: [CarLiveListPage] = []
        var cursor: Int?
        var window = CarLiveSessionWalk.walk(pages: pages, archivedOnly: archivedOnly, skip: skip, count: count)
        while pages.count < CarLiveSessionWalk.maxPages && (pages.isEmpty || window.fetchMore) {
            let page = try await guarded { try await self.api.experimentalRootSessionPage(cursor: cursor, transportToken: self.transportToken) }
            let rows = page.rows.map { session in
                CarLiveListItem(
                    id: session.id,
                    title: session.title.isEmpty ? session.id : session.title,
                    directory: session.directory,
                    status: "",
                    updated: session.time.updated,
                    archivedAt: session.time.archived ?? 0,
                    parentID: session.parentID ?? ""
                )
            }
            pages.append(CarLiveListPage(rows: rows, nextCursor: page.nextCursor))
            window = CarLiveSessionWalk.walk(pages: pages, archivedOnly: archivedOnly, skip: skip, count: count)
            cursor = page.nextCursor
            if !window.fetchMore { break }
        }
        let statuses = (try? await guarded { try await self.api.sessionStatusForLive(transportToken: self.transportToken) }) ?? [:]
        let records = window.records.map { row in
            var copy = row
            if copy.status.isEmpty { copy.status = statuses[row.id]?.type ?? "" }
            return copy
        }
        return CarLiveListWindow(
            records: records,
            skip: window.skip,
            count: window.count,
            returned: records.count,
            hasMore: window.hasMore,
            nextSkip: window.nextSkip,
            partial: window.partial,
            fetchMore: false
        )
    }

    func lookup(id: String, directory: String?) async -> CarLiveLookup {
        do {
            let session = try await guarded { try await self.api.sessionForLive(sessionID: id, directory: directory, transportToken: self.transportToken) }
            return CarLiveLookup(session: session, httpStatus: 200, transport: false)
        } catch APIError.httpError(let status, _) {
            return CarLiveLookup(session: nil, httpStatus: status, transport: false)
        } catch {
            return CarLiveLookup(session: nil, httpStatus: 0, transport: true)
        }
    }

    func history(sessionID: String, directory: String, skip: Int, count: Int) async -> String {
        let limit = await min(max(skip, 0) + max(count, 1), CarLiveHistory.bound)
        do {
            let page = try await guarded { try await self.api.messagePageForLive(sessionID: sessionID, limit: limit, transportToken: self.transportToken) }
            let session = try? await guarded { try await self.api.sessionForLive(sessionID: sessionID, directory: directory, transportToken: self.transportToken) }
            return CarLiveHistory.render(
                sessionID: sessionID,
                title: session?.title ?? sessionID,
                directory: directory,
                drafts: CarLiveHistory.drafts(from: page.messages),
                skip: skip,
                count: count,
                hasOlder: page.hasOlder
            )
        } catch APIError.httpError(let status, _) {
            return CarLiveToolJSON.error(code: status == 404 ? "session_not_found" : "lookup_failed", message: "会话记录没有读全", httpStatus: status)
        } catch {
            return CarLiveToolJSON.error(code: "lookup_failed", message: "会话记录没有读全", httpStatus: 0)
        }
    }

    func connectedRefs() async throws -> Set<String> {
        let registry = try await guarded { try await self.api.providerRegistryForLive(transportToken: self.transportToken) }
        let connected = Set(registry.connectedProviderIDs)
        var refs = Set<String>()
        for provider in registry.providers where connected.contains(provider.id) {
            for (key, model) in provider.models {
                let id = model.id.isEmpty ? key : model.id
                refs.insert("\(provider.id)/\(id)")
            }
        }
        return refs
    }

    func create(directory: String?) async throws -> Session {
        try await guarded { try await self.api.createSessionForLive(directory: directory, transportToken: self.transportToken) }
    }

    func startPrompt(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?) async throws -> Data {
        let body = try CarLivePromptWire.startData(messageID: messageID, text: text, agent: agent, model: model)
        try await guarded { try await self.api.promptAsyncForLive(sessionID: sessionID, messageID: messageID, text: text, agent: agent, model: model, directory: directory, transportToken: self.transportToken) }
        return body
    }

    func continuePrompt(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?) async throws -> Data {
        let body = try CarLivePromptWire.continueData(messageID: messageID, text: text, agent: agent, variant: variant)
        try await guarded { try await self.api.promptAsyncInherited(sessionID: sessionID, messageID: messageID, text: text, agent: agent, variant: variant, directory: directory, transportToken: self.transportToken) }
        return body
    }

    func confirmStop(sessionID: String) async throws -> String {
        let api = api
        let pause = sleepNanoseconds
        return try await CarLiveStopJudge.confirm(
            abort: { try await self.guarded { try await api.abortForLive(sessionID: sessionID, transportToken: self.transportToken) } },
            status: {
                let map = try await self.guarded { try await api.sessionStatusForLive(transportToken: self.transportToken) }
                return map[sessionID]?.type
            },
            childrenActive: {
                let map = try await self.guarded { try await api.sessionStatusForLive(transportToken: self.transportToken) }
                let children = try await self.guarded { try await api.sessionChildrenForLive(sessionID: sessionID, transportToken: self.transportToken) }
                return children.contains { CarLiveStopJudge.isActive(map[$0.id]?.type) }
            },
            sleep: { try? await Task.sleep(nanoseconds: pause) }
        )
    }

    func setArchived(sessionID: String, archived: Int) async throws -> Int {
        try await guarded {
            try await self.api.updateSessionArchivedForLive(sessionID: sessionID, archived: archived, transportToken: self.transportToken)
        }
    }

    func children(sessionID: String) async throws -> [Session] {
        try await guarded {
            try await self.api.sessionChildrenForLive(sessionID: sessionID, transportToken: self.transportToken)
        }
    }

    func answer(sessionID: String, answers: [[String]], permissionReply: String?) async throws {
        let permissions = try await guarded { try await self.api.pendingPermissionsForLive(transportToken: self.transportToken) }.filter { $0.sessionID == sessionID }
        if let permission = permissions.first {
            let reply = permissionReply == "reject" ? APIClient.PermissionResponse.reject : .once
            try await guarded { try await self.api.respondPermissionForLive(sessionID: sessionID, permissionID: permission.id, response: reply, transportToken: self.transportToken) }
            return
        }
        guard !answers.isEmpty, let question = try await guarded({ try await self.api.pendingQuestionsForLive(transportToken: self.transportToken) }).first(where: { $0.sessionID == sessionID }) else {
            throw CarLiveAPIUnsupported.answer
        }
        try await guarded { try await self.api.replyQuestionForLive(requestID: question.id, answers: answers, transportToken: self.transportToken) }
    }

    func round(sessionID: String, messageID: String) async throws -> CarLiveRoundSnapshot {
        let page = try await guarded { try await self.api.messagePageForLive(sessionID: sessionID, limit: 50, transportToken: self.transportToken) }
        let mine = page.messages.filter { $0.info.parentID == messageID && $0.info.role == "assistant" }
        let final = mine.first { CarLiveRound.isFinal($0.info.finish) }
        let openTools = mine.contains { row in
            row.parts.contains { part in
                part.isTool && (part.state?.displayString == "pending" || part.state?.displayString == "running")
            }
        }
        let map = try await guarded { try await self.api.sessionStatusForLive(transportToken: self.transportToken) }
        let children = try await guarded { try await self.api.sessionChildrenForLive(sessionID: sessionID, transportToken: self.transportToken) }
        let questions = try await guarded { try await self.api.pendingQuestionsForLive(transportToken: self.transportToken) }
        let permissions = try await guarded { try await self.api.pendingPermissionsForLive(transportToken: self.transportToken) }
        let text = final?.parts.filter(\.isText).compactMap(\.text).joined(separator: "\n\n")
        return CarLiveRoundSnapshot(
            assistantText: text,
            finalFinish: final != nil,
            openTools: openTools,
            childrenActive: children.contains { CarLiveStopJudge.isActive(map[$0.id]?.type) },
            pending: questions.contains { $0.sessionID == sessionID } || permissions.contains { $0.sessionID == sessionID },
            failed: final?.info.error != nil
        )
    }
}

struct CarLiveBinding: Codable, Equatable {
    var sessionID: String
    var messageID: String?
    var directory: String
    var model: String
}

struct CarLiveLease: Equatable {
    var hostID: UUID
    var generation: UInt64
    var contextKey: String
    var epoch: UInt64
    var ownerToken: String = ""
    var transportToken: UInt64 = 0
}

enum CarLiveLeaseCheck {
    static func allows(lease: CarLiveLease, hostID: UUID, generation: UInt64, contextMatches: Bool, connected: Bool, epoch: UInt64) -> Bool {
        connected && lease.hostID == hostID && lease.generation == generation && contextMatches && lease.epoch == epoch
    }
}
