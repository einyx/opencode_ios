import Foundation
import Testing
@testable import OpenCodeClient

@Suite(.serialized)
struct HIGSessionSearchTests {
    @Test @MainActor func successfulCreationReturnsSuccessAndOfflineCreationDoesNot() async {
        let name = "hig-create.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), userDefaults: defaults)
        state.isConnected = false
        #expect(await state.createSession() == false)
        state.isConnected = true
        #expect(await state.createSession())
        #expect(state.currentSessionID != nil)
        #expect(state.sessions.contains(where: { $0.id == state.currentSessionID }))
    }

    @Test @MainActor func searchRetainsAncestorsOfMatchingDescendantsAndSeparatesArchives() {
        let name = "hig-search.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(), userDefaults: defaults)
        state.sessions = [
            session("parent", title: "Project"),
            session("child", title: "Fix NETWORK issue", parent: "parent"),
            session("unrelated", title: "Other work"),
            session("archived", title: "Network archive", archived: true)
        ]
        let active = state.sessionTree(archived: false, query: " network ")
        #expect(active.map(\.id) == ["parent"])
        #expect(active.first?.children.map(\.id) == ["child"])
        #expect(state.sessionTree(archived: true, query: "network").map(\.id) == ["archived"])
        #expect(state.sessionTree(archived: false, query: "missing").isEmpty)
        #expect(state.sessionTree(archived: false, query: "  ").count == 2)
    }

    private func session(_ id: String, title: String, parent: String? = nil, archived: Bool = false) -> Session {
        Session(id: id, slug: id, projectID: "fixture", directory: "/fixture", parentID: parent,
                title: title, version: "1", time: .init(created: 1, updated: 2, archived: archived ? 3 : nil),
                share: nil, summary: nil)
    }
}
