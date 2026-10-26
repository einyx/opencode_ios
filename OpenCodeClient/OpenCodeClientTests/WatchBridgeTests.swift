import Foundation
import Testing
@testable import OpenCodeClient

@MainActor
struct WatchBridgeTests {
    #if os(iOS)
    /// A voice engine that starts without touching the microphone or the
    /// Speech framework.
    private func makeEngine() -> DeviceVoiceEngine {
        DeviceVoiceEngine(
            audioEngine: FakeAudioEngine(),
            makeSession: {
                let session = OnDeviceSpeechSession(recognizer: FakeStreamingRecognizer())
                try session.start()
                return session
            },
            turnRunner: { _ in nil },
            speaker: { _ in }
        )
    }

    @Test func reconnectReplacesOnlyTheObservedOldLeaseAndRejectsLateCleanup() async {
        let state = makeIsolatedAppState(apiClient: MockAPIClient(), deviceVoice: makeEngine())
        let bridge = WatchPhoneBridge()
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

    /// The watch's microphone goes to the phone, and the answer comes back.
    @Test func audioReachesThePhoneAndTheAnswerComesBack() async {
        let state = makeIsolatedAppState(apiClient: MockAPIClient(), deviceVoice: makeEngine())
        let bridge = WatchPhoneBridge()
        bridge.state = state
        let run = UUID().uuidString
        #expect(await bridge.handle(WatchBridgeWire.envelope("begin", run: run))["run"] as? String == run)

        var audio = WatchBridgeWire.envelope("audio", run: run)
        audio["data"] = Data([0, 1, 2, 3])
        #expect(await bridge.handle(audio)["ok"] as? Bool == true)

        bridge.deliverVoiceReply("The garage door is closed.")
        let reply = await bridge.handle(WatchBridgeWire.envelope("voice", run: run))
        #expect(reply["text"] as? String == "The garage door is closed.")
        // The answer is handed over once.
        #expect(await bridge.handle(WatchBridgeWire.envelope("voice", run: run))["ok"] as? Bool == true)
    }

    /// The bridge never carries a credential.
    @Test func theBridgeCarriesNoCredential() async {
        let state = makeIsolatedAppState(apiClient: MockAPIClient(), deviceVoice: makeEngine())
        let bridge = WatchPhoneBridge()
        bridge.state = state
        let run = UUID().uuidString
        let setup = await bridge.handle(WatchBridgeWire.envelope("begin", run: run))
        #expect(setup["token"] == nil)
        #expect(setup["portal"] == nil)
    }
    #endif
}
