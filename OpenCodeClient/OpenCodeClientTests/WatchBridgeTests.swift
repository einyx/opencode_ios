import Foundation
import Testing
@testable import OpenCodeClient

@MainActor
struct WatchBridgeTests {
    #if os(iOS)
    @Test func reconnectReplacesOnlyTheObservedOldLeaseAndRejectsLateCleanup() async {
        let defaults = UserDefaults(suiteName: "watch-reconnect-\(UUID().uuidString)")!
        let state = AppState(userDefaults: defaults)
        state.aiBuilderBaseURL = "https://example.invalid"
        state.aiBuilderToken = "test-builder-token"
        let bridge = WatchPhoneBridge(makeClient: { _ in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [WatchHealthHTTP.self]
            return APIClient(baseURL: "https://watch-health.invalid", session: URLSession(configuration: configuration))
        })
        bridge.state = state
        let old = UUID().uuidString
        let next = UUID().uuidString
        let late = UUID().uuidString
        #expect(await bridge.handle(WatchBridgeWire.envelope("begin", run: old))["run"] as? String == old)
        let busy = await bridge.handle(WatchBridgeWire.envelope("begin", run: next))
        #expect(busy["error"] as? String == "busy")
        #expect(busy["activeRun"] as? String == old)

        var replacement = WatchBridgeWire.envelope("begin", run: next)
        replacement["replacing"] = old
        #expect(await bridge.handle(replacement)["run"] as? String == next)
        #expect(bridge.lease?.ownerToken == next)
        var staleReplacement = WatchBridgeWire.envelope("begin", run: late)
        staleReplacement["replacing"] = old
        #expect(await bridge.handle(staleReplacement)["error"] as? String == "busy")
        #expect(await bridge.handle(WatchBridgeWire.envelope("end", run: old))["error"] as? String == "stale_context")
        #expect(bridge.lease?.ownerToken == next)
        #expect(await bridge.handle(WatchBridgeWire.envelope("end", run: next))["ok"] as? Bool == true)
        #expect(bridge.lease == nil)
    }
    #endif

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

#if os(iOS)
private final class WatchHealthHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"healthy\":true,\"version\":\"test\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
