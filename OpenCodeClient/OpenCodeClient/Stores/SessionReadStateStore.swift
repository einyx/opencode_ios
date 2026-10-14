import Foundation
import Observation

@Observable
final class SessionReadStateStore {
    private struct ReadState: Codable {
        var lastViewedAt: Date?
        var failedAt: Date?
        var blueAckBySource: [String: Int]?
    }

    private var states: [String: ReadState] = [:]
    private let defaults: UserDefaults
    private var storageKey = "sessionReadState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func selectHost(_ hostProfileID: UUID) {
        storageKey = "sessionReadState.v1.\(hostProfileID.uuidString)"
        load()
    }

    func lastViewedAt(for sessionID: String) -> Date? {
        states[sessionID]?.lastViewedAt
    }

    func failedAt(for sessionID: String) -> Date? {
        states[sessionID]?.failedAt
    }

    func blueAcknowledgements(for sessionID: String) -> [String: Int] {
        states[sessionID]?.blueAckBySource ?? [:]
    }

    func acknowledgeBlue(sessionID: String, sources: [String: Int]) {
        let valid = sources.filter { $0.key != sessionID && $0.value > 0 }
        guard !valid.isEmpty else { return }
        var state = states[sessionID] ?? ReadState()
        state.blueAckBySource = (state.blueAckBySource ?? [:]).merging(valid) { _, captured in captured }
        states[sessionID] = state
        save()
    }

    func markViewed(sessionID: String, at date: Date) {
        states[sessionID, default: ReadState()].lastViewedAt = date
        save()
    }

    func markFailed(sessionID: String, at date: Date) {
        states[sessionID, default: ReadState()].failedAt = date
        save()
    }

    func clearFailed(sessionID: String) {
        guard states[sessionID]?.failedAt != nil else { return }
        states[sessionID]?.failedAt = nil
        save()
    }

    func remove(sessionID: String) {
        var changed = states.removeValue(forKey: sessionID) != nil
        for rowID in Array(states.keys) {
            if states[rowID]?.blueAckBySource?.removeValue(forKey: sessionID) != nil {
                changed = true
            }
        }
        guard changed else { return }
        save()
    }

    private func load() {
        states = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: ReadState].self, from: $0) } ?? [:]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
