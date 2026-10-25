import Foundation
import Observation

enum CarVoiceMode {
    static let storageKey = "carVoiceMode.v1"
    static let hostedLive = "hostedLive"
    static let turnByTurn = "turnByTurn"
}

nonisolated enum CarLiveRow: Equatable, Identifiable {
    case caption(id: String, role: String, text: String)
    case tool(id: String, name: String, arguments: String, status: String, result: String)

    var id: String {
        switch self {
        case .caption(let id, _, _):
            return "c-\(id)"
        case .tool(let id, _, _, _, _):
            return "t-\(id)"
        }
    }

    var followKey: String {
        switch self {
        case .caption(let id, _, let text):
            return "c|\(id)|\(text)"
        case .tool(let id, _, let arguments, let status, let result):
            return "t|\(id)|\(status)|\(arguments)|\(result)"
        }
    }
}

enum CarLiveTimeline {
    nonisolated static func rows(captions: [CarLiveCaption], activities: [CarLiveActivity]) -> [CarLiveRow] {
        var indexed: [(sequence: Int, tie: Int, row: CarLiveRow)] = []
        for (offset, caption) in captions.enumerated() {
            indexed.append((
                caption.sequence,
                offset,
                .caption(id: caption.id, role: caption.role, text: caption.text)
            ))
        }
        let captionCount = captions.count
        for (offset, activity) in activities.enumerated() {
            indexed.append((
                activity.sequence,
                captionCount + offset,
                .tool(
                    id: activity.id,
                    name: activity.name,
                    arguments: activity.arguments,
                    status: activity.status,
                    result: activity.result
                )
            ))
        }
        return indexed.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.tie < rhs.tie
        }.map(\.row)
    }

    static func kind(_ row: CarLiveRow) -> String {
        switch row {
        case .caption(_, let role, _):
            return role
        case .tool:
            return "tool"
        }
    }
}

enum CarLiveScenePolicy {
    enum Phase: Equatable {
        case active
        case inactive
        case background
    }

    static func shouldRelinquish(_ phase: Phase) -> Bool {
        phase == .background
    }
}

enum CarLivePresentation {
    static func showsError(_ snapshot: CarLiveSnapshot) -> Bool {
        snapshot.phase == .failed || snapshot.hasVisibleError
    }

    static func errorLine(_ snapshot: CarLiveSnapshot) -> String {
        CarLiveErrorText.line(from: snapshot.errorMessage)
    }
}

