import Foundation

enum OrderedServerID {
    nonisolated private static let bodyLength = 26
    nonisolated private static let timeLength = 12
    nonisolated private static let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    nonisolated private static let state = GeneratorState()

    nonisolated static func make(prefix: String, timestamp: Int = Int(Date().timeIntervalSince1970 * 1000)) -> String {
        makeBatch(prefix: prefix, count: 1, timestamp: timestamp)[0]
    }

    nonisolated static func makeBatch(prefix: String, count: Int, timestamp: Int) -> [String] {
        state.lock.lock()
        defer { state.lock.unlock() }
        if timestamp != state.lastTimestamp {
            state.lastTimestamp = timestamp
            state.counter = 0
        }
        return (0..<count).map { _ in
            state.counter += 1
            return prefix + "_" + body(timestamp: timestamp, counter: state.counter)
        }
    }

    nonisolated static func body(timestamp: Int, counter: Int) -> String {
        let current = UInt64(max(timestamp, 0)) * 0x1000 + UInt64(max(counter, 0))
        var time = ""
        time.reserveCapacity(timeLength)
        var shift = 40
        while shift >= 0 {
            let byte = Int((current >> UInt64(shift)) & 0xff)
            time += String(format: "%02x", byte)
            shift -= 8
        }
        return time + randomSuffix(bodyLength - timeLength)
    }

    nonisolated static func isOrdered(_ id: String, prefix: String) -> Bool {
        let marker = prefix + "_"
        guard id.hasPrefix(marker) else { return false }
        let body = id.dropFirst(marker.count)
        guard body.count == bodyLength else { return false }
        let time = body.prefix(timeLength)
        let suffix = body.suffix(bodyLength - timeLength)
        return time.allSatisfy(\.isHexDigit) && suffix.allSatisfy { chars.contains($0) }
    }

    nonisolated private static func randomSuffix(_ length: Int) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            let byte = UInt8.random(in: 0...255)
            result.append(chars[Int(byte) % chars.count])
        }
        return result
    }

    nonisolated private final class GeneratorState: @unchecked Sendable {
        let lock = NSLock()
        var lastTimestamp = 0
        var counter = 0
    }
}
