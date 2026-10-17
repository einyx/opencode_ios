import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveDetailsFormatTests {
    @Test func durationUsesHourClockWithoutDayWrap() {
        #expect(CarLiveDetailsFormat.clock(totalSeconds: 65) == "00:01:05")
        #expect(CarLiveDetailsFormat.clock(seconds: 12.9) == "00:00:12")
        #expect(CarLiveDetailsFormat.clock(seconds: 59.9) == "00:00:59")
        #expect(CarLiveDetailsFormat.clock(totalSeconds: 3_661) == "01:01:01")
        #expect(CarLiveDetailsFormat.clock(totalSeconds: 86_399) == "23:59:59")
        #expect(CarLiveDetailsFormat.clock(totalSeconds: 86_400) == "24:00:00")
        #expect(CarLiveDetailsFormat.clock(totalSeconds: 90_061) == "25:01:01")
        #expect(CarLiveDetailsFormat.clock(totalSeconds: Int.max) == "2562047788015215:30:07")
        #expect(CarLiveDetailsFormat.sessionDuration(seconds: 90_061) == .clock("25:01:01", unconfirmed: false))
        #expect(CarLiveDetailsFormat.sessionDuration(seconds: -1) == .unknown)
    }

    @Test func unknownVoiceStaysUnknownAndKnownZeroStaysZero() {
        var voice = CarLiveVoiceNote()
        voice.replace(.nan)
        voice.replace(.infinity)
        voice.replace(-1)
        #expect(voice.hasSnapshot == false)
        #expect(voice.seconds == 0)
        #expect(
            CarLiveDetailsFormat.voiceDuration(seconds: voice.seconds, known: voice.hasSnapshot, unconfirmed: voice.unconfirmed)
                == .unknown
        )

        voice.replace(0)
        #expect(
            CarLiveDetailsFormat.voiceDuration(seconds: voice.seconds, known: voice.hasSnapshot, unconfirmed: false)
                == .clock("00:00:00", unconfirmed: false)
        )

        voice.replace(12.9)
        voice.close(nil)
        #expect(voice.seconds == 12.9)
        #expect(voice.unconfirmed)
        #expect(
            CarLiveDetailsFormat.voiceDuration(seconds: voice.seconds, known: voice.hasSnapshot, unconfirmed: voice.unconfirmed)
                == .clock("00:00:12", unconfirmed: true)
        )

        voice.replace(Double.greatestFiniteMagnitude)
        #expect(voice.hasSnapshot)
        #expect(voice.seconds == Double.greatestFiniteMagnitude)
        #expect(CarLiveDetailsFormat.voiceDuration(seconds: voice.seconds, known: true, unconfirmed: false) == .unknown)
        #expect(CarLiveDetailsFormat.clock(seconds: .nan) == nil)
        #expect(CarLiveDetailsFormat.clock(seconds: -.infinity) == nil)
    }

    @Test func tokensScaleHalfUpAndKeepExactAccessibility() throws {
        #expect(CarLiveDetailsFormat.tokens(999) == CarLiveDetailsFormat.TokenText(display: "999", exactAccessibility: "999"))
        #expect(CarLiveDetailsFormat.tokens(1_000) == CarLiveDetailsFormat.TokenText(display: "1K", exactAccessibility: "1000"))
        #expect(CarLiveDetailsFormat.tokens(1_200) == CarLiveDetailsFormat.TokenText(display: "1.2K", exactAccessibility: "1200"))
        #expect(CarLiveDetailsFormat.tokens(1_234) == CarLiveDetailsFormat.TokenText(display: "1.23K", exactAccessibility: "1234"))
        #expect(CarLiveDetailsFormat.tokens(1_235) == CarLiveDetailsFormat.TokenText(display: "1.24K", exactAccessibility: "1235"))
        #expect(CarLiveDetailsFormat.tokens(1_234_567) == CarLiveDetailsFormat.TokenText(display: "1.23M", exactAccessibility: "1234567"))
        #expect(CarLiveDetailsFormat.tokens(999_999) == CarLiveDetailsFormat.TokenText(display: "1M", exactAccessibility: "999999"))
        #expect(CarLiveDetailsFormat.tokens(999_995).display == "1M")
        #expect(CarLiveDetailsFormat.tokens(999_995).exactAccessibility == "999995")
        #expect(CarLiveDetailsFormat.tokens(999_994).display == "999.99K")
        #expect(CarLiveDetailsFormat.tokens(1_000_000_000) == CarLiveDetailsFormat.TokenText(display: "1B", exactAccessibility: "1000000000"))
        #expect(CarLiveDetailsFormat.tokens(-20).display == "-20")
        #expect(CarLiveDetailsFormat.tokens(-20).exactAccessibility == "-20")

        let payload = """
        {"id":"resp_1","model":"gpt-6-luna","service_tier":"default","usage":{"input_tokens":1000,"output_tokens":100,"input_tokens_details":{"cached_tokens":200,"cache_write_tokens":300}}}
        """.data(using: .utf8)!
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let parsed = try #require(CarLiveUsageParser.parse(object))
        var ledger = CarLiveUsageLedger()
        let life = CarLiveLifecycle(
            type: "response.completed",
            responseID: "resp_1",
            model: "gpt-6-luna",
            outputCount: 0,
            usage: parsed
        )
        let accepted = ledger.record(life)
        #expect(accepted)
        let before = ledger.usage
        let shown = CarLiveDetailsFormat.tokens(ledger.usage.inputTokens)
        #expect(ledger.usage == before)
        #expect(before.inputTokens == 500)
        #expect(before.cachedRead == 200)
        #expect(before.cacheWrite == 300)
        #expect(shown == CarLiveDetailsFormat.TokenText(display: "500", exactAccessibility: "500"))
    }

    @Test func costsKeepZeroSubCentAndUnconfirmedDistinct() {
        #expect(CarLiveDetailsFormat.localCost(usd: 0, unpricedCount: 0) == .amount("$0.00"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.004, unpricedCount: 0) == .amount("<$0.01"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.005, unpricedCount: 0) == .amount("<$0.01"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.009, unpricedCount: 0) == .amount("<$0.01"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.009999, unpricedCount: 0) == .amount("<$0.01"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.01, unpricedCount: 0) == .amount("$0.01"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.135, unpricedCount: 0) == .amount("$0.14"))
        #expect(CarLiveDetailsFormat.localCost(usd: 0.12, unpricedCount: 0) == .amount("$0.12"))
        #expect(CarLiveDetailsFormat.localCost(usd: 1.234, unpricedCount: 0) == .amount("$1.23"))
        #expect(CarLiveDetailsFormat.localCost(usd: 1.235, unpricedCount: 0) == .amount("$1.24"))
        #expect(CarLiveDetailsFormat.localCost(usd: 10, unpricedCount: 0) == .amount("$10.00"))
        #expect(CarLiveDetailsFormat.localCost(usd: .nan, unpricedCount: 0) == .unknown)
        #expect(CarLiveDetailsFormat.localCost(usd: .infinity, unpricedCount: 3) == .unknown)
        #expect(CarLiveDetailsFormat.localCost(usd: -0.2, unpricedCount: 0) == .unknown)

        let partialZero = CarLiveDetailsFormat.localCost(usd: 0, unpricedCount: 2)
        #expect(partialZero == .unconfirmed(nil))
        #expect(partialZero.valueText(unknown: "Unconfirmed", unconfirmedLabel: "Unconfirmed") == "Unconfirmed")
        #expect(CarLiveDetailsFormat.localCost(usd: 1.5, unpricedCount: 1) == .unconfirmed("$1.50"))

        #expect(CarLiveDetailsFormat.portalCost(usd: nil, settled: false) == .unknown)
        #expect(CarLiveDetailsFormat.portalCost(usd: nil, settled: true) == .unknown)
        #expect(CarLiveDetailsFormat.portalCost(usd: 0, settled: false) == .unconfirmed(nil))
        #expect(CarLiveDetailsFormat.portalCost(usd: 0, settled: true) == .amount("$0.00"))
        #expect(CarLiveDetailsFormat.portalCost(usd: 0.34, settled: false) == .unconfirmed("$0.34"))
        #expect(CarLiveDetailsFormat.portalCost(usd: 0.34, settled: true) == .amount("$0.34"))
        let missing = CarLiveDetailsFormat.portalCost(usd: nil, settled: false)
            .valueText(unknown: "No portal snapshot", unconfirmedLabel: "Unconfirmed")
        #expect(missing == "No portal snapshot")
        #expect(!missing.contains("$"))
    }

    @Test func metricColumnsFollowContainerWidthAndAccessibilityText() {
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 180, accessibilityText: false) == 1)
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 360, accessibilityText: false) == 2)
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 700, accessibilityText: false) == 3)
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 900, accessibilityText: false) == 4)
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 900, accessibilityText: true) == 1)
        #expect(CarLiveDetailsFormat.metricColumnCount(containerWidth: 360, accessibilityText: true) == 1)
    }

    @Test func approvedCopyIsPresentInBothDictionaries() {
        #expect(L10n.missingEnglishKeys.isEmpty)
        #expect(L10n.missingChineseKeys.isEmpty)
        let ordinary = L10n.t(.carLiveInputUsage)
        #expect(ordinary == "Ordinary Input" || ordinary == "普通输入")
        let heading = L10n.t(.carLiveCostHeading)
        #expect(heading == "Cost Reference (USD)" || heading == "费用参考（USD）")
        let note = L10n.t(.carLiveCostExplanation)
        #expect(note.contains("do not add them together") || note.contains("请勿相加"))
    }

    @Test @MainActor func freshSnapshotDoesNotInventAVoiceClock() {
        let controller = CarLiveController(transport: IdleTransport(), audio: IdleAudio())
        let snapshot = CarLiveSnapshot(controller: controller)
        #expect(snapshot.voiceSeconds == 0)
        #expect(snapshot.voiceDurationKnown == false)
        #expect(snapshot.voiceDurationUnconfirmed == false)
        #expect(snapshot.localUnpricedCount == 0)
        #expect(snapshot.portalEstimatedUSD == nil)
        #expect(snapshot.portalSettled == false)
        #expect(controller.backendUsage.inputTokens == 0)
        #expect(
            CarLiveDetailsFormat.voiceDuration(
                seconds: snapshot.voiceSeconds,
                known: snapshot.voiceDurationKnown,
                unconfirmed: snapshot.voiceDurationUnconfirmed
            ) == .unknown
        )
    }
}

private struct IdleTransport: CarLiveTransporting {
    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        throw CarLiveTransportError.socket
    }
}

private final class IdleAudio: CarLiveAudioEngine, @unchecked Sendable {
    func requestRecordPermission() async -> Bool { false }

    func startCapture() async throws -> CarLiveCaptureHandle {
        let stream = CarLiveFrameStream(generation: 1)
        return CarLiveCaptureHandle(generation: 1, frames: stream.frames) { stream.finish() }
    }

    func stopCapture(generation: UInt64) async {}
    func setMuted(_ muted: Bool) {}
    func enqueuePlayback(_ pcm: Data) {}
    func clearPlayback() {}
    func setLevelHandler(_ handler: (@Sendable (Double, Double) -> Void)?) {}
    func setPlaybackIdleHandler(_ handler: (@Sendable () -> Void)?) {}
}
