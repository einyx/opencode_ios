import Foundation
import Testing
@testable import OpenCodeClient

struct SessionIndicatorTests {
    private static func status(_ type: String) -> SessionStatus {
        SessionStatus(type: type, attempt: nil, message: nil, next: nil)
    }

    private static func session(_ id: String, parent: String? = nil, updated: Int = 200_000, archived: Bool = false) -> Session {
        Session(id: id, slug: id, projectID: "p", directory: "/test", parentID: parent,
                title: id, version: "1", time: .init(created: 0, updated: updated, archived: archived ? 1 : nil),
                share: nil, summary: nil)
    }

    @MainActor private static func state() -> AppState {
        let defaults = UserDefaults(suiteName: "SessionIndicatorTests.\(UUID().uuidString)")!
        return AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(),
                        sshTunnelManager: SSHTunnelManager(defaults: defaults), userDefaults: defaults,
                        hostCredentialAccess: .noExternal)
    }

    @Test func settledRequiresIdleOrMissingStatus() {
        #expect(AppState.settled(nil))
        #expect(AppState.settled(Self.status("idle")))
        #expect(!AppState.settled(Self.status("busy")))
        #expect(!AppState.settled(Self.status("retry")))
        #expect(!AppState.settled(Self.status("unknown")))
    }

    @Test func unreadUsesStrictTimestampComparisonAndSettledStatus() {
        let sessions = [Self.session("a")]
        #expect(AppState.unreadSessionIDs(sessions: sessions, statuses: [:], lastViewedAt: [:]) == ["a"])
        for viewed in [199.0, 200.0, 201.0] {
            let ids = AppState.unreadSessionIDs(sessions: sessions, statuses: [:], lastViewedAt: ["a": Date(timeIntervalSince1970: viewed)])
            #expect(ids == (viewed < 200 ? ["a"] : []))
        }
        for type in ["busy", "retry"] {
            #expect(AppState.unreadSessionIDs(sessions: sessions, statuses: ["a": Self.status(type)], lastViewedAt: [:]).isEmpty)
        }
    }

    @Test @MainActor func precedenceAndExemptions() {
        let state = Self.state()
        state.sessions = [Self.session("a"), Self.session("archived", archived: true)]
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .unread)
        state.readStateStore.markFailed(sessionID: "a", at: Date(timeIntervalSince1970: 150))
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .failed)
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 1) == .needsYou)
        state.currentSessionID = "a"
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .failed)
        state.readStateStore.markViewed(sessionID: "a", at: Date(timeIntervalSince1970: 150))
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == nil)
        state.currentSessionID = nil
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == nil)
        state.readStateStore.markViewed(sessionID: "a", at: Date(timeIntervalSince1970: 150))
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .unread)
        state.readStateStore.markFailed(sessionID: "archived", at: Date())
        #expect(state.rowIndicator(sessionID: "archived", attentionCount: 1) == nil)
        for type in ["busy", "retry"] {
            state.sessionStatuses["a"] = Self.status(type)
            #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == nil)
            #expect(state.rowIndicator(sessionID: "a", attentionCount: 1) == .needsYou)
        }
    }

    @Test @MainActor func descendantsCompareAgainstParentsViewedTime() {
        let state = Self.state()
        state.sessions = [Self.session("parent", updated: 50_000), Self.session("child", parent: "parent", updated: 75_000), Self.session("grandchild", parent: "child")]
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 100))
        state.readStateStore.markViewed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 300))
        #expect(state.sessionUnreadCounts["parent"] == 1)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .unread)
        #expect(state.rowIndicator(sessionID: "grandchild", attentionCount: 0) == nil)
        state.sessionStatuses["grandchild"] = Self.status("busy")
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == nil)
        state.sessionStatuses["grandchild"] = Self.status("idle")
        state.sessionStatuses["parent"] = Self.status("retry")
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == nil)
        state.sessionStatuses["parent"] = Self.status("idle")
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 200))
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == nil)
    }

    @Test func unreadAncestorWalkIsCycleSafe() {
        let sessions = [Self.session("a", parent: "b"), Self.session("b", parent: "a")]
        #expect(AppState.unreadCountsBySession(sessions: sessions, unreadIDs: ["a"]) == ["a": 1, "b": 1])
    }

    @Test @MainActor func errorsCommitOnlyAtIdleAndCleanTurnsClearFailure() async throws {
        let state = Self.state()
        state.sessions = [Self.session("other")]
        func send(_ type: String, status: String? = nil) async throws {
            var properties: [String: Any] = ["sessionID": "other"]
            if let status { properties["status"] = ["type": status] }
            let data = try JSONSerialization.data(withJSONObject: ["payload": ["type": type, "properties": properties]])
            let event = try JSONDecoder().decode(SSEEvent.self, from: data)
            await state.applySSEEventForTesting(event)
        }
        try await send("session.status", status: "busy")
        try await send("session.error")
        #expect(state.pendingSessionErrorAt["other"] != nil)
        #expect(state.readStateStore.failedAt(for: "other") == nil)
        try await send("session.status", status: "retry")
        #expect(state.pendingSessionErrorAt["other"] == nil)
        try await send("session.status", status: "idle")
        #expect(state.readStateStore.failedAt(for: "other") == nil)
        try await send("session.error")
        let failed = state.pendingSessionErrorAt["other"]
        // A repeated idle still settles an error, without repeating reconciliation.
        try await send("session.status", status: "idle")
        #expect(state.readStateStore.failedAt(for: "other") == failed)
        #expect(state.rowIndicator(sessionID: "other", attentionCount: 0) == .failed)
        try await send("session.status", status: "idle")
        #expect(state.readStateStore.failedAt(for: "other") == failed)
        try await send("session.status", status: "busy")
        try await send("session.status", status: "idle")
        #expect(state.readStateStore.failedAt(for: "other") == nil)
    }

    @Test @MainActor func selectionAndCleanup() {
        let state = Self.state()
        let session = Self.session("a")
        state.sessions = [session]
        state.currentSessionID = "a"
        state.readStateStore.markFailed(sessionID: "a", at: Date(timeIntervalSince1970: 100))
        state.selectSession(session)
        #expect(state.readStateStore.lastViewedAt(for: "a") != nil)
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == nil)
        state.pendingSessionErrorAt["a"] = Date()
        state.clearSessionScopedCaches(sessionID: "a")
        #expect(state.readStateStore.lastViewedAt(for: "a") == nil)
        #expect(state.readStateStore.failedAt(for: "a") == nil)
        #expect(state.pendingSessionErrorAt["a"] == nil)
        state.pendingSessionErrorAt["a"] = Date()
        state.resetConnectionRuntimeForHostSwitch()
        #expect(state.pendingSessionErrorAt.isEmpty)
    }

    @Test @MainActor func pollCommitsErrorsAndClearsOnlyAtTurnEnd() {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.pendingSessionErrorAt["a"] = failed
        state.sessionStatuses["a"] = Self.status("busy")
        state.sessionStatusUpdatedAt["a"] = Date()
        state.mergePolledSessionStatuses(["a": Self.status("idle")])
        #expect(state.pendingSessionErrorAt["a"] == failed)
        #expect(state.readStateStore.failedAt(for: "a") == nil)
        #expect(state.sessionStatuses["a"]?.type == "busy")

        state.sessionStatusUpdatedAt["a"] = Date().addingTimeInterval(-6)
        state.mergePolledSessionStatuses(["a": Self.status("idle")])
        #expect(state.readStateStore.failedAt(for: "a") == failed)
        #expect(state.pendingSessionErrorAt["a"] == nil)
        state.mergePolledSessionStatuses(["a": Self.status("idle")])
        #expect(state.readStateStore.failedAt(for: "a") == failed)

        state.sessionStatuses["a"] = Self.status("retry")
        state.mergePolledSessionStatuses(["a": Self.status("idle")])
        #expect(state.readStateStore.failedAt(for: "a") == nil)
    }

    @Test @MainActor func missingPolledStatusUsesSameFailureReconciliation() {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.pendingSessionErrorAt["a"] = failed
        state.sessionStatuses["a"] = Self.status("busy")
        state.sessionStatusUpdatedAt["a"] = Date()
        state.mergePolledSessionStatuses([:])
        #expect(state.pendingSessionErrorAt["a"] == failed)
        #expect(state.sessionStatuses["a"]?.type == "busy")
        state.sessionStatusUpdatedAt["a"] = Date().addingTimeInterval(-6)
        state.mergePolledSessionStatuses([:])
        #expect(state.readStateStore.failedAt(for: "a") == failed)
        #expect(state.pendingSessionErrorAt["a"] == nil)
        state.sessionStatuses["a"] = Self.status("retry")
        state.mergePolledSessionStatuses([:])
        #expect(state.readStateStore.failedAt(for: "a") == nil)
    }

    @Test @MainActor func initialIdlePreservesPersistedFailureOnSSEAndPoll() async throws {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.readStateStore.markFailed(sessionID: "sse", at: failed)
        state.readStateStore.markFailed(sessionID: "poll", at: failed)
        let data = Data(#"{"payload":{"type":"session.status","properties":{"sessionID":"sse","status":{"type":"idle"}}}}"#.utf8)
        await state.applySSEEventForTesting(try JSONDecoder().decode(SSEEvent.self, from: data))
        state.mergePolledSessionStatuses(["poll": Self.status("idle")])
        #expect(state.readStateStore.failedAt(for: "sse") == failed)
        #expect(state.readStateStore.failedAt(for: "poll") == failed)
    }

    @Test @MainActor func pendingErrorsClearOnDisconnectAndHostReset() {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.readStateStore.markFailed(sessionID: "persisted", at: failed)
        state.pendingSessionErrorAt["a"] = failed
        state.disconnectSSE()
        #expect(state.pendingSessionErrorAt.isEmpty)
        #expect(state.readStateStore.failedAt(for: "persisted") == failed)
        state.pendingSessionErrorAt["a"] = failed
        state.resetConnectionRuntimeForHostSwitch()
        #expect(state.pendingSessionErrorAt.isEmpty)
        #expect(state.readStateStore.failedAt(for: "persisted") == failed)
    }

    @Test @MainActor func collapsedParentRollsUpFailuresUsingItsOwnViewedTime() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent"), Self.session("grandchild", parent: "child")]
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 100))
        state.readStateStore.markViewed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 300))
        state.readStateStore.markFailed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 200))
        #expect(!state.expandedSessionIDs.contains("parent"))
        #expect(state.sessionFailureCounts["parent"] == 1)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .failed)
        #expect(state.rowIndicator(sessionID: "grandchild", attentionCount: 0) == nil)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 1) == .needsYou)
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 200))
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == nil)
    }

    @Test @MainActor func rowUsesOnlySuppliedIndicatorMaps() {
        let state = Self.state()
        let row = Self.session("not-in-loaded-sessions")
        #expect(state.rowIndicator(session: row, attentionCount: 0, unreadCounts: [row.id: 1], failureCounts: [:]) == .unread)
        #expect(state.rowIndicator(session: row, attentionCount: 0, unreadCounts: [:], failureCounts: [row.id: 1]) == .failed)
        #expect(state.rowIndicator(session: row, attentionCount: 0, unreadCounts: [:], failureCounts: [:]) == nil)
    }

    @Test @MainActor func leavingSessionMarksOutputSeenButNotFutureOutput() {
        let state = Self.state()
        let now = Date()
        let updated = Int(now.addingTimeInterval(-1).timeIntervalSince1970 * 1000)
        state.sessions = [Self.session("a", updated: updated), Self.session("b")]
        state.currentSessionID = "a"
        state.readStateStore.markViewed(sessionID: "a", at: now.addingTimeInterval(-100))
        state.currentSessionID = "b"
        #expect(state.readStateStore.lastViewedAt(for: "a")! >= now)
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == nil)
        state.sessions[0] = Self.session("a", updated: Int(Date().addingTimeInterval(1).timeIntervalSince1970 * 1000))
        #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .unread)
    }

    @Test @MainActor func chatDisappearanceMarksViewedAndColdSelectionDoesNot() {
        let state = Self.state()
        let viewed = Date(timeIntervalSince1970: 100)
        state.sessions = [Self.session("a")]
        state.readStateStore.markViewed(sessionID: "a", at: viewed)
        state.selectFirstAvailableSessionIfNeeded()
        #expect(state.currentSessionID == "a")
        #expect(state.readStateStore.lastViewedAt(for: "a") == viewed)
        state.markCurrentSessionViewed(at: Date(timeIntervalSince1970: 200))
        #expect(state.readStateStore.lastViewedAt(for: "a") == Date(timeIntervalSince1970: 200))
    }
}

private extension AppState {
    func rowIndicator(sessionID: String, attentionCount: Int) -> SessionIndicator? {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return nil }
        return rowIndicator(session: session, attentionCount: attentionCount,
                            unreadCounts: sessionUnreadCounts, failureCounts: sessionFailureCounts)
    }
}
