import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveToolsTests {
    @Test func queryWalkKeepsArchivedRootsAndPaginates() {
        let pages = [
            CarLiveListPage(rows: [
                item("child", parentID: "root-a", archivedAt: 5),
                item("root-a", archivedAt: 5),
                item("live", archivedAt: 0),
            ], nextCursor: 10),
            CarLiveListPage(rows: [
                item("root-b", archivedAt: 9),
            ], nextCursor: nil),
        ]
        let archived = CarLiveSessionWalk.walk(pages: pages, archivedOnly: true, skip: 0, count: 10)
        #expect(archived.records.map(\.id) == ["root-a", "root-b"])
        #expect(archived.hasMore == false)
        let page = CarLiveSessionWalk.walk(pages: pages, archivedOnly: true, skip: 1, count: 1)
        #expect(page.records.map(\.id) == ["root-b"])
        #expect(page.nextSkip == nil)
        let mixed = CarLiveSessionWalk.walk(pages: pages, archivedOnly: false, skip: 0, count: 10)
        #expect(mixed.records.map(\.id) == ["root-a", "live", "root-b"])
    }

    @Test func sessionPageQueryIncludesArchivedRoots() {
        let items = CarLivePromptWire.sessionPageQuery(cursor: 20)
        #expect(items.contains(URLQueryItem(name: "roots", value: "true")))
        #expect(items.contains(URLQueryItem(name: "archived", value: "true")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "50")))
        #expect(items.contains(URLQueryItem(name: "cursor", value: "20")))
    }

    @Test func createBodyOmitsTitleAndStartBodyKeepsTwoModels() throws {
        let created = CarLivePromptWire.object(try CarLivePromptWire.sessionCreateData(title: nil))
        #expect(created["title"] == nil)
        let deepseek = try CarLivePromptWire.startData(
            messageID: "m1",
            text: "研究天气",
            agent: "build",
            model: Message.ModelInfo(providerID: "ollama-cloud", modelID: "deepseek-v4.1-flash")
        )
        let sol = try CarLivePromptWire.startData(
            messageID: "m2",
            text: "难推理",
            agent: "build",
            model: Message.ModelInfo(providerID: "openai", modelID: "gpt-6.1-sol")
        )
        #expect(modelRef(deepseek) == CarLiveModel.deepseek)
        #expect(modelRef(sol) == CarLiveModel.sol)
    }

    @Test func continueBodyOmitsModelAndKeepsOriginalText() throws {
        let data = try CarLivePromptWire.continueData(
            messageID: "m9",
            text: "请在这个对话中追加以下内容，作为本次prompt下的input",
            agent: nil,
            variant: "default"
        )
        let object = CarLivePromptWire.object(data)
        #expect(object["model"] == nil)
        #expect(object["agent"] == nil)
        #expect(object["variant"] as? String == "default")
        let part = (object["parts"] as? [[String: Any]])?.first
        #expect(part?["text"] as? String == "请在这个对话中追加以下内容，作为本次prompt下的input")
    }

    @Test func historyKeepsBothRolesAndUTC() throws {
        let messages = [
            row(id: "u1", role: "user", created: 1_700_000_000_000, text: "你好"),
            row(id: "a1", role: "assistant", created: 1_700_000_000_500, completed: 1_700_000_001_000, text: "收到"),
        ]
        let json = CarLiveHistory.render(
            sessionID: "s1",
            title: "T",
            directory: "/tmp",
            drafts: CarLiveHistory.drafts(from: messages),
            skip: 0,
            count: 10,
            hasOlder: false
        )
        let object = try jsonObject(json)
        let rows = object["messages"] as? [[String: Any]]
        #expect(rows?.map { $0["role"] as? String } == ["user", "assistant"])
        #expect((rows?.first?["created_at"] as? String)?.hasSuffix("Z") == true)
        #expect((object["pagination"] as? [String: Any])?["count"] as? Int == 10)
    }

    @Test func queryDoesNotCreateOrPrompt() async {
        let fake = LiveToolFake()
        await fake.setWindow(CarLiveListWindow(records: [item("root-a", archivedAt: 3)], skip: 0, count: 10, returned: 1, hasMore: false, nextSkip: nil, partial: false, fetchMore: false))
        let effect = await CarLiveToolHandler.run(CarLiveToolName.queryJobs, arguments: #"{"queryScope":"recent","sessionID":null,"text":"","archivedOnly":true,"skip":0,"count":10}"#, client: fake, context: allowingContext())
        let object = try? jsonObject(effect.output)
        #expect(object?["ok"] as? Bool == true)
        #expect(await fake.creates.isEmpty)
        #expect(await fake.startBodies.isEmpty)
        #expect(await fake.continueBodies.isEmpty)
    }

    @Test func unknownSessionDoesNotFallbackOrClearOnServerError() async {
        let fake = LiveToolFake()
        await fake.setLookup("missing", CarLiveLookup(session: nil, httpStatus: 404, transport: false))
        await fake.setLookup("down", CarLiveLookup(session: nil, httpStatus: 500, transport: false))
        let missing = await CarLiveToolHandler.run(CarLiveToolName.continueJob, arguments: #"{"sessionID":"missing","text":"你好"}"#, client: fake, context: allowingContext(tracked: "current"))
        #expect(missing.clearSessionID == "missing")
        #expect(code(missing.output) == "session_not_found")
        #expect(await fake.creates.isEmpty)
        let down = await CarLiveToolHandler.run(CarLiveToolName.continueJob, arguments: #"{"sessionID":"down","text":"你好"}"#, client: fake, context: allowingContext(tracked: "current"))
        #expect(down.clearSessionID == nil)
        #expect(code(down.output) == "lookup_failed")
        #expect(await fake.continueBodies.isEmpty)
    }

    @Test func continueSendsOriginalTextWithoutModel() async throws {
        let fake = LiveToolFake()
        await fake.setLookup("s1", CarLiveLookup(session: session("s1", agent: "build", variant: "default"), httpStatus: 200, transport: false))
        let text = "追加：你好"
        let effect = await CarLiveToolHandler.run(CarLiveToolName.continueJob, arguments: #"{"sessionID":"s1","text":"追加：你好"}"#, client: fake, context: allowingContext())
        #expect(code(effect.output) == nil)
        #expect(status(effect.output) == "accepted")
        let body = try #require(await fake.continueBodies.first)
        #expect(body["model"] == nil)
        #expect(body["agent"] == nil)
        #expect(body["variant"] == nil)
        #expect(((body["parts"] as? [[String: Any]])?.first)?["text"] as? String == text)
    }

    @Test func startAcceptsWithoutWaitingAndUsesExplicitModel() async throws {
        let fake = LiveToolFake()
        let effect = await CarLiveToolHandler.run(CarLiveToolName.startJob, arguments: #"{"text":"研究路线","requestedModel":"openai/gpt-6.1-sol"}"#, client: fake, context: allowingContext())
        #expect(status(effect.output) == "accepted")
        #expect(effect.poll)
        #expect(await fake.roundCalls == 0)
        let body = try #require(await fake.startBodies.first)
        #expect(modelRef(body) == CarLiveModel.sol)
        #expect(await fake.creates == ["/work" as String?])
    }

    @Test func hostSwitchBlocksLateMutation() async {
        let fake = LiveToolFake()
        let blocked = await CarLiveToolHandler.run(CarLiveToolName.startJob, arguments: #"{"text":"晚到的任务","requestedModel":null}"#, client: fake, context: allowingContext(allows: false))
        #expect(code(blocked.output) == "stale_context")
        #expect(await fake.creates.isEmpty)
        #expect(await fake.aborts.isEmpty)
        let stop = await CarLiveToolHandler.run(CarLiveToolName.stopJob, arguments: #"{"sessionID":"s1","text":"停"}"#, client: fake, context: allowingContext(allows: false))
        #expect(code(stop.output) == "stale_context")
        #expect(await fake.aborts.isEmpty)
    }

    @Test func stopTreatsMissingStatusAsIdleAndDoesNotTreatFetchFailureAsIdle() async {
        let idle = try? await CarLiveStopJudge.confirm(
            abort: {},
            status: { nil },
            childrenActive: { false },
            sleep: {}
        )
        #expect(status(idle ?? "") == "cancelled")
        let queued = QueuedThenIdle()
        let confirmed = try? await CarLiveStopJudge.confirm(
            abort: { await queued.abort() },
            status: { await queued.status() },
            childrenActive: { false },
            sleep: {}
        )
        #expect(status(confirmed ?? "") == "cancelled")
        #expect(await queued.abortCount == 2)
        do {
            _ = try await CarLiveStopJudge.confirm(
                abort: {},
                status: { throw CarLiveAPIUnsupported.status },
                childrenActive: { false },
                sleep: {}
            )
            Issue.record("status fetch failure must throw")
        } catch {
            #expect(error as? CarLiveAPIUnsupported == .status)
        }
    }

    @Test @MainActor func rejectedStartSetsVisibleError() async {
        let state = makeIsolatedAppState()
        state.isConnected = false
        await state.startCarLive()
        #expect(state.carLive?.phase == .idle)
        #expect(state.carLive?.errorMessage == L10n.t(.carNotConnected))
        state.isConnected = true
        await state.startCarLive()
        #expect(state.carLive?.errorMessage == L10n.t(.errorAiBuilderTokenEmpty))
        state.aiBuilderToken = "token"
        state.aiBuilderBaseURL = "not a url"
        await state.startCarLive()
        #expect(state.carLive?.errorMessage == L10n.t(.errorInvalidBaseURL))
    }

    @Test @MainActor func closeVoiceDoesNotAbort() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        await state.stopCarLive()
        #expect(await api.abortSessionIDs.isEmpty)
        #expect(CarLiveLeaseCheck.allows(
            lease: CarLiveLease(hostID: state.currentHostProfileID, generation: 1, contextKey: "a", epoch: 1),
            hostID: UUID(),
            generation: 1,
            contextMatches: true,
            connected: true,
            epoch: 1
        ) == false)
    }

    @Test func stringModelDoesNotFailSessionDecode() throws {
        let json = #"{"id":"s2","slug":"s2","projectID":"p","directory":"/tmp","title":"T","version":"1","time":{"created":1,"updated":2},"model":"ollama-cloud/deepseek-v4.1-flash","agent":"build"}"#
        let decoded = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(decoded.id == "s2")
        #expect(decoded.directory == "/tmp")
    }

    @Test func historyAndQueryStayWithinFunctionOutputLimit() throws {
        let huge = String(repeating: "长", count: 20_000)
        let drafts = (0..<10).map { index in
            CarLiveHistory.Draft(id: "m\(index)", role: index.isMultiple(of: 2) ? "user" : "assistant", createdMS: 1_700_000_000_000 + index, completedMS: nil, text: huge, synthetic: false)
        }
        let history = CarLiveHistory.render(sessionID: "s", title: huge, directory: huge, drafts: drafts, skip: 0, count: 10, hasOlder: false)
        #expect(history.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes)
        let historyObject = try jsonObject(history)
        #expect(historyObject["ok"] as? Bool == true)
        #expect((historyObject["pagination"] as? [String: Any])?["partial"] as? Bool == true)
        let records = (0..<10).map { index in
            ["id": "s\(index)", "title": huge, "directory": huge, "status": "idle"]
        }
        let query = CarLiveOutputBound.json([
            "ok": true,
            "query_ok": true,
            "records": records,
            "sessions": records,
            "pagination": ["skip": 0, "count": 10, "returned": 10],
        ])
        #expect(query.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes)
        #expect(try jsonObject(query)["ok"] as? Bool == true)
    }

    @Test func oldTransportRetireDoesNotCloseNewArm() {
        var lease = CarLiveTransportLease()
        let first = CarLiveTransportGate.arm(lease)
        lease = first.lease
        #expect(first.token == 1)
        lease = CarLiveTransportGate.retire(lease, token: first.token)
        #expect(lease.active == 0)
        #expect(lease.issued == 1)
        let second = CarLiveTransportGate.arm(lease)
        lease = second.lease
        #expect(second.token == 2)
        #expect(second.token != first.token)
        lease = CarLiveTransportGate.retire(lease, token: first.token)
        #expect(lease.active == second.token)
        #expect(CarLiveTransportGate.allows(lease, token: second.token))
        #expect(CarLiveTransportGate.allows(lease, token: first.token) == false)
        let overflow = CarLiveTransportGate.arm(CarLiveTransportLease(issued: UInt64.max, active: 0))
        #expect(overflow.token == 0)
        #expect(overflow.lease.issued == UInt64.max)
        #expect(overflow.lease.active == 0)
        #expect(CarLiveRunOwner.shouldClose(current: CarLiveLease(hostID: UUID(), generation: 2, contextKey: "b", epoch: 2), owned: CarLiveLease(hostID: UUID(), generation: 1, contextKey: "a", epoch: 1)) == false)
    }

    @Test func unknownModelFailureIsTyped() {
        switch CarLiveModel.canonicalize("gpt-5.6-sol") {
        case .failure(let error):
            #expect(error.code == "unknown_model")
        case .success:
            Issue.record("unknown model must fail")
        }
    }

    @Test func lateAllowFlipDropsTheNextWrite() async {
        let fake = LiveToolFake()
        let gate = AllowGate()
        let context = CarLiveToolContext(trackedSessionID: nil, directory: "/work", startAgent: "build", allows: { await gate.next() })
        let effect = await CarLiveToolHandler.run(CarLiveToolName.startJob, arguments: #"{"text":"研究路线","requestedModel":null}"#, client: fake, context: context)
        #expect(code(effect.output) == "stale_context")
        #expect(effect.poll == false)
        #expect(await fake.startBodies.isEmpty)
    }

    @Test @MainActor func carLiveConfigSendsEightArchiveTools() throws {
        let state = makeIsolatedAppState()
        let portal = try #require(URL(string: "https://example.invalid"))
        let config = state.carLiveConfiguration(portal: portal, token: "token", ownerToken: "owner")
        let configNames = try toolNames(config.toolsJSON)
        let body = try CarLiveCreateBody.data(for: config)
        let sent = try jsonData(body)
        let sentTools = try #require(sent["tools"] as? [[String: Any]])
        let sentNames = sentTools.compactMap { $0["name"] as? String }
        let unique = Set(sentNames)
        #expect(configNames == CarLiveToolName.native)
        #expect(sentNames == configNames)
        #expect(sentNames.count == 8)
        #expect(unique.count == 8)
        #expect(unique == Set(CarLiveToolName.native))
        #expect(sent["frontend_instructions"] as? String == config.instructions)
        #expect(sent["backend_instructions"] as? String == config.backendInstructions)
        #expect(config.instructions.contains("归档"))
        #expect(config.instructions.contains("取消归档"))
        #expect(config.backendInstructions.contains("archive_job"))
        #expect(config.backendInstructions.contains("unarchive_job"))
        #expect(config.backendInstructions.contains("不要因此 stop_job"))
        #expect(config.backendInstructions.contains("八个"))
        #expect(!config.backendInstructions.contains("六个"))
        #expect(config.instructions == CarLiveProtocol.instructions)
        #expect(config.backendInstructions == CarLiveProtocol.backendInstructions)
        #expect(configNames == CarLiveHostedFunction.names)
        for name in CarLiveArchiveTools.names {
            let tool = try #require(sentTools.first { $0["name"] as? String == name })
            let parameters = try #require(tool["parameters"] as? [String: Any])
            let properties = try #require(parameters["properties"] as? [String: Any])
            #expect(Set(properties.keys) == Set(["sessionID"]))
            let required = parameters["required"] as? [String] ?? (parameters["required"] as? [Any])?.compactMap { $0 as? String }
            #expect(required == ["sessionID"])
            #expect(parameters["additionalProperties"] as? Bool == false)
            #expect(tool["strict"] as? Bool == true)
            #expect((properties["sessionID"] as? [String: Any])?["type"] as? String == "string")
        }
        let canonical = try toolNames(CarLiveProtocol.defaultToolsJSON)
        #expect(canonical == configNames)
    }

    @Test func archiveAndUnarchiveWirePositiveMillisOrZero() async throws {
        let archiveFake = LiveToolFake()
        await archiveFake.setLookupSequence("s1", [
            found(liveSession("s1", archived: nil, parentID: "parent")),
            found(liveSession("s1", archived: 1_700_000_000_000, parentID: "parent")),
        ])
        await archiveFake.setPatchStatus(204)
        let before = CarLiveArchiveTools.archiveMillis()
        let archived = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"s1"}"#, client: archiveFake, context: allowingContext(tracked: "current"))
        let after = CarLiveArchiveTools.archiveMillis()
        let archivePatches = await archiveFake.patches
        let stamp = try #require(archivePatches.first?.archived)
        let archiveBody = try CarLiveArchiveWire.body(archived: stamp)
        let archiveWire = try jsonData(archiveBody)
        let archiveTime = try #require(archiveWire["time"] as? [String: Any])
        let archiveText = String(decoding: archiveBody, as: UTF8.self)
        let archiveObject = try jsonObject(archived.output)
        #expect(stamp > 0)
        #expect(stamp >= before)
        #expect(stamp <= after)
        #expect(stamp != -1)
        #expect(archivePatches.map(\.sessionID) == ["s1"])
        #expect(archiveTime["archived"] as? Int == stamp)
        #expect(!archiveText.contains("null"))
        #expect(archiveObject["ok"] as? Bool == true)
        #expect(archiveObject["status"] as? String == "archived")
        #expect(archiveObject["archived"] as? Bool == true)
        #expect(archiveObject["title"] as? String == "路线")
        #expect(archiveObject["password"] == nil)
        #expect(archiveObject["host"] == nil)
        #expect(archiveObject["directory"] == nil)
        #expect(archived.clearSessionID == nil)
        #expect(archived.poll == false)
        let archiveAborts = await archiveFake.aborts
        let archiveCreates = await archiveFake.creates
        let archiveStarts = await archiveFake.startBodies
        let archiveContinues = await archiveFake.continueBodies
        #expect(archiveAborts.isEmpty)
        #expect(archiveCreates.isEmpty)
        #expect(archiveStarts.isEmpty)
        #expect(archiveContinues.isEmpty)

        let restoreFake = LiveToolFake()
        await restoreFake.setLookupSequence("s1", [
            found(liveSession("s1", archived: -1)),
            found(liveSession("s1", archived: 0)),
        ])
        let restored = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"s1"}"#, client: restoreFake, context: allowingContext(tracked: "current"))
        let restorePatches = await restoreFake.patches
        let zero = try CarLiveArchiveWire.body(archived: 0)
        let zeroWire = try jsonData(zero)
        let zeroTime = try #require(zeroWire["time"] as? [String: Any])
        let zeroText = String(decoding: zero, as: UTF8.self)
        let restoreObject = try jsonObject(restored.output)
        #expect(restorePatches.map(\.archived) == [0])
        #expect(zeroTime["archived"] as? Int == 0)
        #expect(!zeroText.contains("null"))
        #expect(restoreObject["status"] as? String == "unarchived")
        #expect(restoreObject["archived"] as? Bool == false)
        #expect(restored.poll == false)
        let restoreAborts = await restoreFake.aborts
        let restoreCreates = await restoreFake.creates
        #expect(restoreAborts.isEmpty)
        #expect(restoreCreates.isEmpty)
    }

    @Test func alreadyArchivedOrUnarchivedDoesNotPatch() async throws {
        let archived = LiveToolFake()
        await archived.setLookup("s1", found(liveSession("s1", archived: 50)))
        let already = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"s1"}"#, client: archived, context: allowingContext())
        let archivedPatches = await archived.patches
        let alreadyObject = try jsonObject(already.output)
        #expect(archivedPatches.isEmpty)
        #expect(alreadyObject["status"] as? String == "already_archived")
        #expect(alreadyObject["archived"] as? Bool == true)
        #expect(already.poll == false)

        let missingFlag = LiveToolFake()
        await missingFlag.setLookup("s1", found(liveSession("s1", archived: nil)))
        let missing = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"s1"}"#, client: missingFlag, context: allowingContext())
        let missingPatches = await missingFlag.patches
        let missingObject = try jsonObject(missing.output)
        #expect(missingPatches.isEmpty)
        #expect(missingObject["status"] as? String == "already_unarchived")

        let zero = LiveToolFake()
        await zero.setLookup("s1", found(liveSession("s1", archived: 0)))
        let zeroed = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"s1"}"#, client: zero, context: allowingContext())
        let zeroPatches = await zero.patches
        let zeroObject = try jsonObject(zeroed.output)
        #expect(zeroPatches.isEmpty)
        #expect(zeroObject["status"] as? String == "already_unarchived")
        #expect(zeroObject["archived"] as? Bool == false)
    }

    @Test func unknownArchiveDoesNotFallbackAndServerErrorKeepsBinding() async throws {
        let tracked = "current"
        let missingID = await rejectedArchive(arguments: #"{"sessionID":"missing"}"#, lookup: CarLiveLookup(session: nil, httpStatus: 404, transport: false), tracked: tracked)
        #expect(missingID.lookups == ["missing"])
        #expect(missingID.patches.isEmpty)
        #expect(missingID.effect.clearSessionID == "missing")
        #expect(missingID.effect.clearSessionID != tracked)
        #expect(missingID.creates.isEmpty)

        let blank = await rejectedArchive(arguments: #"{"sessionID":"  "}"#, lookup: nil, tracked: tracked)
        #expect(blank.lookups.isEmpty)
        #expect(blank.patches.isEmpty)
        #expect(code(blank.effect.output) == "needs_input")
        #expect(blank.effect.clearSessionID == nil)

        let absent = await rejectedArchive(arguments: "{}", lookup: nil, tracked: tracked)
        #expect(absent.lookups.isEmpty)
        #expect(absent.effect.clearSessionID == nil)

        let nullID = await rejectedArchive(arguments: #"{"sessionID":null}"#, lookup: nil, tracked: tracked)
        #expect(nullID.lookups.isEmpty)
        #expect(code(nullID.effect.output) == "needs_input")

        let numeric = await rejectedArchive(arguments: #"{"sessionID":1}"#, lookup: nil, tracked: tracked)
        #expect(numeric.lookups.isEmpty)
        #expect(code(numeric.effect.output) == "needs_input")

        let server = await rejectedArchive(arguments: #"{"sessionID":"s1"}"#, lookup: CarLiveLookup(session: nil, httpStatus: 500, transport: false), tracked: tracked)
        #expect(server.effect.clearSessionID == nil)
        #expect(server.patches.isEmpty)
        #expect(code(server.effect.output) == "lookup_failed")
        #expect(server.creates.isEmpty)

        let denied = await rejectedArchive(arguments: #"{"sessionID":"s1"}"#, lookup: CarLiveLookup(session: nil, httpStatus: 401, transport: false), tracked: tracked)
        #expect(denied.effect.clearSessionID == nil)
        #expect(denied.patches.isEmpty)

        let offline = await rejectedArchive(arguments: #"{"sessionID":"s1"}"#, lookup: CarLiveLookup(session: nil, httpStatus: 0, transport: true), tracked: tracked)
        #expect(offline.effect.clearSessionID == nil)
        #expect(offline.patches.isEmpty)
        #expect(offline.creates.isEmpty)

        let mismatch = await rejectedArchive(arguments: #"{"sessionID":"s1"}"#, lookup: found(liveSession("other")), tracked: tracked)
        #expect(mismatch.patches.isEmpty)
        #expect(mismatch.effect.clearSessionID == nil)
        #expect(mismatch.lookups == ["s1"])

        let noDirectory = await rejectedArchive(arguments: #"{"sessionID":"s1"}"#, lookup: found(liveSession("s1", directory: "  ")), tracked: tracked)
        #expect(noDirectory.patches.isEmpty)
        #expect(noDirectory.effect.clearSessionID == nil)
        #expect(code(noDirectory.effect.output) == "directory_unknown")
    }

    @Test func patchAcceptedButReadbackUnchangedIsNotConfirmed() async throws {
        let accepted = LiveToolFake()
        await accepted.setPatchStatus(200)
        await accepted.setLookupSequence("s1", [
            found(liveSession("s1", archived: nil)),
            found(liveSession("s1", archived: nil)),
        ])
        let archive = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"s1"}"#, client: accepted, context: allowingContext())
        let archivePatches = await accepted.patches
        let archiveObject = try jsonObject(archive.output)
        #expect(archivePatches.count == 1)
        #expect((archivePatches.first?.archived ?? 0) > 0)
        #expect(archiveObject["ok"] as? Bool == false)
        #expect(archiveObject["status"] as? String == "not_confirmed")
        #expect(archiveObject["error"] as? String == "not_confirmed")
        #expect(archiveObject["archived"] as? Bool == false)
        #expect(archive.clearSessionID == nil)
        #expect(archive.poll == false)
        let archiveAborts = await accepted.aborts
        #expect(archiveAborts.isEmpty)

        let noContent = LiveToolFake()
        await noContent.setPatchStatus(204)
        await noContent.setLookupSequence("s1", [
            found(liveSession("s1", archived: 80)),
            found(liveSession("s1", archived: 80)),
        ])
        let restore = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"s1"}"#, client: noContent, context: allowingContext())
        let restorePatches = await noContent.patches
        let restoreObject = try jsonObject(restore.output)
        #expect(restorePatches.map(\.archived) == [0])
        #expect(restoreObject["status"] as? String == "not_confirmed")
        #expect(restoreObject["archived"] as? Bool == true)
        #expect(restore.clearSessionID == nil)
        let restoreAborts = await noContent.aborts
        let restoreStarts = await noContent.startBodies
        #expect(restoreAborts.isEmpty)
        #expect(restoreStarts.isEmpty)
    }

    @Test func lateOwnerDoesNotPatchOrReverseArchive() async {
        let blocked = LeaseFlag()
        let beforePatch = LiveToolFake()
        await beforePatch.setLookup("s1", found(liveSession("s1", archived: nil)))
        await beforePatch.setAfterLookup { await blocked.close() }
        let blockedEffect = await CarLiveToolHandler.run(
            CarLiveToolName.archiveJob,
            arguments: #"{"sessionID":"s1"}"#,
            client: beforePatch,
            context: CarLiveToolContext(trackedSessionID: "current", directory: "/work", startAgent: "build", allows: { await blocked.allows() })
        )
        let blockedPatches = await beforePatch.patches
        let blockedAborts = await beforePatch.aborts
        #expect(code(blockedEffect.output) == "stale_context")
        #expect(blockedPatches.isEmpty)
        #expect(blockedAborts.isEmpty)
        #expect(blockedEffect.clearSessionID == nil)
        #expect(blockedEffect.poll == false)

        let expired = LeaseFlag()
        let afterPatch = LiveToolFake()
        await afterPatch.setLookup("s1", found(liveSession("s1", archived: nil)))
        await afterPatch.setAfterPatch { await expired.close() }
        let expiredEffect = await CarLiveToolHandler.run(
            CarLiveToolName.archiveJob,
            arguments: #"{"sessionID":"s1"}"#,
            client: afterPatch,
            context: CarLiveToolContext(trackedSessionID: "current", directory: "/work", startAgent: "build", allows: { await expired.allows() })
        )
        let expiredPatches = await afterPatch.patches
        #expect(code(expiredEffect.output) == "stale_context")
        #expect(expiredPatches.count == 1)
        #expect((expiredPatches.first?.archived ?? 0) > 0)
        #expect(!expiredPatches.contains { $0.archived == 0 })
        #expect(expiredEffect.poll == false)

        let closed = LiveToolFake()
        await closed.setLookup("s1", found(liveSession("s1", archived: 40)))
        await closed.setPatchError(CarLiveAPIUnsupported.closed)
        let closedEffect = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"s1"}"#, client: closed, context: allowingContext())
        let closedPatches = await closed.patches
        #expect(code(closedEffect.output) == "stale_context")
        #expect(closedPatches.map(\.archived) == [0])
        #expect(closedEffect.clearSessionID == nil)

        let failed = LiveToolFake()
        await failed.setLookup("s1", found(liveSession("s1", archived: nil)))
        await failed.setPatchError(APIError.httpError(statusCode: 500, data: Data()))
        let failedEffect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"s1"}"#, client: failed, context: allowingContext())
        let failedPatches = await failed.patches
        #expect(failedEffect.clearSessionID == nil)
        #expect(failedPatches.count == 1)
        #expect((failedPatches.first?.archived ?? 0) > 0)
        #expect(code(failedEffect.output) == "failed")
    }

    @Test func archiveLiveDefaultDoesNotUseUnguardedPatch() async {
        let api = MockAPIClient()
        do {
            _ = try await api.updateSessionArchivedForLive(sessionID: "s1", archived: 1, transportToken: 1)
            Issue.record("unsupported archive must throw")
        } catch {
            #expect(error as? CarLiveAPIUnsupported == .archive)
        }
        let calls = await api.updateSessionArchivedCalls
        #expect(calls.isEmpty)
    }

    @Test func archiveOrderIsPostorderAndRestoreIsPreorder() {
        let children = ["parent": ["child"], "child": ["grandchild"]]
        let archive = CarLiveArchiveTools.ids(root: "parent", children: children, parentFirst: false)
        let restore = CarLiveArchiveTools.ids(root: "parent", children: children, parentFirst: true)
        #expect(archive == ["grandchild", "child", "parent"])
        #expect(restore == ["parent", "child", "grandchild"])
    }

    @Test func archiveSyncsGrandchildrenAndDoesNotSkipChildWhenRootAlreadyArchived() async throws {
        let fake = LiveToolFake()
        await fake.setLookup("parent", found(liveSession("parent", archived: 40, title: "根")))
        await fake.setLookup("child", found(liveSession("child", archived: 40, parentID: "parent")))
        await fake.setLookup("grandchild", found(liveSession("grandchild", archived: 40, parentID: "child")))
        await fake.setChildren("parent", [liveSession("child", archived: nil, parentID: "parent", title: "子")])
        await fake.setChildren("child", [liveSession("grandchild", archived: nil, parentID: "child", title: "孙")])
        let effect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: fake, context: allowingContext(tracked: "current"))
        let patches = await fake.patches
        let object = try jsonObject(effect.output)
        let stamps = Set(patches.map(\.archived))
        #expect(patches.map(\.sessionID) == ["grandchild", "child"])
        #expect(stamps.count == 1)
        #expect((stamps.first ?? 0) > 0)
        #expect(object["ok"] as? Bool == true)
        #expect(object["status"] as? String == "archived")
        #expect(object["status"] as? String != "already_archived")
        #expect(effect.clearSessionID == nil)
        let aborts = await fake.aborts
        let creates = await fake.creates
        #expect(aborts.isEmpty)
        #expect(creates.isEmpty)
    }

    @Test func unarchiveWalksRootBeforeDescendantsAndWritesZero() async throws {
        let fake = LiveToolFake()
        await fake.setLookupSequence("parent", [
            found(liveSession("parent", archived: 40, title: "根")),
            found(liveSession("parent", archived: 0, title: "根")),
        ])
        await fake.setLookup("child", found(liveSession("child", archived: 0, parentID: "parent")))
        await fake.setLookup("grandchild", found(liveSession("grandchild", archived: 0, parentID: "child")))
        await fake.setChildren("parent", [liveSession("child", archived: 40, parentID: "parent")])
        await fake.setChildren("child", [liveSession("grandchild", archived: 40, parentID: "child")])
        let effect = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"parent"}"#, client: fake, context: allowingContext())
        let patches = await fake.patches
        let object = try jsonObject(effect.output)
        #expect(patches.map(\.sessionID) == ["parent", "child", "grandchild"])
        #expect(patches.allSatisfy { $0.archived == 0 })
        #expect(object["status"] as? String == "unarchived")
        #expect(object["archived"] as? Bool == false)
        let aborts = await fake.aborts
        let starts = await fake.startBodies
        #expect(aborts.isEmpty)
        #expect(starts.isEmpty)
    }

    @Test func archiveStopsOnCycleDuplicateDiscoveryErrorAndChildWriteFailure() async throws {
        let cycle = LiveToolFake()
        await cycle.setLookupSequence("parent", [
            found(liveSession("parent", archived: nil)),
            found(liveSession("parent", archived: 20)),
        ])
        await cycle.setLookup("child", found(liveSession("child", archived: 20, parentID: "parent")))
        await cycle.setChildren("parent", [liveSession("child", archived: nil, parentID: "parent")])
        await cycle.setChildren("child", [liveSession("parent", archived: nil, parentID: "child")])
        let cycleEffect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: cycle, context: allowingContext())
        let cyclePatches = await cycle.patches
        let cycleCalls = await cycle.childCalls
        #expect(cyclePatches.map(\.sessionID) == ["child", "parent"])
        #expect(cycleCalls.count < 8)
        #expect(code(cycleEffect.output) == nil)

        let duplicate = LiveToolFake()
        await duplicate.setLookupSequence("parent", [
            found(liveSession("parent", archived: nil)),
            found(liveSession("parent", archived: 20)),
        ])
        await duplicate.setLookup("child", found(liveSession("child", archived: 20, parentID: "parent")))
        let repeated = liveSession("child", archived: nil, parentID: "parent")
        await duplicate.setChildren("parent", [repeated, repeated])
        let duplicateEffect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: duplicate, context: allowingContext())
        let duplicatePatches = await duplicate.patches
        #expect(duplicatePatches.map(\.sessionID) == ["child", "parent"])
        #expect(code(duplicateEffect.output) == nil)

        let missingParent = LiveToolFake()
        await missingParent.setLookup("parent", found(liveSession("parent", archived: nil)))
        await missingParent.setChildren("parent", [liveSession("child", archived: nil, parentID: "other")])
        let mismatch = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: missingParent, context: allowingContext())
        let mismatchPatches = await missingParent.patches
        #expect(mismatchPatches.isEmpty)
        #expect(code(mismatch.output) == "lookup_failed")

        let broken = LiveToolFake()
        await broken.setLookup("parent", found(liveSession("parent", archived: nil)))
        await broken.setChildrenError("parent", APIError.httpError(statusCode: 500, data: Data()))
        let discovery = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: broken, context: allowingContext())
        let discoveryPatches = await broken.patches
        #expect(discoveryPatches.isEmpty)
        #expect(code(discovery.output) == "lookup_failed")
        #expect(discovery.clearSessionID == nil)

        let failedChild = LiveToolFake()
        await failedChild.setLookup("parent", found(liveSession("parent", archived: nil, title: "根")))
        await failedChild.setChildren("parent", [liveSession("child", archived: nil, parentID: "parent")])
        await failedChild.setPatchError(APIError.httpError(statusCode: 500, data: Data()))
        let write = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: failedChild, context: allowingContext())
        let writePatches = await failedChild.patches
        let writeObject = try jsonObject(write.output)
        #expect(writePatches.map(\.sessionID) == ["child"])
        #expect(writeObject["ok"] as? Bool == false)
        #expect(writeObject["status"] as? String != "archived")
        #expect(write.clearSessionID == nil)
        let writeAborts = await failedChild.aborts
        #expect(writeAborts.isEmpty)

        let missingChild = LiveToolFake()
        await missingChild.setLookup("parent", found(liveSession("parent", archived: nil)))
        await missingChild.setChildren("parent", [liveSession("child", archived: nil, parentID: "parent")])
        await missingChild.setPatchError(APIError.httpError(statusCode: 404, data: Data()))
        let gone = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: missingChild, context: allowingContext())
        #expect(gone.clearSessionID == nil)
        #expect(code(gone.output) != nil)
    }

    @Test func lateHostStopsLaterArchivePatchesWithoutReverse() async {
        let lease = LeaseFlag()
        let fake = LiveToolFake()
        await fake.setLookup("parent", found(liveSession("parent", archived: nil)))
        await fake.setLookup("child", found(liveSession("child", archived: 30, parentID: "parent")))
        await fake.setChildren("parent", [liveSession("child", archived: nil, parentID: "parent")])
        await fake.setAfterPatch { await lease.close() }
        let effect = await CarLiveToolHandler.run(
            CarLiveToolName.archiveJob,
            arguments: #"{"sessionID":"parent"}"#,
            client: fake,
            context: CarLiveToolContext(trackedSessionID: "current", directory: "/work", startAgent: "build", allows: { await lease.allows() })
        )
        let patches = await fake.patches
        #expect(code(effect.output) == "stale_context")
        #expect(patches.map(\.sessionID) == ["child"])
        #expect(!patches.contains { $0.archived == 0 })
        #expect(effect.clearSessionID == nil)
        let aborts = await fake.aborts
        #expect(aborts.isEmpty)
    }

    @Test func changedSnapshotAfterArchiveIsPartialNotComplete() async throws {
        let fake = LiveToolFake()
        await fake.setLookupSequence("parent", [
            found(liveSession("parent", archived: nil, title: "根")),
            found(liveSession("parent", archived: 70, title: "根")),
        ])
        await fake.setChildrenSequence("parent", [
            [liveSession("child", archived: 70, parentID: "parent")],
            [
                liveSession("child", archived: 70, parentID: "parent"),
                liveSession("newborn", archived: nil, parentID: "parent"),
            ],
        ])
        let effect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: fake, context: allowingContext())
        let patches = await fake.patches
        let object = try jsonObject(effect.output)
        let pending = object["pendingIDs"] as? [String]
        #expect(patches.map(\.sessionID) == ["parent"])
        #expect(object["ok"] as? Bool == false)
        #expect(object["status"] as? String == "partial")
        #expect(object["archived"] as? Bool == true)
        #expect((object["verifiedIDs"] as? [String])?.contains("parent") == true)
        #expect(object["snapshot"] as? Bool == true)
        #expect(pending == ["newborn"])
        #expect((object["message"] as? String)?.contains("newborn") == false)
        #expect(object["password"] == nil)
        #expect(object["host"] == nil)
        #expect(object["directory"] == nil)

        let restore = LiveToolFake()
        await restore.setLookupSequence("parent", [
            found(liveSession("parent", archived: 40, title: "根")),
            found(liveSession("parent", archived: 0, title: "根")),
        ])
        await restore.setChildrenSequence("parent", [
            [liveSession("child", archived: 0, parentID: "parent")],
            [
                liveSession("child", archived: 0, parentID: "parent"),
                liveSession("newborn", archived: 40, parentID: "parent"),
            ],
        ])
        let restored = await CarLiveToolHandler.run(CarLiveToolName.unarchiveJob, arguments: #"{"sessionID":"parent"}"#, client: restore, context: allowingContext())
        let restoredObject = try jsonObject(restored.output)
        #expect(restoredObject["ok"] as? Bool == false)
        #expect(restoredObject["status"] as? String == "partial")
        #expect(restoredObject["archived"] as? Bool == false)
    }

    @Test func partialArchiveResultStaysWithinFunctionOutputLimit() {
        let ids = (0..<2000).map { String(repeating: "s", count: 80) + "\($0)" }
        let text = CarLiveArchiveTools.partial(
            sessionID: "root",
            title: "根",
            archived: false,
            verified: ids,
            failed: ids,
            pending: ids,
            error: "partial",
            message: "子树没有全部确认。不要说已经全部完成。"
        )
        #expect(text.utf8.count <= CarLiveProtocol.maxFunctionOutputBytes)
        let object = try? jsonObject(text)
        #expect(object?["verified"] as? Int == 2000)
        #expect(object?["failed"] as? Int == 2000)
        #expect(object?["truncated"] as? Bool == true)
        #expect(object?["password"] == nil)
    }

    @Test func archiveNodeCapReturnsPartialWithoutPatch() async throws {
        let fake = LiveToolFake()
        await fake.setLookup("parent", found(liveSession("parent", archived: nil, title: "根")))
        let children = (0..<CarLiveArchiveTools.maxNodes).map { index in
            liveSession("child-\(index)", archived: nil, parentID: "parent")
        }
        await fake.setChildren("parent", children)
        let effect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: #"{"sessionID":"parent"}"#, client: fake, context: allowingContext())
        let patches = await fake.patches
        let object = try jsonObject(effect.output)
        #expect(patches.isEmpty)
        #expect(object["ok"] as? Bool == false)
        #expect(object["status"] as? String == "partial")
        #expect(object["status"] as? String != "archived")
        #expect(effect.clearSessionID == nil)
    }

    @Test func retiredLiveTokenIsNotReusedOnTheNextHost() async throws {
        LiveHostGate.shared.reset()
        let session = makeLiveHostSession()
        let api = APIClient(baseURL: "https://priv01-a.invalid", username: "a", password: "fixture-a", session: session)
        let old = await api.armLiveTransport()
        await api.retireLiveTransport(token: old)
        await api.configure(baseURL: "https://priv01-b.invalid", username: "b", password: "fixture-b")
        let fresh = await api.armLiveTransport()
        #expect(fresh != old)
        #expect(fresh != 0)
        do {
            _ = try await api.updateSessionArchivedForLive(sessionID: "s1", archived: 1, transportToken: old)
            Issue.record("retired token must be rejected")
        } catch {
            #expect(error as? CarLiveAPIUnsupported == .closed)
        }
        let hits = LiveHostGate.shared.snapshot()
        #expect(hits.isEmpty)
    }

    @Test func queuedArchiveWriteDoesNotReachTheRearmedHost() async throws {
        LiveHostGate.shared.reset()
        let session = makeLiveHostSession()
        let api = APIClient(baseURL: "https://priv01-a.invalid", username: "a", password: "fixture-a", session: session)
        let old = await api.armLiveTransport()
        let hold = LiveWriteHold()
        let task = Task {
            await hold.enterAndWait()
            do {
                _ = try await api.updateSessionArchivedForLive(sessionID: "s1", archived: 9, transportToken: old)
                return false
            } catch {
                return (error as? CarLiveAPIUnsupported) == .closed
            }
        }
        for _ in 0..<50 {
            if await hold.hasEntered() { break }
            await Task.yield()
        }
        let entered = await hold.hasEntered()
        #expect(entered)
        await api.retireLiveTransport(token: old)
        await api.configure(baseURL: "https://priv01-b.invalid", username: "b", password: "fixture-b")
        let fresh = await api.armLiveTransport()
        #expect(fresh != old)
        await hold.go()
        let rejected = await task.value
        #expect(rejected)
        let hits = LiveHostGate.shared.snapshot()
        #expect(hits.isEmpty)
    }

    @Test func stopGraceDoesNotLeaveOldArchiveWriteArmed() async throws {
        LiveHostGate.shared.reset()
        let session = makeLiveHostSession()
        let api = APIClient(baseURL: "https://priv01-a.invalid", username: "a", password: "fixture-a", session: session)
        let old = await api.armLiveTransport()
        let hold = LiveWriteHold()
        let grace = LiveWriteHold()
        let task = Task {
            await hold.enterAndWait()
            do {
                _ = try await api.updateSessionArchivedForLive(sessionID: "s1", archived: 9, transportToken: old)
                return false
            } catch {
                return (error as? CarLiveAPIUnsupported) == .closed
            }
        }
        let graceTask = Task {
            await grace.enterAndWait()
        }
        for _ in 0..<50 {
            if await hold.hasEntered(), await grace.hasEntered() { break }
            await Task.yield()
        }
        let entered = await hold.hasEntered()
        let graceHeld = await grace.hasEntered()
        #expect(entered)
        #expect(graceHeld)
        await api.retireLiveTransport(token: old)
        let fresh = await api.armLiveTransport()
        await api.retireLiveTransport(token: old)
        #expect(fresh != old)
        #expect(fresh != 0)
        await hold.go()
        let rejected = await task.value
        let stillHeld = await grace.hasEntered()
        #expect(rejected)
        #expect(stillHeld)
        let hits = LiveHostGate.shared.snapshot()
        #expect(hits.isEmpty)
        await grace.go()
        await graceTask.value
    }
}

