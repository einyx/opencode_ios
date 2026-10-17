import CoreGraphics
import Foundation

nonisolated enum CarLiveDetailsFormat {
    struct TokenText: Equatable {
        var display: String
        var exactAccessibility: String
    }

    enum DurationPresentation: Equatable {
        case unknown
        case clock(String, unconfirmed: Bool)
    }

    enum CostPresentation: Equatable {
        case unknown
        case amount(String)
        case unconfirmed(String?)

        func valueText(unknown: String, unconfirmedLabel: String) -> String {
            switch self {
            case .unknown:
                return unknown
            case .amount(let text):
                return text
            case .unconfirmed(.none):
                return unconfirmedLabel
            case .unconfirmed(.some(let text)):
                return "\(text) \(unconfirmedLabel)"
            }
        }
    }

    static func voiceDuration(seconds: Double, known: Bool, unconfirmed: Bool) -> DurationPresentation {
        guard known, let text = clock(seconds: seconds) else { return .unknown }
        return .clock(text, unconfirmed: unconfirmed)
    }

    static func sessionDuration(seconds: Int) -> DurationPresentation {
        guard let text = clock(totalSeconds: seconds) else { return .unknown }
        return .clock(text, unconfirmed: false)
    }

    static func tokens(_ count: Int) -> TokenText {
        let exact = String(count)
        guard count >= 1_000 else {
            return TokenText(display: exact, exactAccessibility: exact)
        }
        let units = ["K", "M", "B"]
        var divisor = Decimal(1_000)
        let magnitude = Decimal(count)
        for (index, unit) in units.enumerated() {
            let rounded = roundHalfUp(magnitude / divisor, scale: 2)
            let lastUnit = index == units.count - 1
            if rounded < 1_000 || lastUnit {
                return TokenText(
                    display: decimalString(rounded, minimumFractionDigits: 0, maximumFractionDigits: 2) + unit,
                    exactAccessibility: exact
                )
            }
            divisor *= 1_000
        }
        return TokenText(display: exact, exactAccessibility: exact)
    }

    static func localCost(usd: Double, unpricedCount: Int) -> CostPresentation {
        guard let text = usdText(usd) else { return .unknown }
        if unpricedCount > 0 {
            if usd == 0 { return .unconfirmed(nil) }
            return .unconfirmed(text)
        }
        return .amount(text)
    }

    static func portalCost(usd: Double?, settled: Bool) -> CostPresentation {
        guard let usd else { return .unknown }
        guard let text = usdText(usd) else { return .unknown }
        if !settled {
            if usd == 0 { return .unconfirmed(nil) }
            return .unconfirmed(text)
        }
        return .amount(text)
    }

    static func level(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func metricColumnCount(containerWidth: CGFloat, accessibilityText: Bool) -> Int {
        if accessibilityText || containerWidth < 240 { return 1 }
        if containerWidth < 560 { return 2 }
        if containerWidth < 800 { return 3 }
        return 4
    }

    static func clock(seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let floored = seconds.rounded(.down)
        guard floored <= Double(Int.max), let total = Int(exactly: floored) else { return nil }
        return clock(totalSeconds: total)
    }

    static func clock(totalSeconds: Int) -> String? {
        guard totalSeconds >= 0 else { return nil }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return "\(padded(hours)):\(padded(minutes)):\(padded(seconds))"
    }

    private static func padded(_ value: Int) -> String {
        let digits = String(value)
        if digits.count >= 2 { return digits }
        return String(repeating: "0", count: 2 - digits.count) + digits
    }

    private static func usdText(_ amount: Double) -> String? {
        guard amount.isFinite, amount >= 0 else { return nil }
        if amount == 0 { return "$0.00" }
        if amount < 0.01 { return "<$0.01" }
        let token = String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), amount)
        guard let decimal = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let rounded = roundHalfUp(decimal, scale: 2)
        return "$" + decimalString(rounded, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    private static func roundHalfUp(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    private static func decimalString(
        _ value: Decimal,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }
}
