import Foundation
import Testing
@testable import OpenCodeClient

@MainActor
struct WatchBridgeTests {
    @Test func duplicateAndUnknownCallsNeverBecomeNewWrites() {
        let ledger = WatchCallLedger()
        #expect(ledger.claim(id: "call-a", name: "start_job", arguments: "{}") == "accepted")
        #expect(ledger.claim(id: "call-a", name: "start_job", arguments: "{}") == "duplicate")
        #expect(ledger.claim(id: "call-a", name: "start_job", arguments: "different") == "call_conflict")
        #expect(ledger.claim(id: "call-b", name: "continue_job", arguments: "{}") == "busy")
        ledger.markUnknown(id: "call-a")
        ledger.finish(id: "call-a", output: "late success")
        #expect(ledger.header(id: "call-a")["status"] as? String == "unknown")
        #expect(ledger.claim(id: "call-a", name: "start_job", arguments: "{}") == "duplicate")
        #expect(ledger.claim(id: "call-b", name: "continue_job", arguments: "{}") == "accepted")
    }

    @Test func fullSizeUnicodeResultSurvivesEightChunksAndAckLeavesTombstone() throws {
        let ledger = WatchCallLedger()
        let text = String(repeating: "中", count: 21_844) + "end!"
        #expect(text.utf8.count == WatchBridgeWire.maxOutputBytes)
        #expect(ledger.claim(id: "unicode", name: "get_session_messages", arguments: "{}") == "accepted")
        ledger.finish(id: "unicode", output: text)
        let header = ledger.header(id: "unicode")
        #expect(header["chunks"] as? Int == 8)
        var data = Data()
        for seq in 0..<8 { data.append(try #require(ledger.chunk(id: "unicode", sequence: seq))) }
        #expect(String(data: data, encoding: .utf8) == text)
        #expect(WatchBridgeWire.digest(data) == header["sha256"] as? String)
        ledger.acknowledge(id: "unicode", digest: "wrong")
        #expect(ledger.header(id: "unicode")["status"] as? String == "ready")
        ledger.acknowledge(id: "unicode", digest: WatchBridgeWire.digest(data))
        #expect(ledger.chunk(id: "unicode", sequence: 0) == nil)
        #expect(ledger.claim(id: "unicode", name: "get_session_messages", arguments: "{}") == "duplicate")
    }

    @Test func watchClientDoesNotReplacePhoneTransportGate() async {
        let phone = APIClient(baseURL: "https://example.invalid")
        let phoneToken = await phone.armLiveTransport()
        let watch = await phone.makeWatchClient()
        let watchToken = await watch.armLiveTransport()
        await watch.retireLiveTransport(token: watchToken)
        // A retired token fails locally before networking; the phone token remains independent.
        do {
            _ = try await watch.sessionStatusForLive(transportToken: watchToken)
            Issue.record("Retired Watch gate must reject")
        } catch { #expect(error is CancellationError || error is CarLiveAPIUnsupported) }
        #expect(await phone.armLiveTransport() == phoneToken + 1)
        watch.cancelWatchRequests()
    }
}