private actor QueuedThenIdle {
    private var reads = 0
    private(set) var abortCount = 0

    func abort() {
        abortCount += 1
    }

    func status() -> String? {
        reads += 1
        return reads == 1 ? "queued" : nil
    }
}

private actor LiveToolFake: CarLiveToolClient {
    var creates: [String?] = []
    var startBodies: [[String: Any]] = []
    var continueBodies: [[String: Any]] = []
    var aborts: [String] = []
    var roundCalls = 0
    private(set) var lookupIDs: [String] = []
    private(set) var patches: [(sessionID: String, archived: Int)] = []
    private var window = CarLiveListWindow(records: [], skip: 0, count: 10, returned: 0, hasMore: false, nextSkip: nil, partial: false, fetchMore: false)
    private var lookups: [String: CarLiveLookup] = [:]
    private var lookupQueues: [String: [CarLiveLookup]] = [:]
    private var patchStatus = 204
    private var patchError: Error?
    private var afterLookup: (() async -> Void)?
    private var afterPatch: (() async -> Void)?
    private var childrenByParent: [String: [Session]] = [:]
    private var childrenQueues: [String: [[Session]]] = [:]
    private var childrenErrors: [String: Error] = [:]
    private(set) var childCalls: [String] = []

    func setWindow(_ window: CarLiveListWindow) { self.window = window }
    func setLookup(_ id: String, _ lookup: CarLiveLookup) { lookups[id] = lookup }
    func setLookupSequence(_ id: String, _ values: [CarLiveLookup]) { lookupQueues[id] = values }
    func setPatchStatus(_ status: Int) { patchStatus = status }
    func setPatchError(_ error: Error?) { patchError = error }
    func setAfterLookup(_ hook: @escaping () async -> Void) { afterLookup = hook }
    func setAfterPatch(_ hook: @escaping () async -> Void) { afterPatch = hook }
    func setChildren(_ parent: String, _ sessions: [Session]) { childrenByParent[parent] = sessions }
    func setChildrenSequence(_ parent: String, _ pages: [[Session]]) { childrenQueues[parent] = pages }
    func setChildrenError(_ parent: String, _ error: Error) { childrenErrors[parent] = error }

    func listed(archivedOnly: Bool, skip: Int, count: Int) async throws -> CarLiveListWindow { window }
    func lookup(id: String, directory: String?) async -> CarLiveLookup {
        lookupIDs.append(id)
        let result: CarLiveLookup
        if var queue = lookupQueues[id], !queue.isEmpty {
            result = queue.removeFirst()
            lookupQueues[id] = queue
        } else {
            result = lookups[id] ?? CarLiveLookup(session: nil, httpStatus: 404, transport: false)
        }
        await afterLookup?()
        return result
    }
    func history(sessionID: String, directory: String, skip: Int, count: Int) async -> String { "{}" }
    func connectedRefs() async throws -> Set<String> { Set(CarLiveModel.refs) }
    func create(directory: String?) async throws -> Session {
        creates.append(directory)
        return session("created", directory: directory ?? "/tmp")
    }
    func startPrompt(sessionID: String, messageID: String, text: String, agent: String, model: Message.ModelInfo, directory: String?) async throws -> Data {
        let data = try CarLivePromptWire.startData(messageID: messageID, text: text, agent: agent, model: model)
        startBodies.append(CarLivePromptWire.object(data))
        return data
    }
    func continuePrompt(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?) async throws -> Data {
        let data = try CarLivePromptWire.continueData(messageID: messageID, text: text, agent: agent, variant: variant)
        continueBodies.append(CarLivePromptWire.object(data))
        return data
    }
    func confirmStop(sessionID: String) async throws -> String {
        aborts.append(sessionID)
        return CarLiveToolJSON.stopped()
    }
    func setArchived(sessionID: String, archived: Int) async throws -> Int {
        patches.append((sessionID, archived))
        await afterPatch?()
        if let patchError { throw patchError }
        return patchStatus
    }
    func children(sessionID: String) async throws -> [Session] {
        childCalls.append(sessionID)
        if let error = childrenErrors[sessionID] { throw error }
        if var queue = childrenQueues[sessionID], !queue.isEmpty {
            let page = queue.removeFirst()
            childrenQueues[sessionID] = queue
            return page
        }
        return childrenByParent[sessionID] ?? []
    }
    func answer(sessionID: String, answers: [[String]], permissionReply: String?) async throws {}
    func round(sessionID: String, messageID: String) async throws -> CarLiveRoundSnapshot {
        roundCalls += 1
        return CarLiveRoundSnapshot(assistantText: nil, finalFinish: false, openTools: false, childrenActive: false, pending: false, failed: false)
    }
}

