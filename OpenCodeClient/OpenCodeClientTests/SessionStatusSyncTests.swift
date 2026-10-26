import Foundation
import Testing

@testable import OpenCodeClient

/// The status poll covers only the sessions of the effective project
/// directory. Sessions outside it must not be reported as "Status awaiting
/// sync" — the poll never confirms them, so that label used to stick forever.
@MainActor
struct SessionStatusSyncTests {
    private func makeState() -> AppState {
        makeIsolatedAppState()
    }

    private func session(_ id: String, directory: String) -> Session {
        Session(id: id, slug: id, projectID: "p", directory: directory, parentID: nil, title: id,
                version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
    }

    @Test func sessionOutsideThePolledDirectoryIsNotAwaitingSync() {
        let state = makeState()
        state.sessions = [session("in", directory: "/work/a"), session("out", directory: "/work/b")]
        state.selectedProjectWorktree = "/work/a"
        state.statusStreamConnected = true
        state.isConnected = true
        state.statusConfirmedAt["in"] = Date()

        let presentations = state.sessionIndicatorPresentations
        #expect(presentations["in"]?.needsSync == false)
        // Not tracked ≠ awaiting sync: no claim is made for it.
        #expect(presentations["out"]?.needsSync == false)
    }

    @Test func staleSessionInThePolledDirectoryIsAwaitingSync() {
        let state = makeState()
        state.sessions = [session("in", directory: "/work/a")]
        state.selectedProjectWorktree = "/work/a"
        state.statusStreamConnected = true
        state.isConnected = true
        // The last confirmation is older than the freshness window.
        state.statusConfirmedAt["in"] = Date().addingTimeInterval(-120)

        let presentations = state.sessionIndicatorPresentations
        #expect(presentations["in"]?.needsSync == true)
    }

    @Test func sessionInsideThePolledDirectoryWithAFreshStatusIsSettled() {
        let state = makeState()
        state.sessions = [session("in", directory: "/work/a")]
        state.selectedProjectWorktree = "/work/a"
        state.statusStreamConnected = true
        state.isConnected = true
        state.statusConfirmedAt["in"] = Date()
        state.sessionStatuses["in"] = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)

        let presentations = state.sessionIndicatorPresentations
        #expect(presentations["in"]?.needsSync == false)
    }
}
