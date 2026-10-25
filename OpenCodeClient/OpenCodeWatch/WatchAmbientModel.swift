import Foundation
import Observation
import WatchConnectivity
import WatchKit

private enum WatchBridgeError: Error { case unreachable, timeout, protocolError, remote(String), busy(String) }

@MainActor
private final class WatchRequestWaiter {
    var continuation: CheckedContinuation<[String: Any], Error>?
    var timeout: Task<Void, Never>?
    func finish(_ result: sending Result<[String: Any], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}

@MainActor
@Observable
final class WatchAmbientModel: NSObject, WCSessionDelegate {
    let live = CarLiveController(audioSendTimeout: 5)
    var connecting = false
    var error: String?
    var bridgeStatus = ""
    private var run = ""
    private var poll: Task<Void, Never>?
    private var submittedEvents: Set<String> = []
    private var pendingCommentaryAcks: Set<String> = []
    private var fixture = false
    private var didActivate = false
    private var lastWCErrorCode = 0
    var phase: CarLivePhase { fixture ? .listening : live.phase }

    var status: String {
        if fixture { return "正在听" }
        if connecting { return "连接中…" }
        switch live.phase {
        case .listening: return live.isMuted ? "已静音" : "正在听"
        case .speaking: return "正在播报，轻点打断"
        case .closing: return "正在结束语音"
        case .failed: return "语音连接已断开"
        default: return bridgeStatus.isEmpty ? "开始语音" : bridgeStatus
        }
    }
    var latestCaption: String {
        if fixture { return "已交给手机继续处理" }
        return live.captions.last?.text ?? ""
    }

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("WATCH_UI_FIXTURE") { fixture = true; return }
        #endif
        WCSession.default.delegate = self
        WCSession.default.activate()
        live.toolExecutor = { [weak self] call in
            guard let self else { return CarLiveToolResult(output: CarLiveWire.errorOutput(code: "closed", message: "语音已关闭")) }
            return await self.execute(call)
        }
        live.onCommentaryAppended = { [weak self] event in
            guard let self, !self.run.isEmpty else { return }
            let owner = self.run
            self.pendingCommentaryAcks.insert(event)
            Task {
                var request = WatchBridgeWire.envelope("commentaryAck", run: owner)
                request["event"] = event
                if (try? await self.request(request)) != nil, self.run == owner {
                    self.pendingCommentaryAcks.remove(event)
                }
            }
        }
        live.onLiveEnded = { [weak self] _ in
            guard let self else { return }
            let owner = self.live.sessionOwnerForPolicy
            guard !owner.isEmpty, self.run == owner else { return }
            Task {
                guard self.run == owner else { return }
                await self.stop()
            }
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("WATCH_BRIDGE_PROBE") || arguments.contains("WATCH_LIVE_PROBE") {
            Task { await self.runProbe(audio: arguments.contains("WATCH_LIVE_PROBE")) }
        }
        #endif
    }

    func start(readOnly: Bool = false) async {
        guard run.isEmpty, !connecting, live.phase != .closing else { return }
        let owner = UUID().uuidString
        run = owner
        connecting = true
        error = nil
        submittedEvents.removeAll()
        pendingCommentaryAcks.removeAll()
        do {
            var begin = WatchBridgeWire.envelope("begin", run: owner)
            begin["readOnly"] = readOnly
            let setup: [String: Any]
            do {
                setup = try await request(begin)
            } catch WatchBridgeError.busy(let previous) {
                guard run == owner, !Task.isCancelled else { throw CancellationError() }
                // The user explicitly started a new local voice session. Replace
                // only the exact leftover lease reported by the paired phone.
                begin["replacing"] = previous
                setup = try await request(begin)
            }
            guard run == owner else { await end(owner); return }
            guard setup["run"] as? String == owner,
                  let raw = setup["portal"] as? String, let portal = URL(string: raw), portal.scheme == "https",
                  let token = setup["token"] as? String, !token.isEmpty else { throw WatchBridgeError.protocolError }
            let instructions = "你是用户手腕上的 Ambient 语音入口。回答简短，适合听，不念会话编号、路径或凭据。工具经配对 iPhone 执行。结束语音不停止后台工作，不承诺结束后通知。" + (readOnly ? "本轮验收只允许 query_jobs 和 get_session_messages，不执行任何写操作。" : "")
            let backend = CarLiveProtocol.backendInstructions.replacingOccurrences(of: "iPhone 上", with: "Apple Watch 上")
            let config = CarLiveConfiguration(portalBaseURL: portal, builderToken: token,
                instructions: instructions, backendInstructions: backend, ownerToken: owner)
            await live.start(configuration: config)
            guard run == owner else { return }
            connecting = false
            guard live.phase == .listening || live.phase == .speaking else {
                await end(owner)
                if run == owner { run = "" }
                return
            }
            WKInterfaceDevice.current().play(.start)
            startPoll(owner)
        } catch {
            if run == owner {
                if case WatchBridgeError.unreachable = error {
                    self.error = "手机不可达，请先在 iPhone 打开 OpenCode"
                } else {
                    // A reply such as busy or a phone-side health failure is
                    // evidence that the companion was reached, not unreachable.
                    self.error = CarLiveCopy.notReady
                }
                connecting = false
                run = ""
            }
            await end(owner)
        }
    }