private actor AllowGate {
    private var reads = 0
    func next() -> Bool {
        reads += 1
        return reads < 3
    }
}

private struct ArchiveProbe {
    var effect: CarLiveToolEffect
    var lookups: [String]
    var patches: [(sessionID: String, archived: Int)]
    var creates: [String?]
}

private func rejectedArchive(arguments: String, lookup: CarLiveLookup?, tracked: String) async -> ArchiveProbe {
    let fake = LiveToolFake()
    if let lookup {
        await fake.setLookup("s1", lookup)
        await fake.setLookup("missing", lookup)
    }
    let effect = await CarLiveToolHandler.run(CarLiveToolName.archiveJob, arguments: arguments, client: fake, context: allowingContext(tracked: tracked))
    let lookups = await fake.lookupIDs
    let patches = await fake.patches
    let creates = await fake.creates
    return ArchiveProbe(effect: effect, lookups: lookups, patches: patches, creates: creates)
}

private final class LiveHostGate: @unchecked Sendable {
    static let shared = LiveHostGate()
    private let lock = NSLock()
    private var hits: [String] = []

    func record(_ host: String) {
        lock.lock()
        hits.append(host)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    func reset() {
        lock.lock()
        hits.removeAll()
        lock.unlock()
    }
}

private final class LiveHostHTTP: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("priv01-") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let host = request.url?.host {
            LiveHostGate.shared.record(host)
        }
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}