nonisolated struct CarLiveSnapshot: Equatable {
    var phase: CarLivePhase = .idle
    var captions: [CarLiveCaption] = []
    var activities: [CarLiveActivity] = []
    var inputLevel: Double = 0
    var outputLevel: Double = 0
    var elapsedSeconds: Int = 0
    var voiceSeconds: Double = 0
    var inputTokens: Int = 0
    var cachedRead: Int = 0
    var cacheWrite: Int = 0
    var outputTokens: Int = 0
    var localEstimatedUSD: Double = 0
    var portalEstimatedUSD: Double?
    var usageUnconfirmed = false
    var voiceDurationKnown = false
    var voiceDurationUnconfirmed = false
    var localUnpricedCount = 0
    var portalSettled = false
    var errorMessage: String?
    var isMuted = false

    var hasVisibleError: Bool {
        guard let errorMessage else { return false }
        return !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isSessionUp: Bool {
        switch phase {
        case .connecting, .listening, .speaking:
            return true
        case .idle, .closing, .failed:
            return false
        }
    }

    var rows: [CarLiveRow] {
        CarLiveTimeline.rows(captions: captions, activities: activities)
    }

    var followToken: String {
        rows.map(\.followKey).joined(separator: "\u{1e}")
    }

    static let disconnected = CarLiveSnapshot()

    mutating func updateToolResult() {
        guard let index = activities.firstIndex(where: { $0.id == "echo" }) else { return }
        activities[index].result = "FIXTURE_TOOL_UPDATE_SENTINEL"
    }
}

@MainActor
@Observable
final class CarLiveFixtureSession {
    static let shared = CarLiveFixtureSession()
    var snapshot = CarLiveFixture.connectedSnapshot()

    private init() {}
}

enum CarLiveFixture {
    static var isActive: Bool {
        UITestFixtures.hasUITestCarLiveFixture
    }

    static var opensDetails: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("UITEST_CAR_LIVE_DETAILS_OPEN")
    }

    static var usesAccessibilityText: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("UITEST_CAR_LIVE_ACCESSIBILITY_TEXT")
    }

    static func idleErrorSnapshot() -> CarLiveSnapshot {
        var snapshot = CarLiveSnapshot()
        snapshot.phase = .idle
        snapshot.errorMessage = CarLiveCopy.notConnected
        return snapshot
    }

    static func connectedSnapshot() -> CarLiveSnapshot {
        var captions: [CarLiveCaption] = [
            CarLiveCaption(id: "early", role: "user", text: "EARLY_CAPTION_SENTINEL", sequence: 1),
            CarLiveCaption(id: "reply", role: "assistant", text: "ASSISTANT_CAPTION_SENTINEL", sequence: 2),
        ]
        for index in 1...28 {
            captions.append(
                CarLiveCaption(
                    id: "pad-\(index)",
                    role: index.isMultiple(of: 2) ? "assistant" : "user",
                    text: "ROW \(index)",
                    sequence: index + 2
                )
            )
        }
        let activities = [
            CarLiveActivity(
                id: "echo",
                name: "echo",
                arguments: "text=ok",
                status: "sent",
                result: "ok",
                sequence: 31
            ),
        ]
        var snapshot = CarLiveSnapshot(
            phase: .listening,
            captions: captions,
            activities: activities,
            inputLevel: 0.40,
            outputLevel: 0.20,
            elapsedSeconds: 90_061,
            voiceSeconds: 12.9,
            inputTokens: 1_234_567,
            cachedRead: 999,
            cacheWrite: 1_500,
            outputTokens: 1_200,
            localEstimatedUSD: 0.12,
            portalEstimatedUSD: 0.34,
            usageUnconfirmed: true,
            voiceDurationKnown: true,
            errorMessage: nil,
            isMuted: false
        )
        applyMeterPreset(&snapshot)
        return snapshot
    }

    static func applyMeterPreset(_ snapshot: inout CarLiveSnapshot) {
        let preset = CarLiveMeterPreset.resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        snapshot = CarLiveMeterPreset.applying(preset, active: isActive, to: snapshot)
    }
}

enum CarLiveMeterPreset: String, Equatable {
    case quiet
    case mid
    case high
    case muted

    static let quietLevel = 0.02
    static let midLevel = 0.08
    static let highLevel = 0.15
    static let mutedLevel = 0.08

    var inputLevel: Double {
        switch self {
        case .quiet:
            return Self.quietLevel
        case .mid:
            return Self.midLevel
        case .high:
            return Self.highLevel
        case .muted:
            return Self.mutedLevel
        }
    }

    var isMuted: Bool {
        self == .muted
    }

    static func applying(_ preset: CarLiveMeterPreset?, active: Bool, to snapshot: CarLiveSnapshot) -> CarLiveSnapshot {
        guard active, let preset else { return snapshot }
        var next = snapshot
        next.phase = .listening
        next.inputLevel = preset.inputLevel
        next.isMuted = preset.isMuted
        return next
    }

    static func resolve(arguments: [String], environment: [String: String]) -> CarLiveMeterPreset? {
        if arguments.contains("UITEST_CAR_LIVE_METER_QUIET") { return .quiet }
        if arguments.contains("UITEST_CAR_LIVE_METER_MID") { return .mid }
        if arguments.contains("UITEST_CAR_LIVE_METER_HIGH") { return .high }
        if arguments.contains("UITEST_CAR_LIVE_METER_MUTED") { return .muted }
        let raw = environment["UITEST_CAR_LIVE_METER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw else { return nil }
        return CarLiveMeterPreset(rawValue: raw)
    }
}

enum CarLiveErrorText {
    static func line(from raw: String?) -> String {
        let fallback = L10n.t(.carLiveConnectFailedError)
        guard let raw else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return fallback }
        let lowered = trimmed.lowercased()
        if lowered.contains("://") || trimmed.contains("@") { return fallback }
        let blocked = ["password", "ticket", "secret", "bearer", "authorization", "api_key", "apikey", "private key"]
        if blocked.contains(where: { lowered.contains($0) }) { return fallback }
        return trimmed
    }
}