    func stop() async {
        let owner = run
        run = ""
        connecting = false
        poll?.cancel()
        poll = nil
        submittedEvents.removeAll()
        pendingCommentaryAcks.removeAll()
        await live.stop()
        await end(owner)
        bridgeStatus = "语音已结束，后台工作仍在继续"
    }

    private func end(_ owner: String) async {
        guard !owner.isEmpty else { return }
        _ = try? await request(WatchBridgeWire.envelope("end", run: owner))
    }

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        // Activation is asynchronous, including immediately after the first tap.
        // sendMessage from watchOS can wake the companion; isReachable is only a
        // snapshot and must not prevent that attempt.
        for _ in 0..<20 {
            if WCSession.default.activationState == .activated { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try Task.checkCancellation()
        guard WCSession.default.activationState == .activated else {
            throw WatchBridgeError.unreachable
        }
        let waiter = WatchRequestWaiter()
        lastWCErrorCode = 0
        // Beginning may include a cold SSH reconnect and the phone's 12s health
        // request; ordinary result/chunk messages remain short-lived.
        let timeoutSeconds = payload["op"] as? String == "begin" ? 30 : 8
        return try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            waiter.timeout = Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if !Task.isCancelled { waiter.finish(.failure(WatchBridgeError.timeout)) }
            }
            WCSession.default.sendMessage(payload, replyHandler: { response in
                Task { @MainActor in
                    if let code = response["error"] as? String {
                        if code == "busy", let previous = response["activeRun"] as? String, WatchBridgeWire.validID(previous) {
                            waiter.finish(.failure(WatchBridgeError.busy(previous)))
                        } else { waiter.finish(.failure(WatchBridgeError.remote(code))) }
                    }
                    else { waiter.finish(.success(response)) }
                }
            }, errorHandler: { [weak self] failure in
                let code = (failure as NSError).code
                Task { @MainActor in
                    self?.lastWCErrorCode = code
                    waiter.finish(.failure(WatchBridgeError.unreachable))
                }
            })
        }
    }

    private func execute(_ call: CarLiveFunctionCall) async -> CarLiveToolResult {
        let owner = run
        noteTool("dispatch")
        guard !owner.isEmpty, call.ownerToken == owner else { return unknown("owner") }
        do {
            var message = WatchBridgeWire.envelope("tool", run: owner, call: call.callID)
            message["name"] = call.name
            message["arguments"] = call.arguments
            bridgeStatus = "正在通过手机执行"
            var header = try await request(message)
            noteTool("header", status: header["status"] as? String)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while header["status"] as? String == "pending" {
                guard run == owner, !Task.isCancelled, ContinuousClock.now < deadline else { return unknown("poll_deadline") }
                try await Task.sleep(for: .milliseconds(300))
                header = try await request(WatchBridgeWire.envelope("result", run: owner, call: call.callID))
                noteTool("result", status: header["status"] as? String)
            }
            guard run == owner, header["status"] as? String == "ready",
                  let count = header["bytes"] as? Int, (0...WatchBridgeWire.maxOutputBytes).contains(count),
                  let chunks = header["chunks"] as? Int, chunks == (count + WatchBridgeWire.chunkBytes - 1) / WatchBridgeWire.chunkBytes,
                  let digest = header["sha256"] as? String else { return unknown("header_invalid") }
            var output = Data()
            for seq in 0..<chunks {
                var pull = WatchBridgeWire.envelope("pull", run: owner, call: call.callID)
                pull["seq"] = seq
                let chunk = try await request(pull)
                noteTool("chunk", sequence: seq)
                guard run == owner, chunk["run"] as? String == owner, chunk["call"] as? String == call.callID,
                      chunk["seq"] as? Int == seq, let data = chunk["data"] as? Data,
                      data.count == min(WatchBridgeWire.chunkBytes, count - output.count) else { return unknown("chunk_invalid") }
                output.append(data)
            }
            guard run == owner, output.count == count, WatchBridgeWire.digest(output) == digest,
                  let text = String(data: output, encoding: .utf8) else { return unknown("digest_invalid") }
            var ack = WatchBridgeWire.envelope("ack", run: owner, call: call.callID)
            ack["sha256"] = digest
            _ = try? await request(ack)
            noteTool("returned")
            WKInterfaceDevice.current().play(.success)
            return CarLiveToolResult(output: text)
        } catch WatchBridgeError.remote(let code) {
            let known = ["stale_context", "unreachable", "bad_arguments", "busy", "limit", "protocol", "missing_call", "missing_chunk", "call_conflict", "read_only_probe"]
            return unknown(known.contains(code) ? code : "remote_other")
        } catch WatchBridgeError.timeout { return unknown("message_timeout") }
        catch WatchBridgeError.unreachable { return unknown("unreachable") }
        catch { return unknown("cancelled_or_other") }
    }

