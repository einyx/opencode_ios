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
        store.acknowledgeBlue(sessionID: "same-id", sources: ["child": 100])
        store.selectHost(second)
        #expect(store.lastViewedAt(for: "same-id") == nil)
        #expect(store.blueAcknowledgements(for: "same-id").isEmpty)
        store.acknowledgeBlue(sessionID: "same-id", sources: ["child": 200])
        store.markFailed(sessionID: "same-id", at: viewed)
        store.selectHost(first)
        #expect(store.lastViewedAt(for: "same-id") == viewed)
        #expect(store.failedAt(for: "same-id") == nil)
        #expect(store.blueAcknowledgements(for: "same-id") == ["child": 100])
        let restored = SessionReadStateStore(defaults: defaults)
        restored.selectHost(second)
        #expect(restored.failedAt(for: "same-id") == viewed)
        #expect(restored.blueAcknowledgements(for: "same-id") == ["child": 200])
    }

    @Test func legacyJSONPreservesViewedAndFailedWhenAddingBlueAcknowledgements() throws {
        let suite = "SessionReadStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = UUID()
        // JSONEncoder's default Date representation is seconds since the reference date.
        let legacy = Data(#"{"parent":{"lastViewedAt":100,"failedAt":200},"child":{"failedAt":300}}"#.utf8)
        defaults.set(legacy, forKey: "sessionReadState.v1.\(host.uuidString)")
        let store = SessionReadStateStore(defaults: defaults)
        store.selectHost(host)
        #expect(store.lastViewedAt(for: "parent") == Date(timeIntervalSinceReferenceDate: 100))
        #expect(store.failedAt(for: "parent") == Date(timeIntervalSinceReferenceDate: 200))
        #expect(store.blueAcknowledgements(for: "parent").isEmpty)
        store.acknowledgeBlue(sessionID: "parent", sources: ["child": 100, "invalid": 0, "negative": -1, "parent": 50])
        let restored = SessionReadStateStore(defaults: defaults)
        restored.selectHost(host)
        #expect(restored.blueAcknowledgements(for: "parent") == ["child": 100])
        #expect(restored.lastViewedAt(for: "parent") == Date(timeIntervalSinceReferenceDate: 100))
        #expect(restored.failedAt(for: "parent") == Date(timeIntervalSinceReferenceDate: 200))
        #expect(restored.failedAt(for: "child") == Date(timeIntervalSinceReferenceDate: 300))
    }

    @Test func deletingSourceWithoutOwnRecordRemovesReferencesAndDeletingRowKeepsOtherRows() {
        let suite = "SessionReadStateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SessionReadStateStore(defaults: defaults)
        store.acknowledgeBlue(sessionID: "parent", sources: ["child": 100, "sibling": 200])
        store.acknowledgeBlue(sessionID: "grandparent", sources: ["child": 100, "sibling": 200])
        store.remove(sessionID: "child")
        #expect(store.blueAcknowledgements(for: "parent") == ["sibling": 200])
        #expect(store.blueAcknowledgements(for: "grandparent") == ["sibling": 200])
        store.remove(sessionID: "parent")
        let restored = SessionReadStateStore(defaults: defaults)
        #expect(restored.blueAcknowledgements(for: "parent").isEmpty)
        #expect(restored.blueAcknowledgements(for: "grandparent") == ["sibling": 200])
    }
}
