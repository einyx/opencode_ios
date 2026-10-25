#if os(iOS)
import Foundation
import UIKit
import WatchConnectivity

@MainActor
private final class WatchConnectionWaiter {
    var continuation: CheckedContinuation<Bool, Never>?
    var operation: Task<Void, Never>?
    var deadline: Task<Void, Never>?
    func finish(_ connected: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        operation?.cancel()
        deadline?.cancel()
        operation = nil
        deadline = nil
        continuation.resume(returning: connected)
    }
}

@MainActor
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    private struct Commentary {
        let text: String
        let order: UInt64
        var firstOffered: Date?
    }
    weak var state: AppState?
    private(set) var lease: CarLiveLease?
    private var client: APIClient?
    private var ledger = WatchCallLedger()
    private var binding: CarLiveBinding?
    private var lastContact = Date.distantPast
    private var calls: [String: Task<Void, Never>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var comments: [String: Commentary] = [:]
    private var commentaryOrder: UInt64 = 0
    private var expiry: Task<Void, Never>?
    private var replies = CarLiveReplyBridge()
    private var beginning: String?
    private var readOnly = false
    private var directory: String?
    private var agent = "build"
    private let makeClient: (APIClient) async -> APIClient
    #if DEBUG
    private var debugEvents: [[String: Any]] = []
    #endif

    init(makeClient: @escaping (APIClient) async -> APIClient = { $0.makeWatchClient() }) {
        self.makeClient = makeClient
        super.init()
    }

    var isActive: Bool { lease != nil && Date().timeIntervalSince(lastContact) < WatchBridgeWire.maxRunSeconds }

    func activate(state: AppState) {
        self.state = state
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        probeState("activating")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("WATCH_PHONE_BRIDGE_PROBE") {
            Task { await self.runBridgeProbe() }
        }
        #endif
    }

    func invalidate() {
        client?.cancelWatchRequests()
        client = nil
        lease = nil
        beginning = nil
        calls.values.forEach { $0.cancel() }
        deadlines.values.forEach { $0.cancel() }
        calls.removeAll()
        deadlines.removeAll()
        comments.removeAll()
        binding = nil
        directory = nil
        replies.invalidate()
        expiry?.cancel()
        expiry = nil
    }

    private func allowed(_ owned: CarLiveLease) -> Bool {
        guard let state, lease == owned else { return false }
        return isActive && state.currentHostProfileID == owned.hostID &&
            state.hostRequestGeneration == owned.generation && state.carContextKey == owned.contextKey
    }

    private func touch() {
        lastContact = Date()
        expiry?.cancel()
        let owner = lease?.ownerToken
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WatchBridgeWire.maxRunSeconds))
            guard !Task.isCancelled, let self, self.lease?.ownerToken == owner else { return }
            self.invalidate()
            self.cleanupBackgroundConnection()
        }
    }

    private func cleanupBackgroundConnection() {
        guard let state, state.backgroundVoiceScene == .background,
              state.carLive?.phase != .listening, state.carLive?.phase != .speaking else { return }
        state.applyBackgroundDisconnect()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor [weak self] in self?.probeState(error == nil ? "activated" : "activation_failed") }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.invalidate()
            self?.cleanupBackgroundConnection()
            session.activate()
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        // WC delivers property-list values; no payload is persisted or logged.
        Task { @MainActor [weak self] in
            guard let self else { replyHandler(WatchBridgeWire.error("unreachable")); return }
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "Watch tool bridge")
            let started = Date()
            self.probeEvent("received", message: message)
            let result = await self.handle(message)
            self.probeEvent("reply", message: message, response: result, elapsed: Date().timeIntervalSince(started))
            self.probeState(result["error"] as? String ?? "replied")
            replyHandler(result)
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }

    private func probeEvent(_ stage: String, message: [String: Any] = [:], response: [String: Any] = [:], elapsed: TimeInterval = 0) {
        #if DEBUG
        let operations = ["begin", "end", "tool", "result", "pull", "ack", "commentary", "commentaryAck"]
        let statuses = ["pending", "ready", "unknown"]
        let codes = ["unreachable", "stale_context", "busy", "limit", "bad_arguments", "protocol", "missing_chunk", "missing_call", "call_conflict", "read_only_probe", "failed", "needs_input", "lookup_failed"]
        let op = message["op"] as? String ?? "none"
        let name = message["name"] as? String ?? "none"
        let status = response["status"] as? String ?? "none"
        let code = response["error"] as? String ?? "none"
        debugEvents.append(["stage": stage, "time": Date().timeIntervalSince1970,
            "op": operations.contains(op) ? op : "none",
            "tool": CarLiveToolName.native.contains(name) ? name : "none",
            "status": statuses.contains(status) ? status : "none",
            "error": code == "none" || codes.contains(code) ? code : "other",
            "elapsedMS": Int(elapsed * 1000), "bytes": response["bytes"] as? Int ?? 0,
            "dataBytes": (response["data"] as? Data)?.count ?? 0,
            "allowed": lease.map { allowed($0) } ?? false])
        debugEvents = Array(debugEvents.suffix(64))
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: debugEvents, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("watch-bridge-events.json"), options: .atomic)
        }
        #endif
    }

    #if DEBUG
    private func runBridgeProbe() async {
        // Same phone handler/ledger as WC, but no microphone or gateway session.
        try? await Task.sleep(for: .seconds(1))
        let owner = UUID().uuidString
        let call = UUID().uuidString
        var begin = WatchBridgeWire.envelope("begin", run: owner)
        begin["readOnly"] = true
        let setup = await handle(begin)
        var metadata: [String: Any] = ["probe": ProcessInfo.processInfo.environment["WATCH_PROBE_ID"] ?? "phone", "time": Date().timeIntervalSince1970]
        if let error = setup["error"] as? String {
            metadata["error"] = ["busy", "unreachable", "stale_context", "already_started"].contains(error) ? error : "other"
        } else {
            var message = WatchBridgeWire.envelope("tool", run: owner, call: call)
            message["name"] = CarLiveToolName.queryJobs
            message["arguments"] = "{\"queryScope\":\"recent\",\"archivedOnly\":false,\"skip\":0,\"count\":1}"
            var header = await handle(message)
            for _ in 0..<70 {
                if header["status"] as? String != "pending" { break }
                try? await Task.sleep(for: .milliseconds(300))
                header = await handle(WatchBridgeWire.envelope("result", run: owner, call: call))
            }
            let status = header["status"] as? String ?? "other"
            metadata["status"] = ["pending", "ready", "unknown"].contains(status) ? status : "other"
            if status == "ready", let chunks = header["chunks"] as? Int, (0...8).contains(chunks) {
                var output = Data()
                for sequence in 0..<chunks {
                    var pull = WatchBridgeWire.envelope("pull", run: owner, call: call)
                    pull["seq"] = sequence
                    if let data = await handle(pull)["data"] as? Data { output.append(data) }
                }
                metadata["bytes"] = output.count
                metadata["verified"] = output.count == header["bytes"] as? Int && WatchBridgeWire.digest(output) == header["sha256"] as? String
                let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any]
                metadata["toolOK"] = object?["ok"] as? Bool ?? false
            }
            _ = await handle(WatchBridgeWire.envelope("end", run: owner))
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-phone-probe.json")
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif

    private func probeState(_ stage: String) {
        #if DEBUG
        let session = WCSession.default
        let metadata: [String: Any] = ["stage": stage, "activated": session.activationState == .activated,
            "paired": session.isPaired, "installed": session.isWatchAppInstalled, "reachable": session.isReachable]
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("watch-bridge-state.json"), options: .atomic)
        }
        #endif
    }

    func handle(_ message: [String: Any]) async -> [String: Any] {
        guard message["v"] as? Int == WatchBridgeWire.version,
              let op = message["op"] as? String else { return WatchBridgeWire.error("protocol") }
        if op == "begin" { return await begin(message) }
        guard let run = message["run"] as? String, let owned = lease,
              run == owned.ownerToken, allowed(owned) else { return WatchBridgeWire.error("stale_context") }
        touch()
        if op == "end" {
            invalidate()
            cleanupBackgroundConnection()
            return ["ok": true]
        }
        let call = message["call"] as? String ?? ""
        switch op {
        case "tool":
            guard let name = message["name"] as? String, CarLiveToolName.native.contains(name),
                  let arguments = message["arguments"] as? String,
                  arguments.utf8.count <= WatchBridgeWire.maxArgumentsBytes else { return WatchBridgeWire.error("bad_arguments") }
            if readOnly, name != CarLiveToolName.queryJobs, name != CarLiveToolName.getSessionMessages {
                return WatchBridgeWire.error("read_only_probe")
            }
            let claim = ledger.claim(id: call, name: name, arguments: arguments)
            if claim == "duplicate" { return ledger.header(id: call) }
            guard claim == "accepted" else { return WatchBridgeWire.error(claim) }
            launchTool(id: call, name: name, arguments: arguments, owned: owned)
            return ["status": "pending"]
        case "result": return ledger.header(id: call)
        case "pull":
            guard let seq = message["seq"] as? Int, seq >= 0, seq < 8,
                  let data = ledger.chunk(id: call, sequence: seq) else { return WatchBridgeWire.error("missing_chunk") }
            return ["run": run, "call": call, "seq": seq, "data": data]
        case "ack":
            ledger.acknowledge(id: call, digest: message["sha256"] as? String ?? "")
            return ["ok": true]
        case "commentary":
            guard await ensureConnection(owned), allowed(owned) else { return WatchBridgeWire.error("unreachable") }
            replies.noteConnected()
            let now = Date()
            for event in comments.keys.sorted(by: { comments[$0]!.order < comments[$1]!.order }) {
                guard var comment = comments[event] else { continue }
                if let offered = comment.firstOffered, now.timeIntervalSince(offered) >= 8 {
                    comments.removeValue(forKey: event)
                    replies.noteUndelivered(event)
                    continue
                }
                comment.firstOffered = comment.firstOffered ?? now
                comments[event] = comment
                return ["run": run, "event": event, "text": comment.text]
            }
            return ["run": run, "ok": true]
        case "commentaryAck":
            if let event = message["event"] as? String, comments.removeValue(forKey: event) != nil {
                replies.noteAppended(event)
            }
            return ["ok": true]
        default: return WatchBridgeWire.error("protocol")
        }
    }

    private func begin(_ message: [String: Any]) async -> [String: Any] {
        guard let state, let id = message["run"] as? String, WatchBridgeWire.validID(id) else {
            return WatchBridgeWire.error("bad_arguments")
        }
        // A repeated begin must never replace an already running voice owner.
        if lease?.ownerToken == id { return WatchBridgeWire.error("already_started") }
        guard beginning == nil else { return WatchBridgeWire.error("busy") }
        if isActive, let previous = lease?.ownerToken {
            guard message["replacing"] as? String == previous else {
                var response = WatchBridgeWire.error("busy")
                response["activeRun"] = previous
                return response
            }
        }
        invalidate()
        beginning = id
        let host = state.captureHostRequestSnapshot()
        let context = state.carContextKey
        let snapshotDirectory = state.effectiveProjectDirectory
        let snapshotAgent = state.selectedAgentName
        guard let source = state.apiClient as? APIClient else {
            beginning = nil
            return WatchBridgeWire.error("unreachable")
        }
        // Credentials are copied only inside the phone, never into the WC host payload.
        await state.finishHostTransportConfiguration()
        let sibling = await makeClient(source)
        guard beginning == id, state.isCurrentHostRequest(host), state.carContextKey == context else {
            sibling.cancelWatchRequests()
            return WatchBridgeWire.error("stale_context")
        }
        client = sibling
        let token = await sibling.armLiveTransport()
        guard beginning == id, state.isCurrentHostRequest(host), state.carContextKey == context else {
            sibling.cancelWatchRequests()
            return WatchBridgeWire.error("stale_context")
        }
        let owned = CarLiveLease(hostID: host.hostProfileID, generation: host.generation, contextKey: context,
                                 epoch: 1, ownerToken: id, transportToken: token)
        lease = owned
        directory = snapshotDirectory
        agent = snapshotAgent
        beginning = nil
        ledger = WatchCallLedger()
        readOnly = message["readOnly"] as? Bool ?? false
        touch()
        guard await beginConnection(owned), allowed(owned),
              let portal = URL(string: state.aiBuilderBaseURL), portal.scheme == "https",
              !state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if lease == owned { invalidate() }
            return WatchBridgeWire.error("unreachable")
        }
        setupReplies(owned: owned, client: sibling)
        return ["run": id, "portal": portal.absoluteString, "token": state.aiBuilderToken]
    }

    private func ensureConnection(_ owned: CarLiveLease) async -> Bool {
        guard allowed(owned), let state, let client else { return false }
        if state.sshTunnelManager.config.isEnabled, state.sshTunnelManager.status != .connected {
            await state.sshTunnelManager.connect()
        }
        guard allowed(owned) else { return false }
        do {
            let health = try await client.health()
            return allowed(owned) && health.healthy
        } catch { return false }
    }

    private func beginConnection(_ owned: CarLiveLease) async -> Bool {
        // Do not use a task group here: a non-cooperative SSH connect must not
        // delay the timeout reply while the group waits for cancelled children.
        let waiter = WatchConnectionWaiter()
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            waiter.operation = Task { [weak self] in
                let connected = await self?.ensureConnection(owned) ?? false
                waiter.finish(connected)
            }
            waiter.deadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                if self?.lease == owned { self?.invalidate() }
                waiter.finish(false)
            }
        }
    }

    private func launchTool(id: String, name: String, arguments: String, owned: CarLiveLease) {
        let backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Watch OpenCode request")
        deadlines[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.lease == owned,
                  self.ledger.records[id]?.finished == false else { return }
            self.ledger.markUnknown(id: id)
            self.probeEvent("tool_deadline")
            self.calls[id]?.cancel()
        }
        calls[id] = Task { [weak self] in
            defer { if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) } }
            guard let self else { return }
            defer {
                if self.lease == owned {
                    self.deadlines.removeValue(forKey: id)?.cancel()
                    self.calls.removeValue(forKey: id)
                }
            }
            let result = await self.execute(name: name, arguments: arguments, owned: owned)
            #if DEBUG
            let resultMetadata = (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any] ?? [:]
            self.probeEvent("tool_finished", response: resultMetadata)
            #endif
            guard self.allowed(owned), !Task.isCancelled else { return }
            self.ledger.finish(id: id, output: result)
        }
    }

    private func execute(name: String, arguments: String, owned: CarLiveLease) async -> String {
        guard await ensureConnection(owned), allowed(owned), let client else {
            return CarLiveToolJSON.error(code: "unreachable", message: "手机不可达")
        }
        if name == CarLiveToolName.answerPending {
            return await answerPending(arguments, owned: owned, client: client)
        }
        let box = CarLiveAPIBox(client)
        await box.bindOwner { [weak self] in await self?.allowed(owned) ?? false }
        await box.bindTransport(owned.transportToken)
        let context = CarLiveToolContext(trackedSessionID: binding?.sessionID,
            directory: directory, startAgent: agent,
            allows: { [weak self] in await self?.allowed(owned) ?? false },
            reserveReply: { [weak self] reservation in await self?.replies.reserve(reservation, lease: owned) },
            rollbackReply: { [weak self] token in self?.replies.rollback(token) })
        let effect = await CarLiveToolHandler.run(name, arguments: arguments, client: box, context: context)
        guard allowed(owned), !Task.isCancelled else { return CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭") }
        if effect.clearSessionID == binding?.sessionID { binding = nil }
        if effect.poll, let sessionID = effect.sessionID {
            binding = CarLiveBinding(sessionID: sessionID, messageID: effect.messageID,
                                     directory: effect.directory ?? "", model: effect.model ?? "")
            if let token = effect.prepareToken { replies.accept(token) }
        }
        return effect.output
    }

    private func setupReplies(owned: CarLiveLease, client: APIClient) {
        replies.requiresGatewayAcknowledgement = true
        replies.allows = { [weak self] in self?.allowed($0) ?? false }
        replies.page = { session, before, directory, token in
            try await client.messagePageForLive(sessionID: session, limit: 100, before: before, directory: directory, transportToken: token)
        }
        replies.status = { directory, token in try await client.sessionStatusForLive(directory: directory, transportToken: token) }
        replies.submit = { [weak self] text, event, owner in
            guard let self, self.allowed(owned), owner == owned.ownerToken, self.comments.count < 32 else { return false }
            self.commentaryOrder &+= 1
            self.comments[event] = Commentary(text: text, order: self.commentaryOrder)
            return true
        }
    }

    private func answerPending(_ arguments: String, owned: CarLiveLease, client: APIClient) async -> String {
        guard let sessionID = binding?.sessionID,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CarLiveToolJSON.error(code: "needs_input", message: "请在手机处理")
        }
        let reply = object["permissionReply"] as? String
        guard reply == nil || reply == "once" || reply == "reject" else {
            return CarLiveToolJSON.error(code: "bad_arguments", message: "请在手机处理")
        }
        do {
            let permissions = try await client.pendingPermissionsForLive(transportToken: owned.transportToken).filter { $0.sessionID == sessionID }
            guard allowed(owned) else { throw CancellationError() }
            if let request = permissions.first {
                guard let reply else { return CarLiveToolJSON.error(code: "needs_input", message: "请在手机处理") }
                try await client.respondPermissionForLive(sessionID: sessionID, permissionID: request.id,
                    response: reply == "reject" ? .reject : .once, transportToken: owned.transportToken)
                let remaining = try await client.pendingPermissionsForLive(transportToken: owned.transportToken)
                guard allowed(owned), !remaining.contains(where: { $0.id == request.id }) else {
                    return CarLiveToolJSON.error(code: "not_confirmed", message: "请在手机处理")
                }
            } else {
                let questions = try await client.pendingQuestionsForLive(transportToken: owned.transportToken)
                let answers = object["answers"] as? [[String]] ?? []
                guard allowed(owned), let request = questions.first(where: { $0.sessionID == sessionID }), !answers.isEmpty else {
                    return CarLiveToolJSON.error(code: "needs_input", message: "请在手机处理")
                }
                try await client.replyQuestionForLive(requestID: request.id, answers: answers, transportToken: owned.transportToken)
                let remaining = try await client.pendingQuestionsForLive(transportToken: owned.transportToken)
                guard allowed(owned), !remaining.contains(where: { $0.id == request.id }) else {
                    return CarLiveToolJSON.error(code: "not_confirmed", message: "请在手机处理")
                }
            }
            return CarLiveToolJSON.accepted(sessionID: sessionID, messageID: "", model: nil)
        } catch { return CarLiveToolJSON.error(code: "not_confirmed", message: "请在手机处理") }
    }
}

extension AppState {
    func activateWatchBridge() {
        guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }), apiClient is APIClient else { return }
        if watchPhoneBridge == nil { watchPhoneBridge = WatchPhoneBridge() }
        watchPhoneBridge?.activate(state: self)
    }
}
#endif
