import Foundation

nonisolated enum CarLiveArchiveTools {
    static let archiveJob = CarLiveHostedFunction.archiveJob
    static let unarchiveJob = CarLiveHostedFunction.unarchiveJob
    static let names = [archiveJob, unarchiveJob]
    static let maxNodes = 64
    static let maxDepth = 32

    static func requiredSessionID(_ object: [String: Any]) -> String? {
        guard let value = object["sessionID"] else { return nil }
        if value is NSNull { return nil }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isArchived(_ archived: Int?) -> Bool {
        guard let archived else { return false }
        return archived > 0
    }

    static func isUnarchived(_ archived: Int?) -> Bool {
        archived == nil || archived == 0
    }

    static func archiveMillis(now: Date = Date()) -> Int {
        let millis = Int((now.timeIntervalSince1970 * 1000).rounded(.towardZero))
        return millis > 0 ? millis : 1
    }

    static func outcome(
        ok: Bool,
        status: String,
        sessionID: String,
        title: String,
        archived: Bool,
        error: String? = nil,
        message: String? = nil,
        httpStatus: Int? = nil,
        snapshot: Bool? = nil
    ) -> String {
        var object: [String: Any] = [
            "ok": ok,
            "status": status,
            "sessionID": sessionID,
            "title": title,
            "archived": archived,
        ]
        if let error { object["error"] = error }
        if let message { object["message"] = message }
        if let httpStatus { object["http_status"] = httpStatus }
        if let snapshot { object["snapshot"] = snapshot }
        return CarLiveToolJSON.json(object)
    }

    static func ids(root: String, children: [String: [String]], parentFirst: Bool) -> [String] {
        var seen = Set<String>()
        func collect(_ id: String) -> [String] {
            if !seen.insert(id).inserted { return [] }
            let nested = (children[id] ?? []).flatMap(collect)
            return parentFirst ? [id] + nested : nested + [id]
        }
        return collect(root)
    }

    static func partial(
        sessionID: String,
        title: String,
        archived: Bool,
        verified: [String],
        failed: [String],
        pending: [String],
        error: String,
        message: String
    ) -> String {
        var verifiedIDs = verified
        var failedIDs = failed
        var pendingIDs = pending
        var truncated = false
        while true {
            let text = renderPartial(
                sessionID: sessionID,
                title: title,
                archived: archived,
                verified: verified.count,
                failed: failed.count,
                pending: pending.count,
                verifiedIDs: verifiedIDs,
                failedIDs: failedIDs,
                pendingIDs: pendingIDs,
                error: error,
                message: message,
                truncated: truncated
            )
            if text.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes { return text }
            if verifiedIDs.isEmpty, failedIDs.isEmpty, pendingIDs.isEmpty { return text }
            truncated = true
            if !pendingIDs.isEmpty {
                pendingIDs.removeLast()
            } else if !failedIDs.isEmpty {
                failedIDs.removeLast()
            } else {
                verifiedIDs.removeLast()
            }
        }
    }

    private static func renderPartial(
        sessionID: String,
        title: String,
        archived: Bool,
        verified: Int,
        failed: Int,
        pending: Int,
        verifiedIDs: [String],
        failedIDs: [String],
        pendingIDs: [String],
        error: String,
        message: String,
        truncated: Bool
    ) -> String {
        var object: [String: Any] = [
            "ok": false,
            "status": "partial",
            "error": error,
            "message": message,
            "sessionID": sessionID,
            "title": title,
            "archived": archived,
            "snapshot": true,
            "verified": verified,
            "failed": failed,
            "pending": pending,
            "verifiedIDs": verifiedIDs,
            "failedIDs": failedIDs,
            "pendingIDs": pendingIDs,
        ]
        if truncated { object["truncated"] = true }
        return CarLiveToolJSON.json(object)
    }
}

nonisolated enum CarLiveArchiveWire {
    static func body(archived: Int) throws -> Data {
        struct Body: Encodable {
            struct Time: Encodable {
                let archived: Int
            }

            let time: Time
        }
        return try JSONEncoder().encode(Body(time: .init(archived: archived)))
    }
}
