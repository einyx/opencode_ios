import Foundation
import CryptoKit

nonisolated enum WatchBridgeWire {
    static let version = 1
    static let chunkBytes = 8192
    static let maxOutputBytes = 64 * 1024
    static let maxArgumentsBytes = 24 * 1024
    static let maxCalls = 128
    static let maxRunSeconds: TimeInterval = 60

    static func envelope(_ op: String, run: String = "", call: String = "") -> [String: Any] {
        ["v": version, "op": op, "run": run, "call": call]
    }

    static func error(_ code: String) -> [String: Any] {
        ["v": version, "error": code]
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0)
        }
    }
}

/// Per-run deduplication; a released blob leaves a tombstone, never permission to execute again.
@MainActor
final class WatchCallLedger {
    struct Record {
        var fingerprint: String
        var output: Data?
        var finished = false
        var unknown = false
    }
    private(set) var records: [String: Record] = [:]

    func claim(id: String, name: String, arguments: String) -> String {
        let fingerprint = WatchBridgeWire.digest(Data((name + "\n" + arguments).utf8))
        if let existing = records[id] {
            return existing.fingerprint == fingerprint ? "duplicate" : "call_conflict"
        }
        guard WatchBridgeWire.validID(id), records.count < WatchBridgeWire.maxCalls else { return "limit" }
        guard !records.values.contains(where: { !$0.finished }) else { return "busy" }
        records[id] = Record(fingerprint: fingerprint)
        return "accepted"
    }

    func finish(id: String, output: String) {
        guard var record = records[id], !record.finished else { return }
        let bytes = Data(output.utf8)
        record.finished = true
        record.unknown = bytes.count > WatchBridgeWire.maxOutputBytes
        record.output = record.unknown ? nil : bytes
        records[id] = record
    }

    func markUnknown(id: String) {
        guard var record = records[id], !record.finished else { return }
        record.finished = true
        record.unknown = true
        records[id] = record
    }

    func header(id: String) -> [String: Any] {
        guard let record = records[id] else { return WatchBridgeWire.error("missing_call") }
        guard record.finished else { return ["status": "pending"] }
        guard !record.unknown, let data = record.output else { return ["status": "unknown"] }
        return ["status": "ready", "bytes": data.count, "sha256": WatchBridgeWire.digest(data),
                "chunks": (data.count + WatchBridgeWire.chunkBytes - 1) / WatchBridgeWire.chunkBytes]
    }

    func chunk(id: String, sequence: Int) -> Data? {
        guard sequence >= 0, let data = records[id]?.output else { return nil }
        let start = sequence * WatchBridgeWire.chunkBytes
        guard start < data.count else { return nil }
        return data.subdata(in: start..<min(data.count, start + WatchBridgeWire.chunkBytes))
    }

    func acknowledge(id: String, digest: String) {
        guard var record = records[id], let data = record.output,
              WatchBridgeWire.digest(data) == digest else { return }
        record.output = nil
        record.unknown = true
        records[id] = record
    }
}
