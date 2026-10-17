import Foundation

nonisolated final class CarLiveClock: @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: TimeInterval?

    func now() -> TimeInterval {
        lock.withLock {
            pinned ?? ProcessInfo.processInfo.systemUptime
        }
    }

    func pin(_ value: TimeInterval) {
        lock.withLock { pinned = value }
    }
}

nonisolated struct CarLiveDiagnosticSnapshot: Equatable, Sendable {
    var captionOpens = 0
    var captionAppends = 0
    var bargeBegins = 0
    var bargeEnds = 0
    var playbackClears = 0
    var playbackDrops = 0
    var lastKind = "none"
    var lastAt: TimeInterval = 0
    var inputBucket = 0
    var outputActive = false
    var turnHash = 0
}

nonisolated struct CarLiveDiagnostics: Equatable, Sendable {
    private(set) var snapshot = CarLiveDiagnosticSnapshot()

    static let allowedKeys: Set<String> = [
        "captionOpens", "captionAppends", "bargeBegins", "bargeEnds",
        "playbackClears", "playbackDrops", "lastKind", "lastAt",
        "inputBucket", "outputActive", "turnHash"
    ]

    static let kinds: Set<String> = [
        "none", "other", "caption_open", "caption_append", "barge_begin", "barge_end",
        "playback_drop", "playback_clear", "stop"
    ]

    mutating func reset() {
        snapshot = CarLiveDiagnosticSnapshot()
    }

    mutating func note(kind: String, at: TimeInterval, inputLevel: Double, outputActive: Bool, turnHash: Int) {
        let safe = Self.kinds.contains(kind) ? kind : "other"
        switch safe {
        case "caption_open":
            snapshot.captionOpens += 1
        case "caption_append":
            snapshot.captionAppends += 1
        case "barge_begin":
            snapshot.bargeBegins += 1
        case "barge_end":
            snapshot.bargeEnds += 1
        case "playback_clear":
            snapshot.playbackClears += 1
        case "playback_drop":
            snapshot.playbackDrops += 1
        default:
            break
        }
        snapshot.lastKind = safe
        snapshot.lastAt = at
        snapshot.inputBucket = min(10, max(0, Int((inputLevel * 10).rounded())))
        snapshot.outputActive = outputActive
        snapshot.turnHash = turnHash
    }

    func encoded() -> Data {
        let object: [String: Any] = [
            "captionOpens": snapshot.captionOpens,
            "captionAppends": snapshot.captionAppends,
            "bargeBegins": snapshot.bargeBegins,
            "bargeEnds": snapshot.bargeEnds,
            "playbackClears": snapshot.playbackClears,
            "playbackDrops": snapshot.playbackDrops,
            "lastKind": snapshot.lastKind,
            "lastAt": snapshot.lastAt,
            "inputBucket": snapshot.inputBucket,
            "outputActive": snapshot.outputActive,
            "turnHash": snapshot.turnHash
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
