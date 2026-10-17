import Foundation
import Testing
@testable import OpenCodeClient

private final class CarLiveScriptedLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    private var sent: [CarLiveClientEvent] = []
    var failSend = false

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) {
        continuation.yield(event)
    }

    func send(_ event: CarLiveClientEvent) async throws {
        if failSend { throw CarLiveTransportError.socket }
        lock.withLock { sent.append(event) }
    }

    func ping() async throws {}

    func close() async {
        continuation.finish()
    }

    func snapshot() -> [CarLiveClientEvent] {
        lock.withLock { sent }
    }
}

private struct CarLiveFixedTransport: CarLiveTransporting, Sendable {
    var link: CarLiveScriptedLink
    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink { link }
}

private final class CarLiveFakeAudio: CarLiveAudioEngine, @unchecked Sendable {
    func requestRecordPermission() async -> Bool { true }
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

private func waitUntil(_ ready: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<40 {
        if await MainActor.run(body: ready) { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await MainActor.run(body: ready)
}

struct CarLiveProtocolTests {
    @Test func nestedFunctionCallDecodesCompleteArguments() {
        let text = """
        {"type":"response.event","event":{"type":"response.output_item.done","item":{"type":"function_call","call_id":"call_1","name":"query_jobs","arguments":"{\\"queryScope\\":\\"recent\\"}"}}}
        """
        guard case .hosted(.functionCall(let callID, let name, let arguments)) = CarLiveEventDecoder.decode(text) else {
            Issue.record("missing call")
            return
        }
        #expect(callID == "call_1")
        #expect(name == "query_jobs")
        #expect(arguments.contains("recent"))
    }

    @Test func emptySnapshotDoesNotClearCollectedCalls() {
        var book = CarLiveCallBook(generation: 1)
        book.collect(callID: "call_1", name: "query_jobs")
        book.noteLifecycle(outputCount: 0)
        #expect(book.keptCalls == 1)
    }

    @Test func dedupeAndGenerationRejectOldCall() {
        var book = CarLiveCallBook(generation: 1)
        let first = book.claim(callID: "call_1", generation: 1)
        let duplicate = book.claim(callID: "call_1", generation: 1)
        let stale = book.claim(callID: "call_1", generation: 2)
        #expect(first == .accepted)
        #expect(duplicate == .duplicate)
        #expect(stale == .rejected)
        book.bind(2)
        let rebound = book.claim(callID: "call_1", generation: 2)
        #expect(rebound == .accepted)
    }

    @Test func failedSendBlocksContinueAndDoesNotRetry() {
        var flight = CarLiveFlightBook()
        flight.begin()
        flight.begin()
        let blocked = flight.finish(outputSent: false, accepting: true)
        let stillBlocked = flight.finish(outputSent: true, accepting: true)
        #expect(blocked == false)
        #expect(stillBlocked == false)
        #expect(flight.continuations == 0)
        #expect(flight.inFlight == 0)
    }

    @Test func bothSendsContinueOnce() {
        var flight = CarLiveFlightBook()
        flight.begin()
        flight.begin()
        let waiting = flight.finish(outputSent: true, accepting: true)
        let continued = flight.finish(outputSent: true, accepting: true)
        #expect(waiting == false)
        #expect(continued == true)
        #expect(flight.continuations == 1)
    }

    @Test func cacheWriteIsNotStackedAndReasoningIsNotAdded() {
        let payload = """
        {"id":"resp_1","model":"gpt-6-luna-2026-10-16","service_tier":"default","usage":{"input_tokens":1000,"output_tokens":100,"input_tokens_details":{"cached_tokens":200,"cache_write_tokens":300},"output_tokens_details":{"reasoning_tokens":40}}}
        """.data(using: .utf8)!
        let object = try! JSONSerialization.jsonObject(with: payload) as! [String: Any]
        let parsed = CarLiveUsageParser.parse(object)
        #expect(parsed?.outputTokens == 100)
        #expect(parsed?.reasoningTokens == 40)
        #expect(parsed?.cacheWrite == 300)
        let quote = parsed.flatMap(CarLiveQuoteMaker.make)
        let stacked = (Double(1000) * 0.10 + Double(300) * 0.125 + Double(100) * 0.50) / 1_000_000
        #expect(quote?.ordinaryInputTokens == 500)
        #expect(quote?.estimatedUSD == 0.0001395)
        #expect(quote?.estimatedUSD != stacked)
        var ledger = CarLiveUsageLedger()
        let life = CarLiveLifecycle(type: "response.completed", responseID: "resp_1", model: "gpt-6-luna-2026-10-16", outputCount: 0, usage: parsed)
        let accepted = ledger.record(life)
        let duplicate = ledger.record(life)
        #expect(accepted)
        #expect(duplicate == false)
        #expect(ledger.usage.inputTokens == 500)
        #expect(ledger.usage.cacheWrite == 300)
        #expect(ledger.usage.outputTokens == 100)
        #expect(ledger.usage.responseCount == 1)
    }

    @Test func portalUsageReplacesByRequestAndClosedWithoutUsageKeepsLast() {
        var portal = CarLivePortalLedger()
        portal.replace(requestID: "voice-1", estimatedUSD: 0.01, confirmed: false, status: "provisional")
        portal.replace(requestID: "voice-1", estimatedUSD: 0.02, confirmed: true, status: "confirmed")
        portal.replace(requestID: "resp-1", estimatedUSD: 0.03, confirmed: false, status: "provisional")
        portal.replace(requestID: "bad-1", estimatedUSD: 9, confirmed: false, status: "anomaly")
        #expect(portal.total == 0.05)
        #expect(portal.settled == false)
        #expect(CarLiveEventDecoder.decode("{\"type\":\"usage\",\"estimated_cost_usd\":1.5}") == .usageUnconfirmed)
        let nested = CarLiveEventDecoder.decode("{\"type\":\"error\",\"error\":{\"code\":\"usage_unconfirmed\",\"message\":\"Usage was not confirmed\"}}")
        #expect(nested == .usageUnconfirmed)
        var voice = CarLiveVoiceNote()
        voice.replace(12.5)
        voice.close(nil)
        #expect(voice.seconds == 12.5)
        #expect(voice.unconfirmed)
        #expect(voice.seconds != 0)
    }

    @Test func wireRejectsSessionStartAndFunctionOutputMatchesCall() {
        #expect(CarLiveWire.forbidden("session.start"))
        #expect(CarLiveWire.forbidden("session.update"))
        let encoded = CarLiveWire.encode(.functionOutput(callID: "call_1", output: "{\"ok\":true}"), eventID: "evt_1")
        let object = try! JSONSerialization.jsonObject(with: Data(encoded!.utf8)) as! [String: Any]
        #expect(object["type"] as? String == "response.item.create")
        let item = object["item"] as? [String: Any]
        #expect(item?["call_id"] as? String == "call_1")
        #expect(item?["output"] as? String == "{\"ok\":true}")
        #expect(CarLiveWire.encode(.continueResponse, eventID: "evt_2")?.contains("response.create") == true)
        #expect(CarLiveShutdown.abortsOpenCode == false)
    }

    @Test @MainActor func nestedNativeFunctionOutputContinuesOnceAndDedupes() async {
        let link = CarLiveScriptedLink()
        let controller = CarLiveController(transport: CarLiveFixedTransport(link: link), audio: CarLiveFakeAudio())
        let calls = CarLiveCallCounter()
        controller.toolExecutor = { call in
            await calls.add(call.callID)
            return CarLiveToolResult(output: "{\"ok\":true}", acceptedSessionID: "ses_1")
        }
        let config = CarLiveConfiguration(
            portalBaseURL: URL(string: "https://space.example/backend")!,
            builderToken: "builder-test",
            ownerToken: "owner-a"
        )
        let starting = Task { await controller.start(configuration: config) }
        #expect(await waitUntil { controller.phase == .connecting })
        link.emit(.started(sessionID: "live_1"))
        await starting.value
        #expect(controller.phase == .listening)
        let event = CarLiveServerEvent.hosted(.functionCall(callID: "call_1", name: "query_jobs", arguments: "{\"queryScope\":\"recent\"}"))
        link.emit(event)
        link.emit(event)
        #expect(await waitUntil { link.snapshot().contains(.continueResponse) })
        let sent = link.snapshot()
        let outputs = sent.filter {
            if case .functionOutput(let callID, _) = $0 { return callID == "call_1" }
            return false
        }
        #expect(outputs.count == 1)
        #expect(sent.last == .continueResponse)
        #expect(await calls.count() == 1)
        link.emit(.closed(1))
        await controller.stop()
        #expect(controller.phase == .idle)
    }

    @Test func transcriptEventIDIsNotAnUtteranceBoundary() {
        let first = """
        {"type":"session.input_transcript.delta","event_id":"evt_1","delta":"你","start_ms":1000,"end_ms":1200}
        """
        let second = """
        {"type":"session.input_transcript.delta","event_id":"evt_2","delta":"好","start_ms":1200,"end_ms":1400}
        """
        guard case .inputTranscript(let opening) = CarLiveEventDecoder.decode(first) else {
            Issue.record("missing transcript")
            return
        }
        guard case .inputTranscript(let follow) = CarLiveEventDecoder.decode(second) else {
            Issue.record("missing follow")
            return
        }
        #expect(opening.eventID == "evt_1")
        #expect(opening.utteranceID == nil)
        #expect(opening.startMS == 1000)
        #expect(opening.endMS == 1200)
        #expect(follow.utteranceID == nil)
        var book = CarLiveCaptionBook()
        let opened = book.append(role: "user", text: opening.text, startMS: opening.startMS, endMS: opening.endMS)
        let appended = book.append(role: "user", text: follow.text, startMS: follow.startMS, endMS: follow.endMS)
        #expect(opened == .opened)
        #expect(appended == .appended)
        #expect(book.captions.count == 1)
        #expect(book.captions.first?.text == "你好")
    }

    @Test func speechGapMergesLooseIntervalsAndKeepsExactText() {
        var near = CarLiveCaptionBook()
        let first = near.append(role: "user", text: " hello", startMS: 0, endMS: 200)
        let within = near.append(role: "user", text: " hello", startMS: 200 + 1_900, endMS: 200 + 1_900 + 200)
        #expect(first == .opened)
        #expect(within == .appended)
        #expect(near.captions.map(\.text) == [" hello hello"])
        #expect(near.captions[0].startMS == 0)
        #expect(near.captions[0].endMS == 2_300)
        var far = CarLiveCaptionBook()
        _ = far.append(role: "user", text: " hello", startMS: 0, endMS: 200)
        let beyond = far.append(role: "user", text: " later", startMS: 200 + 2_100, endMS: 200 + 2_100 + 200)
        #expect(beyond == .opened)
        #expect(far.captions.map(\.text) == [" hello", " later"])
        var missing = CarLiveCaptionBook()
        _ = missing.append(role: "user", text: " hello", startMS: 0, endMS: 200)
        let continued = missing.append(role: "user", text: " hello", startMS: nil, endMS: nil)
        #expect(continued == .appended)
        #expect(missing.captions.map(\.text) == [" hello hello"])
        #expect(missing.captions[0].endMS == 200)
    }

    @Test func interleavedSpeechStaysTwoSegmentsAndDeliveryTimeIsIgnored() {
        var book = CarLiveCaptionBook()
        for index in 0..<5 {
            let start = index * 300
            let user = book.append(role: "user", text: index == 0 ? "你" : "你", startMS: start, endMS: start + 120)
            let assistant = book.append(role: "assistant", text: "我", startMS: start + 40, endMS: start + 160)
            #expect(user == (index == 0 ? .opened : .appended))
            #expect(assistant == (index == 0 ? .opened : .appended))
        }
        #expect(book.captions.count == 2)
        #expect(book.captions.map(\.role) == ["user", "assistant"])
        #expect(book.captions[0].text == "你你你你你")
        #expect(book.captions[1].text == "我我我我我")
        let continued = book.append(role: "user", text: "你", startMS: 1_200, endMS: 1_320)
        #expect(continued == .appended)
        book.closeAll()
        let afterTool = book.append(role: "user", text: "后", startMS: 1_400, endMS: 1_500)
        let sameUtterance = book.append(role: "user", text: "续", startMS: 1_500, endMS: 1_600)
        #expect(afterTool == .opened)
        #expect(sameUtterance == .appended)
        #expect(book.captions.filter { $0.role == "user" }.count == 2)
    }

    @Test func diagnosticSnapshotHasNoContentFields() throws {
        var log = CarLiveDiagnostics()
        log.note(kind: "barge_begin", at: 1.5, inputLevel: 0.42, outputActive: true, turnHash: 9)
        log.note(kind: "user said secret", at: 2, inputLevel: 0.1, outputActive: false, turnHash: 9)
        let data = log.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == CarLiveDiagnostics.allowedKeys)
        #expect(object["lastKind"] as? String == "other")
        #expect(object["text"] == nil)
        #expect(object["delta"] == nil)
        let rendered = String(data: data, encoding: .utf8) ?? ""
        #expect(rendered.contains("secret") == false)
    }

    @Test func hostedSchemaHasEightCanonicalNames() throws {
        let names = CarLiveToolSchema.tools().compactMap { $0["name"] as? String }
        let stored = try toolNamesFromProtocol(CarLiveProtocol.defaultToolsJSON)
        #expect(names == CarLiveHostedFunction.names)
        #expect(names.count == 8)
        #expect(Set(names).count == 8)
        #expect(stored == names)
        #expect(names.contains(CarLiveHostedFunction.archiveJob))
        #expect(names.contains(CarLiveHostedFunction.unarchiveJob))
    }
}

private func toolNamesFromProtocol(_ data: Data) throws -> [String] {
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    return rows.compactMap { $0["name"] as? String }
}

private actor CarLiveCallCounter {
    private var values: [String] = []
    func add(_ value: String) { values.append(value) }
    func count() -> Int { values.count }
}
