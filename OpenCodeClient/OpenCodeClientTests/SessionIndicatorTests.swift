import Foundation
import QuartzCore
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
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(),
                        sshTunnelManager: SSHTunnelManager(defaults: defaults), userDefaults: defaults,
                        hostCredentialAccess: .noExternal)
        state.isConnected = true
        state.statusStreamConnected = true
        for id in ["a", "b", "parent", "child", "grandchild", "other", "archived"] {
            state.statusConfirmedAt[id] = Date()
        }
        return state
    }

    @Test func settledRequiresExplicitIdle() {
        #expect(!AppState.settled(nil))
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
            #expect(state.rowIndicator(sessionID: "a", attentionCount: 0) == .running)
            #expect(state.rowIndicator(sessionID: "a", attentionCount: 1) == .needsYou)
        }
    }

    @Test @MainActor func descendantsUseSourceAcknowledgementAndGreenPrecedesBlue() {
        let state = Self.state()
        state.sessions = [Self.session("parent", updated: 50_000), Self.session("child", parent: "parent", updated: 75_000), Self.session("grandchild", parent: "child")]
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 100))
        state.readStateStore.markViewed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 300))
        #expect(state.sessionUnreadCounts["parent"] == 1)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .unread)
        #expect(state.rowIndicator(sessionID: "grandchild", attentionCount: 0) == nil)
        state.sessionStatuses["grandchild"] = Self.status("busy")
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .running)
        state.sessionStatuses["grandchild"] = Self.status("idle")
        state.sessionStatuses["parent"] = Self.status("retry")
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .running)
        state.sessionStatuses["parent"] = Self.status("idle")
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 200))
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .unread)
        state.readStateStore.markViewed(sessionID: "child", at: Date(timeIntervalSince1970: 300))
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == nil)
    }

    @Test func unreadAncestorWalkIsCycleSafe() {
        let sessions = [Self.session("a", parent: "b"), Self.session("b", parent: "a")]
        #expect(AppState.unreadCountsBySession(sessions: sessions, unreadIDs: ["a"]) == ["a": 1, "b": 1])
    }

    @Test @MainActor func errorsCommitAtIdleAndCleanTurnsPreserveUnacknowledgedFailure() async throws {
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
        #expect(state.readStateStore.failedAt(for: "other") == failed)
        #expect(state.rowIndicator(sessionID: "other", attentionCount: 0) == .failed)
        state.readStateStore.markViewed(sessionID: "other", at: Date())
        #expect(state.rowIndicator(sessionID: "other", attentionCount: 0) == nil)
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

    @Test @MainActor func pollCommitsErrorsButDoesNotInventSuccessfulTurns() {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        let failed = Date(timeIntervalSince1970: 100)
        state.pendingSessionErrorAt["a"] = failed
        state.sessionStatuses["a"] = Self.status("busy")
        state.statusRevisions["a"] = 1
        state.applyStatusSnapshot(["a": Self.status("idle")], revisionsAtStart: [:], directory: "/test")
        #expect(state.pendingSessionErrorAt["a"] == failed)
        #expect(state.readStateStore.failedAt(for: "a") == nil)
        #expect(state.sessionStatuses["a"]?.type == "busy")

        state.applyStatusSnapshot(["a": Self.status("idle")], revisionsAtStart: ["a": 1], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "a") == failed)
        #expect(state.pendingSessionErrorAt["a"] == nil)
        state.applyStatusSnapshot(["a": Self.status("idle")], revisionsAtStart: ["a": 1], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "a") == failed)

        state.sessionStatuses["a"] = Self.status("retry")
        state.applyStatusSnapshot(["a": Self.status("idle")], revisionsAtStart: ["a": 1], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "a") == failed)
    }

    @Test @MainActor func missingPolledStatusUsesSameFailureReconciliation() {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        let failed = Date(timeIntervalSince1970: 100)
        state.pendingSessionErrorAt["a"] = failed
        state.sessionStatuses["a"] = Self.status("busy")
        state.statusRevisions["a"] = 1
        state.applyStatusSnapshot([:], revisionsAtStart: [:], directory: "/test")
        #expect(state.pendingSessionErrorAt["a"] == failed)
        #expect(state.sessionStatuses["a"]?.type == "busy")
        state.applyStatusSnapshot([:], revisionsAtStart: ["a": 1], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "a") == failed)
        #expect(state.pendingSessionErrorAt["a"] == nil)
        state.sessionStatuses["a"] = Self.status("retry")
        state.applyStatusSnapshot([:], revisionsAtStart: ["a": 1], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "a") == failed)
    }

    @Test @MainActor func initialIdlePreservesPersistedFailureOnSSEAndPoll() async throws {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.sessions = [Self.session("sse"), Self.session("poll")]
        state.readStateStore.markFailed(sessionID: "sse", at: failed)
        state.readStateStore.markFailed(sessionID: "poll", at: failed)
        let data = Data(#"{"payload":{"type":"session.status","properties":{"sessionID":"sse","status":{"type":"idle"}}}}"#.utf8)
        await state.applySSEEventForTesting(try JSONDecoder().decode(SSEEvent.self, from: data))
        state.applyStatusSnapshot(["poll": Self.status("idle")], revisionsAtStart: [:], directory: "/test")
        #expect(state.readStateStore.failedAt(for: "sse") == failed)
        #expect(state.readStateStore.failedAt(for: "poll") == failed)
    }

    @Test @MainActor func pendingErrorsSurviveDisconnectButNotHostReset() {
        let state = Self.state()
        let failed = Date(timeIntervalSince1970: 100)
        state.readStateStore.markFailed(sessionID: "persisted", at: failed)
        state.pendingSessionErrorAt["a"] = failed
        state.disconnectSSE()
        #expect(state.pendingSessionErrorAt["a"] == failed)
        #expect(state.readStateStore.failedAt(for: "persisted") == failed)
        state.pendingSessionErrorAt["a"] = failed
        state.resetConnectionRuntimeForHostSwitch()
        #expect(state.pendingSessionErrorAt.isEmpty)
        #expect(state.readStateStore.failedAt(for: "persisted") == failed)
    }

    @Test @MainActor func collapsedParentDropsAcknowledgedSourceFailure() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent"), Self.session("grandchild", parent: "child")]
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 100))
        state.readStateStore.markViewed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 300))
        state.readStateStore.markFailed(sessionID: "grandchild", at: Date(timeIntervalSince1970: 200))
        #expect(!state.expandedSessionIDs.contains("parent"))
        #expect(state.sessionFailureCounts["parent"] == nil)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .unread)
        #expect(state.rowIndicator(sessionID: "grandchild", attentionCount: 0) == nil)
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 1) == .needsYou)
        state.readStateStore.markViewed(sessionID: "parent", at: Date(timeIntervalSince1970: 200))
        #expect(state.rowIndicator(sessionID: "parent", attentionCount: 0) == .unread)
    }

    @Test @MainActor func missingStatusIsUnknownUntilConfirmed() {
        let state = Self.state()
        let row = Self.session("not-in-loaded-sessions")
        state.sessions = [row]
        #expect(state.sessionIndicatorPresentations[row.id]?.indicator == nil)
        #expect(state.sessionIndicatorPresentations[row.id]?.needsSync == true)
        state.applyStatusSnapshot([:], revisionsAtStart: [:], directory: "/test")
        #expect(state.sessionIndicatorPresentations[row.id]?.indicator == .unread)
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

    @Test @MainActor func sourceAcknowledgementPreservesSiblingAndParentContributions() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent"),
                          Self.session("grandchild", parent: "child"), Self.session("b", parent: "parent")]
        let failure = Date(timeIntervalSince1970: 200)
        for session in state.sessions { state.readStateStore.markFailed(sessionID: session.id, at: failure) }
        #expect(state.sessionFailureCounts["parent"] == 4)
        state.readStateStore.markViewed(sessionID: "grandchild", at: failure.addingTimeInterval(1))
        #expect(state.sessionFailureCounts["parent"] == 3)
        #expect(state.sessionFailureCounts["child"] == 1)
        state.readStateStore.markViewed(sessionID: "parent", at: failure.addingTimeInterval(1))
        #expect(state.sessionFailureCounts["parent"] == 2)
        #expect(state.sessionUnreadCounts["parent"] == 2)
        state.readStateStore.markViewed(sessionID: "child", at: failure.addingTimeInterval(1))
        #expect(state.sessionFailureCounts["parent"] == 1)
        #expect(state.sessionUnreadCounts["parent"] == 1)
        state.readStateStore.markFailed(sessionID: "grandchild", at: failure.addingTimeInterval(2))
        #expect(state.sessionFailureCounts["parent"] == 2)
    }

    @Test @MainActor func mixedTreeKeepsExecutionSummaryAndLastChildEndsAtomically() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent"), Self.session("grandchild", parent: "child")]
        state.sessionStatuses = ["parent": Self.status("busy"), "child": Self.status("idle"), "grandchild": Self.status("retry")]
        state.readStateStore.markFailed(sessionID: "child", at: Date())
        let presentation = state.sessionIndicatorPresentations["parent"]!
        #expect(presentation.indicator == .failed)
        #expect(presentation.statusText == nil)
        #expect(presentation.activeDescendantCount == 1)
        state.pendingPermissions = PermissionController.fromPendingRequests([Self.permission("p", session: "child")])
        #expect(state.sessionIndicatorPresentations["parent"]?.indicator == .needsYou)
        #expect(state.sessionIndicatorPresentations["parent"]?.activeDescendantCount == presentation.activeDescendantCount)
        state.pendingPermissions = []
        state.readStateStore.markViewed(sessionID: "child", at: Date())
        state.sessionStatuses["parent"] = Self.status("idle")
        #expect(state.sessionIndicatorPresentations["parent"]?.indicator == .running)
        state.sessionStatuses["grandchild"] = Self.status("idle")
        #expect(state.sessionIndicatorPresentations["parent"]?.indicator == .unread)
        state.currentSessionID = "parent"
        #expect(state.sessionIndicatorPresentations["parent"]?.indicator == nil)
    }

    @Test @MainActor func compactPresentationKeepsListCountOutOfComposerStatusText() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent")]
        state.sessionStatuses = ["parent": Self.status("busy"), "child": Self.status("retry")]
        let parent = state.sessionIndicatorPresentations["parent"]!
        #expect(parent.indicator == .running)
        #expect(parent.activeDescendantCount == 1)
        #expect(parent.statusText == nil)
        #expect(state.sessionIndicatorPresentations["child"]?.statusText == L10n.t(.sessionsStatusRetry))
        state.sessionStatuses["child"] = Self.status("idle")
        let alone = state.sessionIndicatorPresentations["parent"]!
        #expect(alone.activeDescendantCount == 0)
        #expect(!alone.hasDetails)
        #expect(alone.statusText == nil)
        state.disconnectSSE()
        #expect(state.sessionIndicatorPresentations["parent"]?.statusText == SessionIndicatorCopy.syncing)
    }

    @Test @MainActor func composerReusesSpecificActivityButListRemainsCompact() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent")]
        state.sessionStatuses = ["parent": Self.status("busy"), "child": Self.status("busy")]
        let presentation = state.sessionIndicatorPresentations["parent"]!
        #expect(presentation.ownIsActive)
        #expect(presentation.statusText == nil) // No verbose list label.
        let activity = L10n.t(.activityRunningCommands)
        #expect(ComposerActivityText.text(presentation: presentation, activity: activity, voice: nil) == activity)
        #expect(ComposerActivityText.text(presentation: presentation, activity: L10n.t(.activityThinking), voice: nil) == L10n.t(.activityThinking))
    }

    @Test @MainActor func composerBareGreenHasWorkingOrSubagentFallbackWithoutCount() {
        let state = Self.state()
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent")]
        state.sessionStatuses = ["parent": Self.status("busy"), "child": Self.status("busy")]
        #expect(ComposerActivityText.text(presentation: state.sessionIndicatorPresentations["parent"], activity: " \n ", voice: nil) == L10n.t(.chatAgentWorking))
        state.sessionStatuses["parent"] = Self.status("idle")
        let descendantsOnly = state.sessionIndicatorPresentations["parent"]!
        #expect(!descendantsOnly.ownIsActive && descendantsOnly.activeDescendantCount == 1)
        #expect(ComposerActivityText.text(presentation: descendantsOnly, activity: "stale tool text", voice: nil) == L10n.t(.chatBackgroundTasksOne))
    }

    @Test @MainActor func composerUnknownDoesNotReuseStaleActivityAndMergesVoice() {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        state.sessionStatuses["a"] = Self.status("busy")
        state.statusConfirmedAt["a"] = Date().addingTimeInterval(-61)
        let presentation = state.sessionIndicatorPresentations["a"]!
        #expect(!presentation.ownIsActive)
        let voice = L10n.t(.chatSpeechTranscribing)
        #expect(ComposerActivityText.text(presentation: presentation, activity: "stale tool text", voice: voice) == "\(SessionIndicatorCopy.syncing) · \(voice)")
        #expect(ComposerActivityText.text(presentation: nil, activity: "stale tool text", voice: voice) == voice)
    }

    @Test @MainActor func composerExplicitStatesTakePriorityAndDoNotDuplicateRetryVoice() {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        state.sessionStatuses["a"] = Self.status("retry")
        let retry = L10n.t(.sessionsStatusRetry)
        #expect(ComposerActivityText.text(presentation: state.sessionIndicatorPresentations["a"], activity: "Thinking", voice: retry) == retry)
        state.readStateStore.markFailed(sessionID: "a", at: Date())
        #expect(ComposerActivityText.text(presentation: state.sessionIndicatorPresentations["a"], activity: "Thinking", voice: nil) == "\(L10n.t(.sessionsIndicatorFailed)) · \(retry)")
        state.pendingPermissions = PermissionController.fromPendingRequests([Self.permission("p", session: "a")])
        state.sessionStatuses["a"] = Self.status("busy")
        #expect(ComposerActivityText.text(presentation: state.sessionIndicatorPresentations["a"], activity: "Thinking", voice: nil) == L10n.t(.sessionsIndicatorNeedsYou))
        state.disconnectSSE()
        #expect(ComposerActivityText.text(presentation: state.sessionIndicatorPresentations["a"], activity: "Thinking", voice: nil) == "\(L10n.t(.sessionsIndicatorNeedsYou)) · \(SessionIndicatorCopy.syncing)")
    }

    @Test @MainActor func disconnectAndExpiredConfirmationSuppressGreenAndBlueButKeepRed() {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        state.sessionStatuses["a"] = Self.status("busy")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .running)
        state.statusConfirmedAt["a"] = Date().addingTimeInterval(-61)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == nil)
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
        state.statusConfirmedAt["a"] = Date()
        state.disconnectSSE()
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == nil)
        state.sessionStatuses["a"] = Self.status("idle")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == nil)
        state.readStateStore.markFailed(sessionID: "a", at: Date())
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .failed)
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
    }

    @Test @MainActor func sameValueSSEWinsAgainstOldSnapshotAndRefreshesConfirmation() async throws {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        for type in ["busy", "idle", "retry"] {
            state.sessionStatuses["a"] = Self.status(type)
            let revisions = state.statusRevisions
            state.statusConfirmedAt["a"] = Date().addingTimeInterval(-61)
            try await Self.send(state, "session.status", ["sessionID": "a", "status": ["type": type]])
            state.applyStatusSnapshot(["a": Self.status(type == "idle" ? "busy" : "idle")], revisionsAtStart: revisions, directory: "/test")
            #expect(state.sessionStatuses["a"]?.type == type)
            #expect(Date().timeIntervalSince(state.statusConfirmedAt["a"]!) < 1)
        }
    }

    @Test @MainActor func noCurrentSessionBootstrapReconcilesBothPendingKinds() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.pendingPermissions = PermissionController.fromPendingRequests([Self.permission("old", session: "child")])
        state.pendingQuestions = [Self.question("old-q", session: "child")]
        await api.configureIndicators(permissions: [Self.permission("new", session: "parent")], questions: [Self.question("new-q", session: "parent")])
        await state.bootstrapSyncCurrentSession(reason: "test")
        #expect(state.currentSessionID == nil)
        #expect(state.pendingPermissions.map(\.permissionID) == ["new"])
        #expect(state.pendingQuestions.map(\.id) == ["new-q"])
    }

    @Test @MainActor func resolvedSSECannotBeResurrectedByOldPendingSnapshots() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent")]
        let p = Self.permission("p", session: "child")
        let q = Self.question("q", session: "child")
        state.pendingPermissions = PermissionController.fromPendingRequests([p])
        state.pendingQuestions = [q]
        await api.configureIndicators(permissions: [p], questions: [q], suspended: true)
        let permissions = Task { await state.refreshPendingPermissions() }
        let questions = Task { await state.refreshPendingQuestions() }
        await Self.waitForRequests(api, count: 2)
        try await Self.send(state, "permission.replied", ["sessionID": "child", "id": "p"])
        try await Self.send(state, "question.replied", ["requestID": "q"])
        await api.resumeIndicatorRequests()
        await permissions.value
        await questions.value
        #expect(state.pendingPermissions.isEmpty)
        #expect(state.pendingQuestions.isEmpty)
        #expect(state.sessionAttentionCounts["parent"] == nil)
    }

    @Test @MainActor func pollIsSingleFlightAndLateHostResponseIsDiscarded() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.sessions = [Self.session("a")]
        await api.configureIndicators(statuses: ["a": Self.status("busy")], suspended: true)
        let task = Task { await state.syncSessionStatusesFromPoll() }
        await Self.waitForRequests(api, count: 1)
        await state.syncSessionStatusesFromPoll()
        #expect(await api.indicatorRequestCount == 1)
        state.resetConnectionRuntimeForHostSwitch()
        await api.resumeIndicatorRequests()
        await task.value
        #expect(state.sessionStatuses.isEmpty)
        #expect(state.statusConfirmedAt.isEmpty)
    }

    @Test @MainActor func outsideProjectBusyWithMissedIdleDoesNotVetoConfirmedBlue() async throws {
        let state = Self.state()
        state.serverCurrentProjectWorktree = "/test"
        state.sessions = [Self.session("a")]
        try await Self.send(state, "session.status", ["sessionID": "elsewhere", "status": ["type": "busy"]], directory: "/different")
        state.applyStatusSnapshot([:], revisionsAtStart: state.statusRevisions, directory: "/test")
        #expect(state.sessionStatuses["elsewhere"]?.type == "busy")
        #expect(state.statusDirectories["elsewhere"] == "/different")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .unread)
        state.statusConfirmedAt["elsewhere"] = Date().addingTimeInterval(-61)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .unread)
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == false)
    }

    @Test @MainActor func sameScopeUnknownActiveConvergesWithoutOverwritingNewSSE() async throws {
        let state = Self.state()
        state.serverCurrentProjectWorktree = "/test"
        state.sessions = [Self.session("a")]
        let before = state.statusRevisions
        try await Self.send(state, "session.status", ["sessionID": "unloaded", "status": ["type": "busy"]], directory: "/test")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == nil)
        state.applyStatusSnapshot([:], revisionsAtStart: before, directory: "/test")
        #expect(state.sessionStatuses["unloaded"]?.type == "busy")
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
        state.applyStatusSnapshot([:], revisionsAtStart: state.statusRevisions, directory: "/test")
        #expect(state.sessionStatuses["unloaded"]?.type == "idle")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .unread)
        state.applyStatusSnapshot(["rest-unloaded": Self.status("busy")], revisionsAtStart: state.statusRevisions, directory: "/test")
        #expect(state.statusDirectories["rest-unloaded"] == "/test")
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
        state.statusConfirmedAt["rest-unloaded"] = Date().addingTimeInterval(-61)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .unread)
    }

    @Test(arguments: ["permission", "question"]) @MainActor
    func sameHostReconnectReplacesPendingBeforeOldGETReturns(kind: String) async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        let host = state.currentHostProfileID
        let oldP = Self.permission("old", session: "child")
        let oldQ = Self.question("old", session: "child")
        state.pendingPermissions = PermissionController.fromPendingRequests([oldP])
        state.pendingQuestions = [oldQ]
        await api.configureIndicators(permissions: [oldP], questions: [oldQ], suspended: true)
        let oldGET = Task {
            if kind == "permission" { await state.refreshPendingPermissions() }
            else { await state.refreshPendingQuestions() }
        }
        await Self.waitForRequests(api, count: 1)
        state.disconnectSSE()
        #expect(state.pendingPermissions.first?.permissionID == "old")
        #expect(state.pendingQuestions.first?.id == "old")
        await api.configureIndicators(permissions: [Self.permission("new", session: "child")], questions: [Self.question("new", session: "child")])
        // Exercise the actual same-host connected event with no selected session.
        try await Self.send(state, "server.connected", [:])
        #expect(state.currentHostProfileID == host && state.currentSessionID == nil)
        #expect(state.pendingPermissions.first?.permissionID == "new")
        #expect(state.pendingQuestions.first?.id == "new")
        await api.configureIndicators(permissions: [Self.permission("new", session: "child")], questions: [Self.question("new", session: "child")], suspended: true)
        let nextGET = Task {
            if kind == "permission" { await state.refreshPendingPermissions() }
            else { await state.refreshPendingQuestions() }
        }
        await Self.waitForRequests(api, count: 5)
        let slot = kind == "permission" ? state.permissionPollID : state.questionPollID
        await api.resumeFirstIndicatorRequest()
        await oldGET.value
        #expect((kind == "permission" ? state.permissionPollID : state.questionPollID) == slot)
        #expect(state.pendingPermissions.first?.permissionID == "new")
        #expect(state.pendingQuestions.first?.id == "new")
        await api.resumeIndicatorRequests()
        await nextGET.value
    }

    @Test @MainActor func expiryClockWithdrawsGreenWhileNetworkIsSuspended() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.statusStreamConnected = true
        state.serverCurrentProjectWorktree = "/test"
        state.sessions = [Self.session("a"), Self.session("red"), Self.session("yellow")]
        let clock = IndicatorExpiryTestClock()
        for session in state.sessions {
            state.sessionStatuses[session.id] = Self.status("busy")
            state.statusConfirmedAt[session.id] = clock.now
        }
        state.readStateStore.markFailed(sessionID: "red", at: clock.now)
        state.pendingPermissions = PermissionController.fromPendingRequests([Self.permission("p", session: "yellow")])
        await api.configureIndicators(suspended: true)
        let network = Task { await state.refreshVisibleSessionStatus() }
        await Self.waitForRequests(api, count: 1)
        let ticks = Task {
            await state.runSessionStatusExpiryTicks(now: { clock.now }, sleep: { try await clock.sleep() })
        }
        for _ in 0..<10_000 {
            if clock.isSleeping { break }
            await Task.yield()
        }
        #expect(clock.isSleeping)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .running)
        clock.advance(seconds: 61)
        for _ in 0..<10_000 {
            if state.statusEvaluationDate == clock.now { break }
            await Task.yield()
        }
        #expect(state.statusEvaluationDate == clock.now)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == nil)
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
        #expect(state.sessionIndicatorPresentations["red"]?.indicator == .failed)
        #expect(state.sessionIndicatorPresentations["yellow"]?.indicator == .needsYou)
        #expect(state.sessionIndicatorPresentations["red"]?.needsSync == true)
        #expect(state.sessionIndicatorPresentations["yellow"]?.needsSync == true)
        #expect(state.statusPollID != nil)
        #expect(await api.indicatorRequestCount == 1)
        ticks.cancel()
        clock.cancelSleep()
        await ticks.value
        await api.resumeIndicatorRequests()
        await network.value
    }

    @Test @MainActor func breathingHasSharedPhaseAndNeverFlashesOff() {
        let animation = SessionIndicatorDot.runningAnimation()
        #expect(animation.keyPath == "opacity")
        #expect(animation.duration == 2.6)
        #expect(animation.values as? [Double] == [1, 0.40, 1])
        #expect(animation.keyTimes == [0, 0.5, 1])
        #expect(SessionIndicatorDot.shouldAnimate(isRunning: true, visible: true, active: true, reduceMotion: false))
        #expect(!SessionIndicatorDot.shouldAnimate(isRunning: true, visible: true, active: true, reduceMotion: true))
        #expect(!SessionIndicatorDot.shouldAnimate(isRunning: true, visible: false, active: true, reduceMotion: false))
        #expect(!SessionIndicatorDot.shouldAnimate(isRunning: true, visible: true, active: false, reduceMotion: false))
    }

    @Test @MainActor func successfulResponsesRemoveOnlyTheirSourceAndFailuresPreservePending() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.sessions = [Self.session("parent"), Self.session("child", parent: "parent"), Self.session("b", parent: "parent")]
        let p = Self.permission("p", session: "child")
        let sibling = Self.permission("sibling", session: "b")
        let q = Self.question("q", session: "child")
        await api.configureIndicators(permissions: [p, sibling], questions: [q])
        await state.refreshPendingPermissions()
        await state.refreshPendingQuestions()
        #expect(state.sessionAttentionCounts["parent"] == 3)
        await api.setIndicatorRequestsFail(true)
        #expect(await state.respondQuestion(q, answers: [[]]) == false)
        await state.respondPermission(state.pendingPermissions[0], response: .reject)
        #expect(state.sessionAttentionCounts["parent"] == 3)
        await api.setIndicatorRequestsFail(false)
        await state.respondPermission(state.pendingPermissions[0], response: .once)
        #expect(state.sessionAttentionCounts["parent"] == 2)
        await state.rejectQuestion(q)
        #expect(state.sessionAttentionCounts["child"] == nil)
        #expect(state.sessionAttentionCounts["parent"] == 1)
        #expect(state.pendingPermissions.first?.permissionID == "sibling")
    }

    @Test @MainActor func heartbeatDoesNotPreventPeriodicPollFromRepairingMissedIdle() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.statusStreamConnected = true
        state.serverCurrentProjectWorktree = "/test"
        state.sessions = [Self.session("a")]
        state.sessionStatuses["a"] = Self.status("busy")
        state.statusConfirmedAt["a"] = Date()
        state.statusLastAttemptAt = Date().addingTimeInterval(-31)
        try await Self.send(state, "server.heartbeat", [:])
        await state.refreshVisibleSessionStatus()
        #expect(state.sessionStatuses["a"]?.type == "idle")
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .unread)
        state.statusConfirmedAt = [:]
        state.sessionStatuses = [:]
        await api.setIndicatorRequestsFail(true)
        await state.syncSessionStatusesFromPoll()
        #expect(state.sessionStatuses.isEmpty)
        #expect(state.sessionIndicatorPresentations["a"]?.needsSync == true)
    }

    @Test @MainActor func backgroundInvalidationRejectsInFlightSnapshot() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/test"
        state.sessions = [Self.session("a")]
        await api.configureIndicators(statuses: ["a": Self.status("busy")], suspended: true)
        let task = Task { await state.syncSessionStatusesFromPoll() }
        await Self.waitForRequests(api, count: 1)
        state.invalidateSessionStatusKnowledge()
        await api.resumeIndicatorRequests()
        await task.value
        #expect(state.statusConfirmedAt.isEmpty)
        #expect(state.sessionStatuses.isEmpty)
    }

    @Test @MainActor func abortErrorDoesNotErasePriorUnacknowledgedFailure() async throws {
        let state = Self.state()
        state.sessions = [Self.session("a")]
        let previousFailure = Date(timeIntervalSince1970: 100)
        state.readStateStore.markFailed(sessionID: "a", at: previousFailure)
        try await Self.send(state, "session.status", ["sessionID": "a", "status": ["type": "busy"]])
        try await Self.send(state, "session.error", ["sessionID": "a", "error": ["name": "AbortError"]])
        try await Self.send(state, "session.status", ["sessionID": "a", "status": ["type": "idle"]])
        #expect(state.readStateStore.failedAt(for: "a") == previousFailure)
        #expect(state.sessionIndicatorPresentations["a"]?.indicator == .failed)
    }

    private static func permission(_ id: String, session: String) -> APIClient.PermissionRequest {
        .init(id: id, sessionID: session, permission: "edit", patterns: nil, metadata: nil, always: nil, tool: nil)
    }

    @MainActor private static func question(_ id: String, session: String) -> QuestionRequest {
        try! JSONDecoder().decode(QuestionRequest.self, from: Data("{\"id\":\"\(id)\",\"sessionID\":\"\(session)\",\"questions\":[]}".utf8))
    }

    @MainActor private static func send(_ state: AppState, _ type: String, _ props: [String: Any], directory: String? = nil) async throws {
        var envelope: [String: Any] = ["payload": ["type": type, "properties": props]]
        if let directory { envelope["directory"] = directory }
        let data = try JSONSerialization.data(withJSONObject: envelope)
        await state.applySSEEventForTesting(try JSONDecoder().decode(SSEEvent.self, from: data))
    }

    private static func waitForRequests(_ api: MockAPIClient, count: Int) async {
        for _ in 0..<10_000 {
            if await api.indicatorRequestCount >= count { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for suspended requests")
    }
}

@MainActor private final class IndicatorExpiryTestClock {
    var now = Date()
    var sleeper: CheckedContinuation<Void, Error>?
    var isSleeping: Bool { sleeper != nil }
    func sleep() async throws {
        try await withCheckedThrowingContinuation { sleeper = $0 }
    }
    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        let pending = sleeper
        sleeper = nil
        pending?.resume()
    }
    func cancelSleep() {
        sleeper?.resume(throwing: CancellationError())
        sleeper = nil
    }
}

private extension AppState {
    func rowIndicator(sessionID: String, attentionCount: Int) -> SessionIndicator? {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return nil }
        if !session.isArchived && attentionCount > 0 { return .needsYou }
        return sessionIndicatorPresentations[sessionID]?.indicator
    }
}
