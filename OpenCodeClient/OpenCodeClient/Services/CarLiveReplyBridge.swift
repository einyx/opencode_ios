import Foundation

struct CarLiveReplyReservation: Sendable, Equatable {
    var token: String
    var sessionID: String
    var directory: String
    var userMessageID: String
    var title: String
    var isNewSession: Bool
}

enum CarLiveReplyEvent {
    static func sessionID(topLevel: String?, infoSessionID: String?) -> String? {
        let top = topLevel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !top.isEmpty { return top }
        let info = infoSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return info.isEmpty ? nil : info
    }

    static func isCompletion(_ info: [String: Any]?) -> Bool {
        guard let info else { return false }
        if let time = info["time"] as? [String: Any], completed(time["completed"]) { return true }
        guard let finish = info["finish"] as? String else { return false }
        return isTerminalFinish(finish)
    }

    private static func completed(_ value: Any?) -> Bool {
        if value == nil || value is NSNull { return false }
        return true
    }
}

enum CarLiveReplyCopy {
    static let limit = 2000

    static func render(title: String, sessionID: String, agent: String?, body: String) -> String {
        let session = clip(sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : sessionID, 64)
        var shown = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if shown.isEmpty { shown = session }
        shown = clip(shown, 80)
        let agentName = agent.flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : clip(trimmed, 40)
        }
        let full = assemble(title: shown, session: session, agent: agentName, body: body, truncated: false)
        if full.utf8.count <= limit { return full }
        let head = assemble(title: shown, session: session, agent: agentName, body: "", truncated: true)
        let clipped = clip(body, max(0, limit - head.utf8.count))
        let result = assemble(title: shown, session: session, agent: agentName, body: clipped, truncated: true)
        return result.utf8.count <= limit ? result : clip(result, limit)
    }

    static func clip(_ text: String, _ maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var used = 0
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            let bytes = String(scalar).utf8.count
            if used + bytes > maxBytes { break }
            used += bytes
            scalars.append(scalar)
        }
        var text = ""
        text.unicodeScalars.append(contentsOf: scalars)
        return text
    }

    private static func assemble(title: String, session: String, agent: String?, body: String, truncated: Bool) -> String {
        var lines = ["来源会话：\(title)", "来源编号：\(session)"]
        if let agent { lines.append("来源 agent：\(agent)") }
        if truncated { lines.append("正文已截断，详情见原会话") }
        return lines.joined(separator: "\n") + "\n新回复：\(body)"
    }
}

@MainActor
final class CarLiveReplyBridge {
    var requiresGatewayAcknowledgement = false
    var allows: (CarLiveLease) -> Bool = { _ in false }
    var page: (String, String?, String?, UInt64) async throws -> CarLiveMessagePage = { _, _, _, _ in
        throw CancellationError()
    }
    var status: (String?, UInt64) async throws -> [String: SessionStatus] = { _, _ in
        throw CancellationError()
    }
    var submit: (String, String, String) async -> Bool = { _, _, _ in false }
    var revision: () -> UInt64 = { 0 }
    var sleep: (Duration) async -> Void = { duration in
        try? await Task.sleep(for: duration)
    }

    private(set) var routedIdleCount = 0
    private(set) var routedUpdateCount = 0
    var subscribedSessionIDs: Set<String> { Set(subscriptions.keys) }

