import Foundation
import Testing
@testable import OpenCodeClient

struct SessionReadStateStoreTests {
    @Test func mutationsPersistAndKeepSessionsIndependent() throws {
        let suite = "SessionReadStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let viewed = Date(timeIntervalSince1970: 100)
        let failed = Date(timeIntervalSince1970: 200)
        let store = SessionReadStateStore(defaults: defaults)
        #expect(store.lastViewedAt(for: "a") == nil)
        #expect(store.failedAt(for: "a") == nil)
        store.markViewed(sessionID: "a", at: viewed)
        store.markFailed(sessionID: "a", at: failed)
        store.markFailed(sessionID: "b", at: failed)

        let restored = SessionReadStateStore(defaults: defaults)
        #expect(restored.lastViewedAt(for: "a") == viewed)
        #expect(restored.failedAt(for: "a") == failed)
        restored.clearFailed(sessionID: "a")
        let cleared = SessionReadStateStore(defaults: defaults)
        #expect(cleared.failedAt(for: "a") == nil)
        #expect(cleared.lastViewedAt(for: "a") == viewed)
        #expect(cleared.failedAt(for: "b") == failed)
        cleared.remove(sessionID: "a")
        let removed = SessionReadStateStore(defaults: defaults)
        #expect(removed.lastViewedAt(for: "a") == nil)
        #expect(removed.failedAt(for: "a") == nil)
        #expect(removed.failedAt(for: "b") == failed)
    }

    @Test func hostNamespacesPersistIndependently() {
        let defaults = UserDefaults(suiteName: "SessionReadStateStoreTests.\(UUID().uuidString)")!
        let store = SessionReadStateStore(defaults: defaults)
        let first = UUID()
        let second = UUID()
        let viewed = Date(timeIntervalSince1970: 100)
        store.selectHost(first)
        store.markViewed(sessionID: "same-id", at: viewed)
        store.selectHost(second)
        #expect(store.lastViewedAt(for: "same-id") == nil)
        store.markFailed(sessionID: "same-id", at: viewed)
        store.selectHost(first)
        #expect(store.lastViewedAt(for: "same-id") == viewed)
        #expect(store.failedAt(for: "same-id") == nil)
        let restored = SessionReadStateStore(defaults: defaults)
        restored.selectHost(second)
        #expect(restored.failedAt(for: "same-id") == viewed)
    }
}
