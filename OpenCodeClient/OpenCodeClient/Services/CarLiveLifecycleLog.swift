import Foundation

nonisolated enum CarLiveLifecycleKind {
    static let closeBegin = "close_begin"
    static let closeEnd = "close_end"
    static let closeJoin = "close_join"
    static let sendDeadline = "send_deadline"
    static let playbackClear = "playback_clear"
    static let playbackSkipPlay = "playback_skip_play"
    static let serverClose = "server_close"
    static let failClosed = "fail_closed"
    static let appClose = "app_close"
    static let budgetExceeded = "budget_exceeded"
    static let audioStopDeadline = "audio_stop_deadline"
    static let audioSendDeadline = "audio_send_deadline"
    static let audioStopQueued = "audio_stop_queued"
    static let audioStopBegin = "audio_stop_begin"
    static let audioTapRemoved = "audio_tap_removed"
    static let audioEngineStopped = "audio_engine_stopped"
    static let audioStopEnd = "audio_stop_end"
    static let audioHold = "audio_hold"
    static let audioHeartbeat = "audio_heartbeat"
    static let watchActive = "watch_active"
    static let watchInactive = "watch_inactive"
    static let watchBackground = "watch_background"
    static let socketOpened = "socket_opened"
    static let socketClosed = "socket_closed"
    static let socketCompleted = "socket_completed"
    static let socketSendFailed = "socket_send_failed"
    static let socketReceiveFailed = "socket_receive_failed"
    static let socketSendDeadline = "socket_send_deadline"
    static let other = "other"

    static let events: Set<String> = [
        closeBegin, closeEnd, closeJoin, sendDeadline, playbackClear, playbackSkipPlay,
        serverClose, failClosed, appClose, budgetExceeded, audioStopDeadline, audioSendDeadline,
        audioStopQueued, audioStopBegin, audioTapRemoved, audioEngineStopped, audioStopEnd, audioHold,
        audioHeartbeat, watchActive, watchInactive, watchBackground,
        socketOpened, socketClosed, socketCompleted, socketSendFailed, socketReceiveFailed, socketSendDeadline, other
    ]
    static let phases: Set<String> = [
        "idle", "connecting", "listening", "speaking", "closing", "failed", "audio", "app", "network", other
    ]
    static let errors: Set<String> = [
        "none", "send_timeout", "cancelled", "playback_skip", "budget_exceeded", "usage_unconfirmed", other
    ]
    static let relativePath = "Library/Application Support/CarLiveLifecycle/events.jsonl"
}

nonisolated struct CarLiveLifecycleRecord: Equatable, Sendable {
    var timeMS: Int = 0
    var runHash: Int = 0
    var phase: String = "other"
    var event: String = CarLiveLifecycleKind.other
    var errorCode: String = "none"
    var taskCancelled: Bool = false
    var closeBegan: Bool = false
    var closeEnded: Bool = false
    var deadlineRemainingMS: Int = 0
    var engineRunning: Bool = false
    var intendedRunning: Bool = false
    var playerAttached: Bool = false
    var stopping: Bool = false
    var closeSeen: Bool = false
    var sendDeadlines: Int = 0
    var playbackSkips: Int = 0
    var stopJoins: Int = 0
    var inputFrames: Int = 0
    var sentFrames: Int = 0
    var outputFrames: Int = 0
    var socketState: Int = 0
    var socketCloseCode: Int = 0
    var networkErrorCode: Int = 0
    var networkBytesSent: Int64 = 0
    var networkBytesReceived: Int64 = 0
    var networkErrorDomain: String = "none"
}

