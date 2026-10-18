import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveReplyToolHookTests {
    @Test func startAndContinueReserveBeforePostAndFailureRollsBackOnlyThatToken() async {
        let fake = ReplyHookClient()
        var rolled: [String] = []
        var reserved: [String] = []
        let context = CarLiveToolContext(
            trackedSessionID: "s1",
            directory: "/work",
            startAgent: "build",
            allows: { true },
            reserveReply: { reservation in
                await fake.note("reserve")
                reserved.append(reservation.token)
                #expect(reservation.isNewSession)
            },
            rollbackReply: { token in
                rolled.append(token)
            }
        )
        await fake.setThrowOnStart(true)
        let failed = await CarLiveToolHandler.run(CarLiveToolName.startJob, arguments: #"{"text":"研究路线","requestedModel":null}"#, client: fake, context: context)
        #expect(status(failed.output) != "accepted")
        #expect(failed.prepareToken == nil)
        #expect(await fake.events == ["reserve", "post-start"])
        #expect(rolled == reserved)

        await fake.resetEvents()
        await fake.setThrowOnStart(false)
        reserved.removeAll()
        let started = await CarLiveToolHandler.run(CarLiveToolName.startJob, arguments: #"{"text":"研究路线","requestedModel":null}"#, client: fake, context: context)
        #expect(status(started.output) == "accepted")
        #expect(started.prepareToken == reserved.last)
        #expect(await fake.events == ["reserve", "post-start"])
        #expect(rolled.count == 1)

        let continueContext = CarLiveToolContext(
            trackedSessionID: "s1",
            directory: "/work",
            startAgent: "build",
            allows: { true },
            reserveReply: { reservation in
                await fake.note("reserve-continue")
                reserved.append(reservation.token)
                #expect(!reservation.isNewSession)
            },
            rollbackReply: { token in
                rolled.append(token)
            }
        )
        await fake.resetEvents()
        await fake.setThrowOnContinue(true)
        let continued = await CarLiveToolHandler.run(CarLiveToolName.continueJob, arguments: #"{"sessionID":"s1","text":"继续"}"#, client: fake, context: continueContext)
        #expect(status(continued.output) != "accepted")
        #expect(await fake.events == ["reserve-continue", "post-continue"])
        #expect(rolled.last == reserved.last)
        let beforeQuery = await fake.events
        let query = await CarLiveToolHandler.run(CarLiveToolName.queryJobs, arguments: #"{"queryScope":"recent"}"#, client: fake, context: continueContext)
        #expect(query.prepareToken == nil)
        #expect(await fake.events == beforeQuery)
    }
}

private actor ReplyHookClient: CarLiveToolClient {
    private var throwStart = false
    private var throwContinue = false
    var events: [String] = []

    func setThrowOnStart(_ value: Bool) { throwStart = value }
    func setThrowOnContinue(_ value: Bool) { throwContinue = value }
    func note(_ event: String) { events.append(event) }
    func resetEvents() { events.removeAll() }

    func bindOwner(_ allows: @escaping () async -> Bool) async {}

    func listed(archivedOnly: Bool, skip: Int, count: Int) async throws -> CarLiveListWindow {
        CarLiveListWindow(records: [], skip: skip, count: count, returned: 0, hasMore: false, nextSkip: nil, partial: false, fetchMore: false)
    }

    func lookup(id: String, directory: String?) async -> CarLiveLookup {
        CarLiveLookup(session: hookSession(id), httpStatus: 200, transport: false)
    }

    func history(sessionID: String, directory: String, skip: Int, count: Int) async -> String { "{}" }

    func connectedRefs() async throws -> Set<String> { [CarLiveModel.deepseek] }

    func create(directory: String?) async throws -> Session {
        return hookSession("s-\(UUID().uuidString.prefix(6))", directory: directory ?? "/work")
    }

    func startPrompt(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?) async throws -> Data {
        events.append("post-start")
        if throwStart { throw ReplyHookError() }
        return Data()
    }

    func continuePrompt(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?) async throws -> Data {
        events.append("post-continue")
        if throwContinue { throw ReplyHookError() }
        return Data()
    }

    func confirmStop(sessionID: String) async throws -> String { CarLiveToolJSON.stopped() }
    func answer(sessionID: String, answers: [[String]], permissionReply: String?) async throws {}
    func setArchived(sessionID: String, archived: Int) async throws -> Int { archived }
    func children(sessionID: String) async throws -> [Session] { [] }
    func round(sessionID: String, messageID: String) async throws -> CarLiveRoundSnapshot {
        CarLiveRoundSnapshot(assistantText: nil, finalFinish: false, openTools: false, childrenActive: false, pending: false, failed: false)
    }
}

private struct ReplyHookError: Error {}

private func hookSession(_ id: String, directory: String = "/work") -> Session {
    Session(id: id, slug: id, projectID: "p", directory: directory, parentID: nil, title: "路线", version: "1", time: .init(created: 1, updated: 2, archived: nil), share: nil, summary: nil)
}

private func status(_ text: String) -> String? {
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return object["status"] as? String
}