private func makeLiveHostSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LiveHostHTTP.self]
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil
    return URLSession(configuration: config)
}

private actor LiveWriteHold {
    private var entered = false
    private var release = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        await withCheckedContinuation { continuation in
            entered = true
            if release {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func hasEntered() -> Bool { entered }

    func go() {
        release = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor LeaseFlag {
    private var open = true
    func close() { open = false }
    func allows() -> Bool { open }
}

private func allowingContext(tracked: String? = nil, allows: Bool = true) -> CarLiveToolContext {
    CarLiveToolContext(trackedSessionID: tracked, directory: "/work", startAgent: "build", allows: { allows })
}

private func item(_ id: String, parentID: String = "", archivedAt: Int) -> CarLiveListItem {
    CarLiveListItem(id: id, title: id, directory: "/tmp", status: "idle", updated: archivedAt, archivedAt: archivedAt, parentID: parentID)
}

private func liveSession(_ id: String, directory: String = "/work", archived: Int? = nil, parentID: String? = nil, title: String = "路线") -> Session {
    Session(id: id, slug: id, projectID: "p", directory: directory, parentID: parentID, title: title, version: "1", time: .init(created: 1, updated: 2, archived: archived), share: nil, summary: nil)
}

private func found(_ session: Session) -> CarLiveLookup {
    CarLiveLookup(session: session, httpStatus: 200, transport: false)
}

private func session(_ id: String, directory: String = "/tmp", agent: String? = nil, variant: String? = nil) -> Session {
    _ = agent
    _ = variant
    return Session(id: id, slug: id, projectID: "p", directory: directory, parentID: nil, title: id, version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
}

private func row(id: String, role: String, created: Int, completed: Int? = nil, text: String) -> MessageWithParts {
    MessageWithParts(
        info: Message(id: id, sessionID: "s1", role: role, parentID: nil, providerID: nil, modelID: nil, model: nil, error: nil, time: .init(created: created, completed: completed), finish: "stop", tokens: nil, cost: nil),
        parts: [Part(id: "p-\(id)", messageID: id, sessionID: "s1", type: "text", text: text, tool: nil, callID: nil, state: nil, metadata: nil, files: nil)]
    )
}

private func jsonData(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func toolNames(_ data: Data) throws -> [String] {
    let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    return rows.compactMap { $0["name"] as? String }
}

private func jsonObject(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func code(_ text: String) -> String? {
    (try? jsonObject(text))?["error"] as? String
}

private func status(_ text: String) -> String? {
    (try? jsonObject(text))?["status"] as? String
}

private func modelRef(_ data: Data) -> String? {
    modelRef(CarLivePromptWire.object(data))
}

private func modelRef(_ object: [String: Any]) -> String? {
    guard let model = object["model"] as? [String: Any],
          let provider = model["providerID"] as? String,
          let id = model["modelID"] as? String else { return nil }
    return "\(provider)/\(id)"
}