nonisolated final class CarLiveLifecycleLog: @unchecked Sendable {
    static let shared = CarLiveLifecycleLog(directory: defaultDirectory())
    static let allowedKeys: Set<String> = [
        "timeMS", "runHash", "phase", "event", "errorCode", "taskCancelled",
        "closeBegan", "closeEnded", "deadlineRemainingMS", "engineRunning",
        "intendedRunning", "playerAttached", "stopping", "closeSeen",
        "sendDeadlines", "playbackSkips", "stopJoins", "inputFrames", "sentFrames", "outputFrames",
        "socketState", "socketCloseCode", "networkErrorCode", "networkBytesSent", "networkBytesReceived", "networkErrorDomain"
    ]
    static let maxBytesDefault = 128 * 1024

    private let queue = DispatchQueue(label: "com.grapeot.OpenCodeClient.carlive.lifecycle", qos: .utility)
    private let directory: URL
    private let maxBytes: Int
    private let origin = ContinuousClock.now
    private var sendDeadlines = 0
    private var playbackSkips = 0
    private var stopJoins = 0
    private var closeBegins = 0
    private var closeEnds = 0

    init(directory: URL, maxBytes: Int = CarLiveLifecycleLog.maxBytesDefault) {
        self.directory = directory
        self.maxBytes = max(4_096, maxBytes)
    }

    func note(_ record: CarLiveLifecycleRecord) {
        queue.async {
            self.append(record)
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    static func jsonObject(for record: CarLiveLifecycleRecord) -> [String: Any] {
        let safe = sanitized(record)
        return [
            "timeMS": safe.timeMS,
            "runHash": safe.runHash,
            "phase": safe.phase,
            "event": safe.event,
            "errorCode": safe.errorCode,
            "taskCancelled": safe.taskCancelled,
            "closeBegan": safe.closeBegan,
            "closeEnded": safe.closeEnded,
            "deadlineRemainingMS": safe.deadlineRemainingMS,
            "engineRunning": safe.engineRunning,
            "intendedRunning": safe.intendedRunning,
            "playerAttached": safe.playerAttached,
            "stopping": safe.stopping,
            "closeSeen": safe.closeSeen,
            "sendDeadlines": safe.sendDeadlines,
            "playbackSkips": safe.playbackSkips,
            "stopJoins": safe.stopJoins,
            "inputFrames": safe.inputFrames,
            "sentFrames": safe.sentFrames,
            "outputFrames": safe.outputFrames,
            "socketState": safe.socketState,
            "socketCloseCode": safe.socketCloseCode,
            "networkErrorCode": safe.networkErrorCode,
            "networkBytesSent": safe.networkBytesSent,
            "networkBytesReceived": safe.networkBytesReceived,
            "networkErrorDomain": safe.networkErrorDomain
        ]
    }

    static func sanitized(_ record: CarLiveLifecycleRecord) -> CarLiveLifecycleRecord {
        var copy = record
        copy.phase = CarLiveLifecycleKind.phases.contains(record.phase) ? record.phase : CarLiveLifecycleKind.other
        copy.event = CarLiveLifecycleKind.events.contains(record.event) ? record.event : CarLiveLifecycleKind.other
        copy.errorCode = CarLiveLifecycleKind.errors.contains(record.errorCode) ? record.errorCode : CarLiveLifecycleKind.other
        let domains: Set<String> = ["none", "other", NSURLErrorDomain, NSPOSIXErrorDomain, NSCocoaErrorDomain]
        copy.networkErrorDomain = domains.contains(record.networkErrorDomain) ? record.networkErrorDomain : "other"
        return copy
    }

    static func runHash(_ token: UInt64) -> Int {
        var hasher = Hasher()
        hasher.combine(token)
        hasher.combine("carlive-run")
        return hasher.finalize()
    }

    var fileURL: URL {
        directory.appendingPathComponent("events.jsonl")
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CarLiveLifecycle", isDirectory: true)
    }

    private func append(_ record: CarLiveLifecycleRecord) {
        var stamped = Self.sanitized(record)
        if stamped.timeMS == 0 {
            stamped.timeMS = nowMS()
        }
        switch stamped.event {
        case CarLiveLifecycleKind.sendDeadline:
            sendDeadlines += 1
        case CarLiveLifecycleKind.playbackSkipPlay:
            playbackSkips += 1
        case CarLiveLifecycleKind.closeJoin:
            stopJoins += 1
        case CarLiveLifecycleKind.closeBegin, CarLiveLifecycleKind.appClose:
            closeBegins += 1
        case CarLiveLifecycleKind.closeEnd:
            closeEnds += 1
        default:
            break
        }
        stamped.sendDeadlines = sendDeadlines
        stamped.playbackSkips = playbackSkips
        stamped.stopJoins = stopJoins
        let object = Self.jsonObject(for: stamped)
        guard JSONSerialization.isValidJSONObject(object),
              var line = try? JSONSerialization.data(withJSONObject: object) else { return }
        line.append(0x0A)
        let file = fileURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path),
           let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file, options: .atomic)
        }
        trimIfNeeded(file)
    }

    private func nowMS() -> Int {
        let parts = origin.duration(to: .now).components
        return Int(parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
    }

    private func trimIfNeeded(_ file: URL) {
        guard let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: file) else { return }
        let keep = data.suffix(maxBytes / 2)
        guard let newline = keep.firstIndex(of: 0x0A) else {
            try? Data().write(to: file, options: .atomic)
            return
        }
        let start = keep.index(after: newline)
        guard start < keep.endIndex else {
            try? Data().write(to: file, options: .atomic)
            return
        }
        try? Data(keep[start...]).write(to: file, options: .atomic)
    }
}
