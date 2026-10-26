//
//  WatchPhoneBridge.swift
//  OpenCodeClient
//

import Foundation
import os
#if os(iOS)
import UIKit
import WatchConnectivity

/// The phone side of the watch's voice.
///
/// The watch has no Speech framework — watchOS does not ship one — so it
/// cannot recognise speech locally. Its microphone streams here, the phone
/// recognises the words on-device, runs the turn against the user's own
/// OpenCode server, and hands the answer back for the watch to speak.
///
/// No credential crosses the bridge: the watch never holds a token and never
/// talks to a hosted service.
@MainActor
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    private struct WatchConnectionWaiter {
        var continuation: CheckedContinuation<Bool, Never>?
        var operation: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        mutating func finish(_ connected: Bool) {
            continuation?.resume(returning: connected)
            continuation = nil
            operation?.cancel()
            operation = nil
            deadline?.cancel()
            deadline = nil
        }
    }

    weak var state: AppState?
    private(set) var lease: CarLiveLease?
    private var lastContact = Date.distantPast
    private var expiry: Task<Void, Never>?
    /// An answer waiting for the watch to pick it up.
    private var pendingVoiceReply: String?
    private var beginning: String?
    #if DEBUG
    private var debugEvents: [[String: Any]] = []
    #endif

    override init() {
        super.init()
    }

    var isActive: Bool { lease != nil && Date().timeIntervalSince(lastContact) < WatchBridgeWire.maxRunSeconds }

    /// Holds an answer for the watch to pick it up.
    func deliverVoiceReply(_ text: String) {
        pendingVoiceReply = text
    }

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
        lease = nil
        beginning = nil
        pendingVoiceReply = nil
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
              !state.deviceVoice.isListening else { return }
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
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "Watch voice bridge")
            let started = Date()
            self.probeEvent("received", message: message)
            let result = await self.handle(message)
            self.probeEvent("replied", response: result, elapsed: Date().timeIntervalSince(started))
            UIApplication.shared.endBackgroundTask(taskID)
            replyHandler(result)
        }
    }

    func handle(_ message: [String: Any]) async -> [String: Any] {
        guard message["v"] as? Int == WatchBridgeWire.version,
              let op = message["op"] as? String else { return WatchBridgeWire.error("protocol") }
        if op == "begin" { return await begin(message) }
        guard let run = message["run"] as? String, let owned = lease,
              run == owned.ownerToken, allowed(owned) else { return WatchBridgeWire.error("stale_context") }
        touch()
        switch op {
        case "end":
            invalidate()
            await state?.deviceVoice.stop()
            cleanupBackgroundConnection()
            return ["ok": true]
        case "audio":
            // The watch's microphone. The phone recognises it: watchOS has no
            // Speech framework, so the watch cannot recognise on its own.
            guard let data = message["data"] as? Data, !data.isEmpty,
                  data.count <= WatchBridgeWire.chunkBytes else { return WatchBridgeWire.error("bad_arguments") }
            state?.deviceVoice.ingest(data)
            return ["ok": true]
        case "voice":
            // The watch asks for the answer the engine produced.
            if let text = pendingVoiceReply {
                pendingVoiceReply = nil
                return ["run": run, "text": text]
            }
            return ["run": run, "ok": true]
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
        guard beginning == id, state.isCurrentHostRequest(host), state.carContextKey == context else {
            beginning = nil
            return WatchBridgeWire.error("stale_context")
        }
        let owned = CarLiveLease(hostID: host.hostProfileID, generation: host.generation, contextKey: context,
                                 epoch: 1, ownerToken: id)
        lease = owned
        beginning = nil
        touch()
        guard await beginConnection(owned), allowed(owned) else {
            if lease == owned { invalidate() }
            return WatchBridgeWire.error("unreachable")
        }
        // The watch drives the phone's voice engine: its microphone arrives
        // here, the phone recognises it and runs the turn against the user's
        // own server. No portal and no credential cross the bridge.
        state.deviceVoice.delivery = .watch
        await state.deviceVoice.start(capturesLocally: false)
        guard state.deviceVoice.isListening else {
            if lease == owned { invalidate() }
            return WatchBridgeWire.error("unreachable")
        }
        return ["run": id]
    }

    private func ensureConnection(_ owned: CarLiveLease) async -> Bool {
        guard allowed(owned), let state else { return false }
        if state.sshTunnelManager.config.isEnabled, state.sshTunnelManager.status != .connected {
            await state.sshTunnelManager.connect()
        }
        guard allowed(owned) else { return false }
        do {
            let health = try await state.apiClient.health()
            return allowed(owned) && health.healthy
        } catch { return false }
    }

    private func beginConnection(_ owned: CarLiveLease) async -> Bool {
        // Do not use a task group here: a non-cooperative SSH connect must not
        // delay the timeout reply while the group waits for cancelled children.
        var waiter = WatchConnectionWaiter()
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            waiter.operation = Task { [weak self] in
                let connected = await self?.ensureConnection(owned) ?? false
                waiter.finish(connected)
            }
            waiter.deadline = Task {
                try? await Task.sleep(for: .seconds(20))
                waiter.finish(false)
            }
        }
    }

    private func probeEvent(_ stage: String, message: [String: Any] = [:], response: [String: Any] = [:], elapsed: TimeInterval = 0) {
        var record: [String: Any] = ["stage": stage, "time": Date().timeIntervalSince1970, "elapsed": elapsed]
        for (key, value) in message {
            if key == "op" || key == "run" { record[key] = value }
        }
        for (key, value) in response {
            if key == "error" || key == "op" || key == "run" { record[key] = value }
        }
        debugEvents.append(record)
        if debugEvents.count > 50 { debugEvents.removeFirst(debugEvents.count - 50) }
        writeProbe("watch-bridge-events.json", value: debugEvents)
    }

    private func probeState(_ stage: String) {
        writeProbe("watch-bridge-state.json", value: [
            "stage": stage,
            "active": isActive,
            "time": Date().timeIntervalSince1970
        ])
    }

    private func runBridgeProbe() async {
        let owner = UUID().uuidString
        var metadata: [String: Any] = ["probe": ProcessInfo.processInfo.environment["WATCH_PROBE_ID"] ?? "phone", "time": Date().timeIntervalSince1970]
        var begin = WatchBridgeWire.envelope("begin", run: owner)
        metadata["begin"] = await handle(begin)
        begin["replacing"] = owner
        metadata["begin_again"] = await handle(begin)
        writeProbe("watch-phone-probe.json", value: metadata)
    }

    private func writeProbe(_ name: String, value: Any) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
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

/// Who owns a watch voice session.
///
/// The lease is bound to the host, the host-request generation and the
/// workspace, so a session that outlives its host is rejected instead of
/// talking to the wrong server.
struct CarLiveLease: Equatable {
    var hostID: UUID
    var generation: UInt64
    var contextKey: String
    var epoch: UInt64
    var ownerToken: String = ""
}

enum CarLiveLeaseCheck {
    static func allows(lease: CarLiveLease, hostID: UUID, generation: UInt64, contextMatches: Bool, connected: Bool, epoch: UInt64) -> Bool {
        connected && lease.hostID == hostID && lease.generation == generation && contextMatches && lease.epoch == epoch
    }
}