    private var generation: UInt64 = 0
    private var pendings: [String: Pending] = [:]
    private var subscriptions: [String: Subscription] = [:]
    private var deliveries: [String: Delivery] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]

    func reserve(_ reservation: CarLiveReplyReservation, lease: CarLiveLease) async {
        let sessionID = reservation.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let run = generation
        guard !sessionID.isEmpty, !reservation.token.isEmpty, generation == run, allows(lease) else { return }
        if let existing = subscriptions[sessionID], existing.lease == lease, allows(existing.lease) {
            guard generation == run, allows(lease) else { return }
            pendings[reservation.token] = Pending(reservation: normalized(reservation, sessionID: sessionID), lease: lease, baselineID: nil, baselineKnown: true, reuses: true, sawIdle: false)
            return
        }
        if reservation.isNewSession {
            guard generation == run, allows(lease) else { return }
            pendings[reservation.token] = Pending(reservation: normalized(reservation, sessionID: sessionID), lease: lease, baselineID: nil, baselineKnown: true, reuses: false, sawIdle: false)
            return
        }
        var baselineID: String?
        var known = false
        do {
            let first = try await page(sessionID, nil, directoryQuery(reservation.directory), lease.transportToken)
            guard generation == run, allows(lease) else { return }
            if !first.hasDecodeGaps {
                known = true
                baselineID = first.messages.last?.info.id
            }
        } catch {
            known = false
        }
        guard generation == run, allows(lease) else { return }
        pendings[reservation.token] = Pending(reservation: normalized(reservation, sessionID: sessionID), lease: lease, baselineID: baselineID, baselineKnown: known, reuses: false, sawIdle: false)
    }

    func rollback(_ token: String) {
        pendings.removeValue(forKey: token)
    }

    func accept(_ token: String) {
        guard let pending = pendings.removeValue(forKey: token), allows(pending.lease) else { return }
        let sessionID = pending.reservation.sessionID
        if pending.reuses {
            guard var existing = subscriptions[sessionID], existing.lease == pending.lease, allows(existing.lease) else { return }
            if !pending.reservation.title.isEmpty { existing.title = pending.reservation.title }
            existing.sawPreAcceptIdle = existing.sawPreAcceptIdle || pending.sawIdle
            existing.lease = pending.lease
            subscriptions[sessionID] = existing
        } else if var existing = subscriptions[sessionID], existing.lease == pending.lease {
            if !pending.reservation.title.isEmpty { existing.title = pending.reservation.title }
            existing.sawPreAcceptIdle = existing.sawPreAcceptIdle || pending.sawIdle
            subscriptions[sessionID] = existing
        } else {
            subscriptions[sessionID]?.task?.cancel()
            subscriptions[sessionID] = Subscription(
                sessionID: sessionID,
                directory: pending.reservation.directory,
                title: pending.reservation.title,
                lease: pending.lease,
                baselineID: pending.baselineID,
                baselineKnown: pending.baselineKnown,
                anchorUserID: pending.baselineKnown ? nil : pending.reservation.userMessageID,
                sawPreAcceptIdle: pending.sawIdle
            )
        }
        schedule(sessionID, reason: .accepted)
    }

    func noteExplicitIdle(sessionID: String) {
        routedIdleCount += 1
        let id = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        for (token, var pending) in pendings where pending.reservation.sessionID == id {
            pending.sawIdle = true
            pendings[token] = pending
        }
        guard var sub = subscriptions[id], allows(sub.lease), !sub.pausedHistory else { return }
        sub.idleOpen = true
        subscriptions[id] = sub
        schedule(id, reason: .idle)
    }

    func noteBusy(sessionID: String) {
        guard var sub = subscriptions[sessionID] else { return }
        sub.idleOpen = false
        subscriptions[sessionID] = sub
    }

    func noteMessageUpdated(sessionID: String) {
        routedUpdateCount += 1
        let id = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var sub = subscriptions[id], sub.idleOpen, allows(sub.lease), !sub.pausedHistory else { return }
        subscriptions[id] = sub
        schedule(id, reason: .completion)
    }

    func noteConnected() {
        let owned = subscriptions.values.filter { allows($0.lease) && !$0.pausedHistory }
        let groups = Dictionary(grouping: owned, by: \.directory)
        let run = generation
        for (directory, rows) in groups {
            guard let lease = rows.first?.lease else { continue }
            let ids = rows.map(\.sessionID)
            let id = UUID()
            let task = Task { [weak self] () -> Void in
                await self?.confirmReconnect(directory: directory, sessionIDs: ids, lease: lease, run: run)
                await self?.finishReconnect(id)
                return
            }
            reconnectTasks[id] = task
        }
    }

    private func finishReconnect(_ id: UUID) {
        reconnectTasks.removeValue(forKey: id)
    }

    func noteAppended(_ eventID: String) {
        guard var delivery = deliveries[eventID] else { return }
        guard let sub = subscriptions[delivery.sessionID], sub.lease.ownerToken == delivery.owner, allows(sub.lease) else { return }
        delivery.state = .injected
        deliveries[eventID] = delivery
        if var sub = subscriptions[delivery.sessionID] {
            sub.injected.formUnion(delivery.messageIDs)
            subscriptions[delivery.sessionID] = sub
        }
    }

    /// A Watch delivery exceeded its acknowledgement window. Release the
    /// boundary without claiming injection or replaying the spoken result.
    func noteUndelivered(_ eventID: String) {
        guard var delivery = deliveries[eventID], delivery.state == .submitted,
              var sub = subscriptions[delivery.sessionID],
              sub.lease.ownerToken == delivery.owner, allows(sub.lease) else { return }
        delivery.state = .failed
        deliveries[eventID] = delivery
        for id in delivery.messageIDs { sub.attempts[id] = 2 }
        subscriptions[delivery.sessionID] = sub
    }

    func invalidate() {
        generation &+= 1
        for sub in subscriptions.values { sub.task?.cancel() }
        subscriptions.removeAll()
        pendings.removeAll()
        deliveries.removeAll()
    }

    func invalidateIfOwner(_ owner: String) {
        let owners = Set(subscriptions.values.map(\.lease.ownerToken) + pendings.values.map(\.lease.ownerToken))
        guard owners.contains(owner), owners.allSatisfy({ $0 == owner }) else { return }
        invalidate()
    }

    func flush() async {
        for _ in 0..<8 {
            let tasks = subscriptions.values.compactMap(\.task) + Array(reconnectTasks.values)
            if tasks.isEmpty { return }
            for task in tasks { await task.value }
        }
    }

    private func normalized(_ reservation: CarLiveReplyReservation, sessionID: String) -> CarLiveReplyReservation {
        var copy = reservation
        copy.sessionID = sessionID
        return copy
    }

    private func directoryQuery(_ raw: String) -> String {
        raw
    }

    private func schedule(_ sessionID: String, reason: Reason) {
        guard var sub = subscriptions[sessionID], allows(sub.lease), !sub.pausedHistory else { return }
        sub.reasons.insert(reason)
        if sub.fetching {
            sub.dirty = true
            subscriptions[sessionID] = sub
            return
        }
        sub.fetching = true
        sub.fetchGeneration &+= 1
        let generation = sub.fetchGeneration
        let run = self.generation
        let task = Task { [weak self] () -> Void in
            await self?.runFetch(sessionID, generation: generation, run: run)
            return
        }
        sub.task = task
        subscriptions[sessionID] = sub
    }

    private func confirmReconnect(directory: String, sessionIDs: [String], lease: CarLiveLease, run: UInt64) async {
        let captured = revision()
        let map: [String: SessionStatus]
        do {
            map = try await status(directoryQuery(directory), lease.transportToken)
        } catch {
            return
        }
        guard generation == run, allows(lease), revision() == captured else { return }
        for id in sessionIDs {
            guard var sub = subscriptions[id], allows(sub.lease), generation == run else { continue }
            if let row = map[id] {
                if row.type == "busy" || row.type == "retry" || row.type != "idle" { continue }
            }
            sub.skipStatus = true
            subscriptions[id] = sub
            schedule(id, reason: .reconnect)
        }
    }

    private func runFetch(_ sessionID: String, generation: UInt64, run: UInt64) async {
        var rounds = 0
        while rounds < 3 {
            rounds += 1
            guard var sub = live(sessionID, generation: generation, run: run) else { return }
            let reasons = sub.reasons
            let skipStatus = sub.skipStatus
            sub.reasons = []
            sub.skipStatus = false
            sub.dirty = false
            subscriptions[sessionID] = sub
            var readMessages = true
            if !skipStatus && reasons.contains(.accepted) {
                let saw = subscriptions[sessionID]?.sawPreAcceptIdle == true
                let explicit = reasons.contains(.idle) || reasons.contains(.completion) || saw
                switch await confirmedIdle(sub, run: run) {
                case .idle:
                    readMessages = true
                case .busy:
                    readMessages = explicit
                case .failed, .stale, .unknown:
                    readMessages = explicit
                }
                if !readMessages {
                    if subscriptions[sessionID]?.dirty == true { continue }
                    finish(sessionID, generation: generation)
                    return
                }
            }
            guard live(sessionID, generation: generation, run: run) != nil else { return }
            await readAndSend(sessionID, generation: generation, run: run)
            guard let after = live(sessionID, generation: generation, run: run) else { return }
            if !after.dirty { break }
        }
        finish(sessionID, generation: generation)
    }

    private func finish(_ sessionID: String, generation: UInt64) {
        guard var sub = subscriptions[sessionID], sub.fetchGeneration == generation else { return }
        sub.fetching = false
        sub.task = nil
        sub.dirty = false
        subscriptions[sessionID] = sub
    }

    private func confirmedIdle(_ sub: Subscription, run: UInt64) async -> IdleCheck {
        let captured = revision()
        do {
            let map = try await status(directoryQuery(sub.directory), sub.lease.transportToken)
            guard generation == run, allows(sub.lease), revision() == captured else { return .stale }
            guard let row = map[sub.sessionID] else { return .idle }
            if row.type == "busy" || row.type == "retry" { return .busy }
            if row.type == "idle" { return .idle }
            return .unknown
        } catch {
            return .failed
        }
    }

    private func readAndSend(_ sessionID: String, generation: UInt64, run: UInt64) async {
        var backoff = 0
        while true {
            guard let sub = live(sessionID, generation: generation, run: run) else { return }
            if sub.pausedHistory { return }
            let collected: Collected
            do {
                collected = try await collect(sub, run: run)
            } catch {
                return
            }
            guard var current = live(sessionID, generation: generation, run: run) else { return }
            if collected.gap { return }
            if collected.missingBoundary {
                current.pausedHistory = true
                current.idleOpen = false
                subscriptions[sessionID] = current
                return
            }
            if !collected.ready.isEmpty {
                current.idleOpen = collected.incomplete || collected.awaitingBody
                subscriptions[sessionID] = current
                await send(collected.ready, sessionID: sessionID, generation: generation, run: run)
                advanceBoundary(collected.messages, sessionID: sessionID, generation: generation, run: run)
                return
            }
            if collected.incomplete || collected.awaitingBody {
                current.idleOpen = true
                subscriptions[sessionID] = current
                advanceBoundary(collected.messages, sessionID: sessionID, generation: generation, run: run)
                if backoff >= 2 { return }
                backoff += 1
                await sleep(backoff == 1 ? .milliseconds(250) : .milliseconds(750))
                guard live(sessionID, generation: generation, run: run) != nil else { return }
                continue
            }
            advanceBoundary(collected.messages, sessionID: sessionID, generation: generation, run: run)
            guard var settled = live(sessionID, generation: generation, run: run) else { return }
            settled.idleOpen = false
            subscriptions[sessionID] = settled
            return
        }
    }

    private func collect(_ sub: Subscription, run: UInt64) async throws -> Collected {
        var combined: [MessageWithParts] = []
        var seen = Set<String>()
        var before: String? = nil
        var cursors = Set<String>()
        for _ in 0..<5 {
            guard generation == run, allows(sub.lease) else { throw CancellationError() }
            let next = try await page(sub.sessionID, before, directoryQuery(sub.directory), sub.lease.transportToken)
            guard generation == run, allows(sub.lease) else { throw CancellationError() }
            if next.hasDecodeGaps { return Collected(ready: [], incomplete: false, gap: true, missingBoundary: false, awaitingBody: false, messages: []) }
            var older: [MessageWithParts] = []
            for row in next.messages where seen.insert(row.info.id).inserted {
                older.append(row)
            }
            combined = older + combined
            if boundaryFound(sub, in: combined) { break }
            guard let cursor = next.nextCursor, cursors.insert(cursor).inserted else { break }
            before = cursor
        }
        let selected = select(combined, sub: sub)
        return Collected(ready: selected.ready, incomplete: selected.incomplete, gap: false, missingBoundary: selected.missingBoundary, awaitingBody: selected.awaitingBody, messages: combined)
    }

    private func boundaryFound(_ sub: Subscription, in messages: [MessageWithParts]) -> Bool {
        if sub.baselineKnown {
            guard let id = sub.baselineID, !id.isEmpty else { return true }
            return messages.contains { $0.info.id == id }
        }
        guard let anchor = sub.anchorUserID, !anchor.isEmpty else { return false }
        return messages.contains { $0.info.id == anchor }
    }

    private func select(_ messages: [MessageWithParts], sub: Subscription) -> (ready: [Candidate], incomplete: Bool, missingBoundary: Bool, awaitingBody: Bool) {
        guard let start = scanStart(messages, sub: sub) else { return ([], false, true, false) }
        var ready: [Candidate] = []
        var incomplete = false
        var awaitingBody = false
        for row in messages[start...] {
            if handled(row.info.id, sub: sub) || inFlight(row.info.id) { continue }
            guard let body = assistantBody(row) else {
                if row.info.role == "assistant" && !isToolCall(row) { awaitingBody = true }
                continue
            }
            if !isComplete(row) {
                incomplete = true
                continue
            }
            ready.append(Candidate(id: row.info.id, text: body, agent: row.info.agent))
        }
        if ready.isEmpty && !incomplete && !awaitingBody {
            let rest = messages[start...]
            let pending = rest.contains { !handled($0.info.id, sub: sub) && !inFlight($0.info.id) }
            if pending || (rest.isEmpty && sub.idleOpen) {
                awaitingBody = true
            }
        }
        return (ready, incomplete, false, awaitingBody)
    }

    private func advanceBoundary(_ messages: [MessageWithParts], sessionID: String, generation: UInt64, run: UInt64) {
        guard var current = live(sessionID, generation: generation, run: run) else { return }
        guard let start = scanStart(messages, sub: current) else { return }
        var advanceTo: String?
        for row in messages[start...] {
            guard canCross(row, sub: current) else { break }
            advanceTo = row.info.id
        }
        guard let advanceTo, !advanceTo.isEmpty, advanceTo != current.baselineID else { return }
        current.baselineID = advanceTo
        current.baselineKnown = true
        current.anchorUserID = nil
        subscriptions[sessionID] = current
    }

    private func scanStart(_ messages: [MessageWithParts], sub: Subscription) -> Int? {
        if sub.baselineKnown {
            if let id = sub.baselineID, !id.isEmpty {
                guard let index = messages.firstIndex(where: { $0.info.id == id }) else { return nil }
                return messages.index(after: index)
            }
            return messages.startIndex
        }
        guard let anchor = sub.anchorUserID, !anchor.isEmpty, let index = messages.firstIndex(where: { $0.info.id == anchor }) else { return nil }
        return messages.index(after: index)
    }

    private func canCross(_ row: MessageWithParts, sub: Subscription) -> Bool {
        if handled(row.info.id, sub: sub) { return true }
        guard row.info.role == "assistant" else { return true }
        if isToolCall(row) { return true }
        return false
    }

    private func handled(_ messageID: String, sub: Subscription) -> Bool {
        if sub.injected.contains(messageID) || confirmedDelivery(messageID) { return true }
        return (sub.attempts[messageID] ?? 0) >= 2
    }

    private func send(_ ready: [Candidate], sessionID: String, generation: UInt64, run: UInt64) async {
        for candidate in ready {
            guard let sub = live(sessionID, generation: generation, run: run) else { return }
            if sub.injected.contains(candidate.id) || inFlight(candidate.id) { continue }
            let eventID = "reply-" + String(UUID().uuidString.prefix(12))
            let text = CarLiveReplyCopy.render(title: sub.title, sessionID: sessionID, agent: candidate.agent, body: candidate.text)
            deliveries[eventID] = Delivery(eventID: eventID, sessionID: sessionID, messageIDs: [candidate.id], owner: sub.lease.ownerToken, state: .sending)
            let ok = await submit(text, eventID, sub.lease.ownerToken)
            guard var current = live(sessionID, generation: generation, run: run) else { return }
            if deliveries[eventID]?.state == .injected {
                current.injected.insert(candidate.id)
                subscriptions[sessionID] = current
                continue
            }
            if var delivery = deliveries[eventID] {
                if ok {
                    delivery.state = .submitted
                } else {
                    delivery.state = .failed
                    current.attempts[candidate.id, default: 0] += 1
                }
                deliveries[eventID] = delivery
            }
            subscriptions[sessionID] = current
        }
    }

    private func inFlight(_ messageID: String) -> Bool {
        deliveries.values.contains { delivery in
            delivery.messageIDs.contains(messageID) && (delivery.state == .sending || delivery.state == .submitted || delivery.state == .injected)
        }
    }

    private func confirmedDelivery(_ messageID: String) -> Bool {
        deliveries.values.contains { delivery in
            delivery.messageIDs.contains(messageID) &&
                (delivery.state == .injected || (!requiresGatewayAcknowledgement && delivery.state == .submitted))
        }
    }

    private func isToolCall(_ row: MessageWithParts) -> Bool {
        row.info.finish == "tool-calls" || row.info.finish == "tool_calls"
    }

    private func assistantBody(_ row: MessageWithParts) -> String? {
        guard row.info.role == "assistant" else { return nil }
        if row.info.finish == "tool-calls" || row.info.finish == "tool_calls" { return nil }
        let text = row.parts.filter { $0.isText && $0.synthetic != true }.compactMap(\.text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private func isComplete(_ row: MessageWithParts) -> Bool {
        if row.info.time.completed != nil { return true }
        guard let finish = row.info.finish else { return false }
        return isTerminalFinish(finish)
    }

    private func live(_ sessionID: String, generation: UInt64, run: UInt64) -> Subscription? {
        guard self.generation == run else { return nil }
        guard let sub = subscriptions[sessionID], sub.fetchGeneration == generation, allows(sub.lease) else { return nil }
        return sub
    }
}

private enum Reason: Hashable {
    case accepted
    case idle
    case completion
    case reconnect
}

private enum IdleCheck {
    case idle
    case busy
    case failed
    case stale
    case unknown
}

private struct Pending {
    var reservation: CarLiveReplyReservation
    var lease: CarLiveLease
    var baselineID: String?
    var baselineKnown: Bool
    var reuses: Bool
    var sawIdle: Bool
}

private struct Subscription {
    var sessionID: String
    var directory: String
    var title: String
    var lease: CarLiveLease
    var baselineID: String?
    var baselineKnown: Bool
    var anchorUserID: String?
    var sawPreAcceptIdle = false
    var pausedHistory = false
    var idleOpen = false
    var fetching = false
    var dirty = false
    var skipStatus = false
    var fetchGeneration: UInt64 = 0
    var reasons: Set<Reason> = []
    var injected: Set<String> = []
    var attempts: [String: Int] = [:]
    var task: Task<Void, Never>?
}

private struct Delivery {
    var eventID: String
    var sessionID: String
    var messageIDs: [String]
    var owner: String
    var state: State

    enum State {
        case sending
        case submitted
        case injected
        case failed
    }
}

private struct Candidate {
    var id: String
    var text: String
    var agent: String?
}

private struct Collected {
    var ready: [Candidate]
    var incomplete: Bool
    var gap: Bool
    var missingBoundary: Bool
    var awaitingBody: Bool
    var messages: [MessageWithParts]
}

private func isTerminalFinish(_ finish: String) -> Bool {
    !finish.isEmpty && finish != "unknown" && finish != "tool-calls" && finish != "tool_calls"
}