    private func unknown(_ reason: String = "unknown") -> CarLiveToolResult {
        noteTool("failed", reason: reason)
        return CarLiveToolResult(output: CarLiveWire.errorOutput(code: "unknown", message: "结果未知，请到手机查看，不自动重试"))
    }

    private func noteTool(_ stage: String, status: String? = nil, reason: String = "none", sequence: Int = -1) {
        #if DEBUG
        let statuses = ["pending", "ready", "unknown"]
        let record: [String: Any] = ["stage": stage, "reason": reason,
            "status": status.map { statuses.contains($0) ? $0 : "other" } ?? "none",
            "sequence": sequence, "time": Date().timeIntervalSince1970, "wcErrorCode": lastWCErrorCode]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-tool-state.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    private func startPoll(_ owner: String) {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.run == owner else { return }
                do {
                    for event in Array(self.pendingCommentaryAcks) {
                        var ack = WatchBridgeWire.envelope("commentaryAck", run: owner)
                        ack["event"] = event
                        _ = try await self.request(ack)
                        guard self.run == owner else { return }
                        self.pendingCommentaryAcks.remove(event)
                    }
                    let response = try await self.request(WatchBridgeWire.envelope("commentary", run: owner))
                    guard self.run == owner else { return }
                    if let event = response["event"] as? String, let text = response["text"] as? String,
                       !self.submittedEvents.contains(event) {
                        let sent = await self.live.appendCommentary(text, eventID: event, expectedOwner: owner)
                        if sent { self.submittedEvents.insert(event) }
                    }
                } catch WatchBridgeError.remote("stale_context") {
                    guard self.run == owner, !Task.isCancelled else { return }
                    self.error = "连接已变更，请重新开始语音"
                    await self.stop()
                    return
                } catch {
                    guard self.run == owner, !Task.isCancelled else { return }
                    self.bridgeStatus = "手机不可达"
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if DEBUG
    private func runProbe(audio: Bool) async {
        // Explicit debug-only launch mode. Metadata only; no voice or tool bodies on disk.
        let probeID = ProcessInfo.processInfo.environment["WATCH_PROBE_ID"] ?? UUID().uuidString
        var result: [String: Any] = ["probe": probeID, "audio": audio]
        result["stage"] = "activation"
        writeProbe(result)
        do {
            // Activation is asynchronous; this wait is bounded and belongs to the local probe.
            for _ in 0..<20 {
                if WCSession.default.activationState == .activated { break }
                try await Task.sleep(for: .milliseconds(250))
            }
            result["activated"] = WCSession.default.activationState == .activated
            result["reachable"] = WCSession.default.isReachable
            result["stage"] = "begin"
            writeProbe(result)
            if audio {
                await start(readOnly: true)
                result["phase"] = live.phase.rawValue
                result["capture"] = live.captureGenerationForPolicy != 0
                if live.phase == .listening || live.phase == .speaking {
                    await live.appendCommentary("这是一次连接验收。请只说一句：语音连接成功。然后等待，不调用工具。")
                }
                try await Task.sleep(for: .seconds(12))
                result["inputFrames"] = live.inputFrameCount
                result["outputFrames"] = live.outputFrameCount
                result["captions"] = live.captions.count
                result["inputActive"] = live.inputLevel > 0
                result["outputActive"] = live.outputLevel > 0
                await stop()
            } else {
                let owner = UUID().uuidString
                run = owner
                connecting = true
                defer {
                    if run == owner {
                        run = ""
                        connecting = false
                    }
                }
                var begin = WatchBridgeWire.envelope("begin", run: owner)
                begin["readOnly"] = true
                let setup = try await request(begin)
                result["configured"] = setup["token"] as? String != nil
                result["stage"] = "tool"
                writeProbe(result)
                let output = await execute(CarLiveFunctionCall(callID: UUID().uuidString,
                    name: CarLiveHostedFunction.queryJobs,
                    arguments: "{\"queryScope\":\"recent\",\"sessionID\":null,\"text\":\"\",\"archivedOnly\":false,\"skip\":0,\"count\":1}", ownerToken: owner))
                let object = (try? JSONSerialization.jsonObject(with: Data(output.output.utf8))) as? [String: Any]
                result["toolOK"] = object?["ok"] as? Bool ?? false
                result["toolError"] = object?["error"] as? String ?? "none"
                await end(owner)
            }
            result["status"] = "completed"
        } catch WatchBridgeError.remote(let code) {
            result["status"] = "failed"
            result["error"] = code
        } catch WatchBridgeError.unreachable {
            result["status"] = "failed"
            result["error"] = "unreachable"
        } catch WatchBridgeError.timeout {
            result["status"] = "failed"
            result["error"] = "timeout"
        } catch { result["status"] = "failed" }
        result["wcErrorCode"] = lastWCErrorCode
        writeProbe(result)
    }

    private func writeProbe(_ result: [String: Any]) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("watch-probe.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif
}
