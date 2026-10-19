import Foundation
import Testing
@testable import OpenCodeClient

struct CarLiveReplyBridgeTests {
    @Test @MainActor func watchUnconfirmedDeliveryCanBeDiscardedWithoutReplay() async throws {
        let h = ReplyHarness()
        h.bridge.requiresGatewayAcknowledgement = true
        var laterTurn = false
        h.pages = { _, _, _ in
            var rows = [liveRow(id: "a1", sessionID: "s", role: "assistant", text: "第一条回复")]
            if laterTurn {
                rows.append(liveRow(id: "u2", sessionID: "s", role: "user", text: "继续"))
                rows.append(liveRow(id: "a2", sessionID: "s", role: "assistant", text: "第二条回复"))
            }
            return livePage(rows)
        }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(token)
        await h.bridge.flush()
        let event = try #require(h.sent.first?.eventID)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 1)
        h.bridge.noteUndelivered(event)
        laterTurn = true
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 2)
        #expect(h.sent.last?.text.contains("第二条回复") == true)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 2)
    }

    @Test @MainActor func parentIdleSendsCompletedTextWithoutChildrenOrParentGate() async {
        let h = ReplyHarness()
        h.pages = { _, _, _ in
            livePage([
                liveRow(id: "u1", sessionID: "s", role: "user", text: "做路线"),
                liveRow(id: "tool", sessionID: "s", role: "assistant", text: "调用工具", finish: "tool-calls"),
                liveRow(id: "a1", sessionID: "s", role: "assistant", parentID: "later-user", text: "先核实预约", agent: "research"),
            ])
        }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(token)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 1)
        #expect(h.sent[0].text.contains("先核实预约"))
        #expect(h.sent[0].text.contains("来源会话：路线"))
        #expect(h.sent[0].text.contains("来源编号：s"))
        #expect(h.sent[0].text.contains("来源 agent：research"))
        #expect(!h.sent[0].text.contains("gpt-6.1-sol"))
        #expect(!h.sent[0].text.contains("调用工具"))
        #expect(h.sent[0].owner == "owner")
    }

    @Test @MainActor func laterSummaryUsesNewAssistantID() async {
        let h = ReplyHarness()
        var includeSummary = false
        h.pages = { _, _, _ in
            var rows = [
                liveRow(id: "a1", sessionID: "s", role: "assistant", parentID: "u1", text: "先交给子代理"),
            ]
            if includeSummary {
                rows.append(liveRow(id: "a2", sessionID: "s", role: "assistant", parentID: "synthetic", text: "预约已核对"))
            }
            return livePage(rows)
        }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(token)
        await h.bridge.flush()
        includeSummary = true
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.map(\.text).filter { $0.contains("先交给子代理") }.count == 1)
        #expect(h.sent.contains { $0.text.contains("预约已核对") && !$0.text.contains("来源 agent：") })
    }

    @Test @MainActor func sessionsAAndBStayIndependent() async {
        let h = ReplyHarness()
        h.pages = { id, _, _ in
            livePage([liveRow(id: "a-\(id)", sessionID: id, role: "assistant", text: "回复\(id)")])
        }
        let a = await h.reserve(sessionID: "A", directory: "/a", title: "甲", isNew: true)
        let b = await h.reserve(sessionID: "B", directory: "/b", title: "乙", isNew: true)
        await h.bridge.accept(a)
        await h.bridge.accept(b)
        await h.bridge.flush()
        #expect(h.bridge.subscribedSessionIDs == ["A", "B"])
        #expect(h.sent.contains { $0.text.contains("回复A") && $0.text.contains("来源会话：甲") })
        #expect(h.sent.contains { $0.text.contains("回复B") && $0.text.contains("来源会话：乙") })
        await h.bridge.noteExplicitIdle(sessionID: "A")
        await h.bridge.flush()
        #expect(h.sent.filter { $0.text.contains("回复B") }.count == 1)
    }

    @Test @MainActor func duplicateIdleSendsOnce() async {
        let h = ReplyHarness()
        h.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "一次")]) }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(token)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 1)
    }

    @Test @MainActor func idleBeforeAcceptDoesNotSendUntilAccepted() async {
        let h = ReplyHarness()
        h.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "已经完成")]) }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.isEmpty)
        await h.bridge.accept(token)
        await h.bridge.flush()
        #expect(h.sent.count == 1)
        #expect(h.sent[0].text.contains("已经完成"))
    }

    @Test @MainActor func reconnectUsesScopedSnapshotAndDoesNotReplay() async {
        let h = ReplyHarness()
        h.statuses = { directory in
            if directory == "/a" { return ["A": SessionStatus(type: "busy", attempt: nil, message: nil, next: nil)] }
            return [:]
        }
        h.pages = { id, _, _ in livePage([liveRow(id: "m-\(id)", sessionID: id, role: "assistant", text: "补\(id)")]) }
        let a = await h.reserve(sessionID: "A", directory: "/a", title: "甲", isNew: true)
        let b = await h.reserve(sessionID: "B", directory: "/b", title: "乙", isNew: true)
        await h.bridge.accept(a)
        await h.bridge.accept(b)
        await h.bridge.flush()
        #expect(h.sent.map(\.text).filter { $0.contains("补A") }.isEmpty)
        #expect(h.sent.contains { $0.text.contains("补B") })
        let before = h.sent.count
        await h.bridge.noteConnected()
        await h.bridge.flush()
        #expect(h.directories.contains("/a"))
        #expect(h.directories.contains("/b"))
        #expect(h.sent.count == before)
        #expect(!h.sent.contains { $0.text.contains("补A") })
    }

    @Test @MainActor func failedOrStaleSnapshotIsNotIdle() async {
        let failed = ReplyHarness()
        failed.statuses = { _ in throw ReplyStubError() }
        failed.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "正文")]) }
        let failedToken = await failed.reserve(sessionID: "s", isNew: true)
        await failed.bridge.accept(failedToken)
        await failed.bridge.flush()
        #expect(failed.sent.isEmpty)
        await failed.bridge.noteExplicitIdle(sessionID: "s")
        await failed.bridge.flush()
        #expect(failed.sent.count == 1)

        let stale = ReplyHarness()
        stale.statuses = { _ in
            stale.revisionValue += 1
            return [:]
        }
        stale.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "过期")]) }
        let staleToken = await stale.reserve(sessionID: "s", isNew: true)
        await stale.bridge.accept(staleToken)
        await stale.bridge.flush()
        #expect(stale.sent.isEmpty)
        await stale.bridge.noteConnected()
        await stale.bridge.flush()
        #expect(stale.sent.isEmpty)
    }

    @Test @MainActor func sendFailureRetriesOnceAndAckOrSubmitDoesNotReplay() async {
        let failed = ReplyHarness()
        failed.bridge.submit = { text, eventID, owner in
            failed.sent.append((text, eventID, owner))
            return false
        }
        failed.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "失败")]) }
        let failedToken = await failed.reserve(sessionID: "s", isNew: true)
        await failed.bridge.accept(failedToken)
        await failed.bridge.flush()
        await failed.bridge.noteExplicitIdle(sessionID: "s")
        await failed.bridge.flush()
        await failed.bridge.noteExplicitIdle(sessionID: "s")
        await failed.bridge.flush()
        #expect(failed.sent.count == 2)

        let early = ReplyHarness()
        early.bridge.submit = { text, eventID, owner in
            early.sent.append((text, eventID, owner))
            early.bridge.noteAppended(eventID)
            return false
        }
        early.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "早确认")]) }
        let earlyToken = await early.reserve(sessionID: "s", isNew: true)
        await early.bridge.accept(earlyToken)
        await early.bridge.flush()
        await early.bridge.noteExplicitIdle(sessionID: "s")
        await early.bridge.flush()
        #expect(early.sent.count == 1)

        let submitted = ReplyHarness()
        submitted.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "已提交")]) }
        let submittedToken = await submitted.reserve(sessionID: "s", isNew: true)
        await submitted.bridge.accept(submittedToken)
        await submitted.bridge.flush()
        await submitted.bridge.noteExplicitIdle(sessionID: "s")
        await submitted.bridge.flush()
        #expect(submitted.sent.count == 1)
    }

    @Test @MainActor func closeAndLeaseLossDropLateResults() async {
        let h = ReplyHarness()
        let hold = Hold()
        var opened = false
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            h.bridge.page = { _, _, _, _ in
                if !opened {
                    opened = true
                    ready.resume()
                }
                await hold.wait()
                return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "晚到")])
            }
            Task { @MainActor in
                let token = await h.reserve(sessionID: "s", isNew: true)
                await h.bridge.accept(token)
            }
        }
        h.bridge.invalidate()
        hold.release()
        await h.bridge.flush()
        #expect(h.sent.isEmpty)
        #expect(h.bridge.subscribedSessionIDs.isEmpty)

        let closed = ReplyHarness()
        closed.pages = { _, _, _ in
            livePage([liveRow(id: "old", sessionID: "s", role: "assistant", text: "旧回复")])
        }
        let token = await closed.reserve(sessionID: "s", userID: "u-new", isNew: false)
        await closed.bridge.accept(token)
        await closed.bridge.flush()
        #expect(closed.sent.isEmpty)
    }

    @Test @MainActor func allowsFalseAfterAwaitDoesNotSend() async {
        let h = ReplyHarness()
        let hold = Hold()
        var opened = false
        await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
            h.bridge.page = { _, _, _, _ in
                if !opened {
                    opened = true
                    ready.resume()
                }
                await hold.wait()
                return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "不该出")])
            }
            Task { @MainActor in
                let token = await h.reserve(sessionID: "s", isNew: true)
                await h.bridge.accept(token)
            }
        }
        h.open = false
        hold.release()
        await h.bridge.flush()
        #expect(h.sent.isEmpty)
    }

    @Test @MainActor func paginationGapAndMissingBaselineDoNotReplay() async {
        let paged = ReplyHarness()
        var calls = 0
        var befores: [String?] = []
        paged.pages = { _, before, _ in
            calls += 1
            befores.append(before)
            if calls == 1 { return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]) }
            if before == nil { return livePage([liveRow(id: "a-new", sessionID: "s", role: "assistant", text: "跨页新回复")], cursor: "c1") }
            return livePage([
                liveRow(id: "base", sessionID: "s", role: "user", text: "旧"),
                liveRow(id: "mid", sessionID: "s", role: "assistant", text: "中间工具", finish: "tool-calls"),
            ])
        }
        let token = await paged.reserve(sessionID: "s", isNew: false)
        await paged.bridge.accept(token)
        await paged.bridge.flush()
        #expect(paged.sent.count == 1)
        #expect(paged.sent[0].text.contains("跨页新回复"))
        #expect(!paged.sent[0].text.contains("中间工具"))
        #expect(befores.contains(nil))
        #expect(befores.contains("c1"))

        let gap = ReplyHarness()
        gap.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "缺口")], gaps: true) }
        let gapToken = await gap.reserve(sessionID: "s", isNew: true)
        await gap.bridge.accept(gapToken)
        await gap.bridge.flush()
        #expect(gap.sent.isEmpty)

        let missing = ReplyHarness()
        var missingCalls = 0
        missing.pages = { _, before, _ in
            missingCalls += 1
            if missingCalls == 1 { throw ReplyStubError() }
            let cursor = missingCalls < 6 ? "c\(missingCalls)" : nil
            return livePage([liveRow(id: "hist-\(missingCalls)", sessionID: "s", role: "assistant", text: "历史\(missingCalls)")], cursor: cursor)
        }
        let missingToken = await missing.reserve(sessionID: "s", userID: "u-new", isNew: false)
        await missing.bridge.accept(missingToken)
        await missing.bridge.flush()
        await missing.bridge.noteExplicitIdle(sessionID: "s")
        await missing.bridge.flush()
        #expect(missing.sent.isEmpty)
        #expect(missingCalls <= 6)
    }

    @Test @MainActor func opaqueCursorIsNotTrimmedAndGapBlocksBackfill() async {
        let gap = ReplyHarness()
        var gapBefores: [String?] = []
        var gapCalls = 0
        gap.pages = { _, before, directory in
            gapCalls += 1
            gapBefores.append(before)
            #expect(directory == " /work ")
            if gapCalls == 1 { return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]) }
            return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "缺口后")], cursor: "  c1  ", gaps: true)
        }
        let gapToken = await gap.reserve(sessionID: "s", directory: " /work ", isNew: false)
        await gap.bridge.accept(gapToken)
        await gap.bridge.flush()
        #expect(gap.sent.isEmpty)
        #expect(!gapBefores.contains("  c1  "))

        let spaced = ReplyHarness()
        var spacedBefores: [String?] = []
        var spacedCalls = 0
        spaced.pages = { _, before, _ in
            spacedCalls += 1
            spacedBefores.append(before)
            if spacedCalls == 1 { return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]) }
            if before == nil { return livePage([liveRow(id: "a-new", sessionID: "s", role: "assistant", text: "空白游标后")], cursor: "  c1  ") }
            #expect(before == "  c1  ")
            return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")])
        }
        let spacedToken = await spaced.reserve(sessionID: "s", isNew: false)
        await spaced.bridge.accept(spacedToken)
        await spaced.bridge.flush()
        #expect(spaced.sent.count == 1)
        #expect(spaced.sent[0].text.contains("空白游标后"))
        #expect(spacedBefores.contains("  c1  "))
    }

    @Test @MainActor func longTextStaysWithinUTF8Budget() async throws {
        let h = ReplyHarness()
        let body = "😀" + String(repeating: "测", count: 1800)
        h.pages = { _, _, _ in livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: body, agent: nil)]) }
        let token = await h.reserve(sessionID: "s", title: "很长的会话标题" + String(repeating: "题", count: 40), isNew: true)
        await h.bridge.accept(token)
        await h.bridge.flush()
        let text = try #require(h.sent.first?.text)
        #expect(text.utf8.count <= 2000)
        #expect(text.contains("来源会话："))
        #expect(text.contains("来源编号：s"))
        #expect(text.contains("正文已截断，详情见原会话"))
        #expect(text.contains("😀"))
        #expect(!text.contains("来源 agent："))
    }

    @Test @MainActor func continueKeepsUnsentReply() async {
        let h = ReplyHarness()
        var calls = 0
        h.pages = { _, _, _ in
            calls += 1
            return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "还没送出")])
        }
        h.bridge.submit = { text, eventID, owner in
            h.sent.append((text, eventID, owner))
            return false
        }
        let first = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(first)
        await h.bridge.flush()
        let seen = calls
        let second = await h.reserve(sessionID: "s", userID: "u2", isNew: false)
        #expect(calls == seen)
        h.bridge.submit = { text, eventID, owner in
            h.sent.append((text, eventID, owner))
            return true
        }
        await h.bridge.accept(second)
        await h.bridge.flush()
        #expect(h.sent.contains { $0.text.contains("还没送出") })
        #expect(h.bridge.subscribedSessionIDs == ["s"])
    }

    @Test @MainActor func completionUpdateFillsIdleWindowOnce() async {
        let h = ReplyHarness()
        var done = false
        h.pages = { _, _, _ in
            if done {
                return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "写完了", completed: 3, finish: "stop")])
            }
            return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "还在写", completed: nil, finish: nil)])
        }
        let token = await h.reserve(sessionID: "s", isNew: true)
        await h.bridge.accept(token)
        await h.bridge.noteExplicitIdle(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.isEmpty)
        done = true
        await h.bridge.noteMessageUpdated(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 1)
        #expect(h.sent[0].text.contains("写完了"))
        await h.bridge.noteMessageUpdated(sessionID: "s")
        await h.bridge.flush()
        #expect(h.sent.count == 1)
    }

    @Test @MainActor func duplicateStatusStillRoutesAndInfoSessionIDCompletes() async throws {
        let state = makeIsolatedAppState()
        let idle = try JSONDecoder().decode(SSEEvent.self, from: Data("""
        {"payload":{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"idle"}}}}
        """.utf8))
        await state.applySSEEventForTesting(idle)
        await state.applySSEEventForTesting(idle)
        #expect(state.carLiveReplies.routedIdleCount == 2)
        #expect(state.sessionStatuses["s1"]?.type == "idle")

        let completed = try JSONDecoder().decode(SSEEvent.self, from: Data("""
        {"payload":{"type":"message.updated","properties":{"info":{"id":"a1","sessionID":"s9","role":"assistant","time":{"created":1,"completed":2},"finish":"stop"}}}}
        """.utf8))
        let streaming = try JSONDecoder().decode(SSEEvent.self, from: Data("""
        {"payload":{"type":"message.updated","properties":{"info":{"id":"a1","sessionID":"s9","role":"assistant","time":{"created":1}}}}}
        """.utf8))
        await state.applySSEEventForTesting(completed)
        await state.applySSEEventForTesting(streaming)
        #expect(state.carLiveReplies.routedUpdateCount == 1)
    }

    @Test @MainActor func naturalEndDropsHungBaselineAndNewRunDoesNotCarryOldReply() async {
        let api = NaturalEndAPI()
        let transport = NaturalEndTransport()
        let audio = NaturalEndAudio()
        let controller = CarLiveController(transport: transport, audio: audio, closeGrace: 0.05)
        let state = makeIsolatedAppState(apiClient: api)
        state.carLive = controller
        state.isConnected = true
        state.aiBuilderToken = "token"
        state.aiBuilderBaseURL = "https://portal.example"
        let starting = Task { await state.startCarLive() }
        #expect(await replyWait { transport.opens == 1 })
        transport.links[0].emit(.started(sessionID: "run-a"))
        await starting.value
        #expect(controller.phase == .listening)
        let epoch = state.carLiveEpoch
        let owner = state.carLiveLease?.ownerToken
        let firstToken = state.carLiveLease?.transportToken
        await api.setRows([liveRow(id: "base", sessionID: "s1", role: "user", text: "旧边界")])
        let first = Task { await state.executeCarLiveTool(CarLiveFunctionCall(callID: "c1", name: CarLiveToolName.continueJob, arguments: #"{"sessionID":"s1","text":"继续"}"#, ownerToken: owner ?? "")) }
        #expect(await replyWait { await api.baselineStarted })
        transport.links[0].emit(.failed("connection_lost"))
        #expect(await replyWait { state.carLiveLease == nil && state.carLiveEpoch != epoch })
        #expect(state.isConnected)
        await api.releaseBaseline()
        let ended = await first.value
        #expect(await api.posts.isEmpty)
        #expect(state.carLiveReplies.subscribedSessionIDs.isEmpty)
        #expect(!ended.output.contains("accepted"))
        #expect(await replyWait { await api.retired == [firstToken ?? 0] })
        #expect(await api.abortCount == 0)

        await api.setRows([
            liveRow(id: "base", sessionID: "s1", role: "user", text: "旧边界"),
            liveRow(id: "old", sessionID: "s1", role: "assistant", text: "旧回复"),
        ])
        let restart = Task { await state.startCarLive() }
        #expect(await replyWait { transport.opens == 2 })
        transport.links[1].emit(.started(sessionID: "run-b"))
        await restart.value
        #expect(controller.phase == .listening)
        let nextOwner = state.carLiveLease?.ownerToken ?? ""
        #expect(nextOwner != owner)
        let continued = await state.executeCarLiveTool(CarLiveFunctionCall(callID: "c2", name: CarLiveToolName.continueJob, arguments: #"{"sessionID":"s1","text":"再继续"}"#, ownerToken: nextOwner))
        #expect(continued.output.contains("accepted"))
        #expect(await api.posts.count == 1)
        await state.carLiveReplies.flush()
        #expect(transport.links[1].commentary.isEmpty)
        await api.setRows([
            liveRow(id: "base", sessionID: "s1", role: "user", text: "旧边界"),
            liveRow(id: "old", sessionID: "s1", role: "assistant", text: "旧回复"),
            liveRow(id: "new", sessionID: "s1", role: "assistant", text: "新回复"),
        ])
        state.carLiveReplies.noteExplicitIdle(sessionID: "s1")
        await state.carLiveReplies.flush()
        let spoken = transport.links[1].commentary.joined(separator: "\n")
        #expect(spoken.contains("新回复"))
        #expect(!spoken.contains("旧回复"))
        await state.stopCarLive()
    }

    @Test @MainActor func idleEmptyBodyWaitsForTerminalUpdateOnly() async throws {
        for kind in ["user", "empty"] {
            let state = makeIsolatedAppState()
            var calls = 0
            var sent: [String] = []
            state.carLiveReplies.allows = { _ in true }
            state.carLiveReplies.sleep = { _ in }
            state.carLiveReplies.status = { _, _ in ["s": SessionStatus(type: "busy", attempt: nil, message: nil, next: nil)] }
            state.carLiveReplies.page = { _, _, _, _ in
                calls += 1
                if calls <= 3 {
                    if kind == "user" {
                        return livePage([liveRow(id: "u1", sessionID: "s", role: "user", text: "问")])
                    }
                    return livePage([liveRow(id: "a1", sessionID: "s", role: "assistant", text: "", completed: nil, finish: nil)])
                }
                var rows = [liveRow(id: "a1", sessionID: "s", role: "assistant", text: "写完了", completed: 3, finish: "stop")]
                if kind == "user" {
                    rows.insert(liveRow(id: "u1", sessionID: "s", role: "user", text: "问"), at: 0)
                }
                return livePage(rows)
            }
            state.carLiveReplies.submit = { text, _, _ in
                sent.append(text)
                return true
            }
            let token = UUID().uuidString
            await state.carLiveReplies.reserve(CarLiveReplyReservation(token: token, sessionID: "s", directory: "/work", userMessageID: "u", title: "路线", isNewSession: true), lease: CarLiveLease(hostID: UUID(), generation: 1, contextKey: "ctx", epoch: 1, ownerToken: "owner", transportToken: 1))
            await state.carLiveReplies.accept(token)
            await state.carLiveReplies.flush()
            #expect(calls == 0)
            await state.carLiveReplies.noteExplicitIdle(sessionID: "s")
            await state.carLiveReplies.flush()
            #expect(calls == 3)
            #expect(sent.isEmpty)
            let before = calls
            await state.applySSEEventForTesting(try sseEvent(#"{"payload":{"type":"message.updated","properties":{"info":{"id":"a1","sessionID":"s","role":"assistant","time":{"created":1}}}}}"#))
            await state.carLiveReplies.flush()
            #expect(calls == before)
            #expect(state.carLiveReplies.routedUpdateCount == 0)
            await state.applySSEEventForTesting(try sseEvent(#"{"payload":{"type":"message.updated","properties":{"info":{"id":"a1","sessionID":"s","role":"assistant","time":{"created":1,"completed":2},"finish":"stop"}}}}"#))
            await state.carLiveReplies.flush()
            #expect(sent.count == 1)
            #expect(sent[0].contains("写完了"))
            let after = calls
            await state.applySSEEventForTesting(try sseEvent(#"{"payload":{"type":"message.updated","properties":{"info":{"id":"a1","sessionID":"s","role":"assistant","time":{"created":1,"completed":2},"finish":"stop"}}}}"#))
            await state.carLiveReplies.flush()
            #expect(sent.count == 1)
            #expect(calls == after)
        }
    }

    @Test @MainActor func inFlightTerminalDirtyTailDoesNotReopenSatisfiedWindow() async {
        for mode in ["sleep", "page"] {
            let h = ReplyHarness()
            let hold = Hold()
            var pages = 0
            var filled = false
            var later = false
            h.statuses = { _ in ["s": SessionStatus(type: "busy", attempt: nil, message: nil, next: nil)] }
            let rows = {
                if later {
                    return livePage([
                        liveRow(id: "u1", sessionID: "s", role: "user", text: "问"),
                        liveRow(id: "a1", sessionID: "s", role: "assistant", text: "写完了", completed: 3, finish: "stop"),
                        liveRow(id: "b1", sessionID: "s", role: "assistant", text: "后到", completed: 4, finish: "stop"),
                    ])
                }
                if filled {
                    return livePage([
                        liveRow(id: "u1", sessionID: "s", role: "user", text: "问"),
                        liveRow(id: "a1", sessionID: "s", role: "assistant", text: "写完了", completed: 3, finish: "stop"),
                    ])
                }
                return livePage([liveRow(id: "u1", sessionID: "s", role: "user", text: "问")])
            }
            let token = await h.reserve(sessionID: "s", isNew: true)
            await h.bridge.accept(token)
            await h.bridge.flush()
            #expect(pages == 0)
            await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
                if mode == "page" {
                    h.bridge.page = { _, _, _, _ in
                        pages += 1
                        if pages == 1 {
                            ready.resume()
                            await hold.wait()
                        }
                        return rows()
                    }
                } else {
                    h.bridge.page = { _, _, _, _ in
                        pages += 1
                        return rows()
                    }
                    var sleeps = 0
                    h.bridge.sleep = { _ in
                        sleeps += 1
                        if sleeps == 1 {
                            ready.resume()
                            await hold.wait()
                        }
                    }
                }
                Task { @MainActor in
                    await h.bridge.noteExplicitIdle(sessionID: "s")
                }
            }
            filled = true
            await h.bridge.noteMessageUpdated(sessionID: "s")
            hold.release()
            await h.bridge.flush()
            #expect(h.sent.count == 1)
            #expect(h.sent[0].text.contains("写完了"))
            let after = pages
            await h.bridge.noteMessageUpdated(sessionID: "s")
            await h.bridge.flush()
            #expect(h.sent.count == 1)
            #expect(pages == after)
            later = true
            await h.bridge.noteExplicitIdle(sessionID: "s")
            await h.bridge.flush()
            #expect(h.sent.count == 2)
            #expect(h.sent[1].text.contains("后到"))
            #expect(pages > after)
        }
    }

    @Test @MainActor func boundaryAdvancesAcrossSmallRoundsAndDoesNotSkipUnsent() async {
        let h = ReplyHarness()
        var rows = [liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]
        var seq = 0
        h.pages = { _, before, _ in
            let end: Int
            if let before, let index = rows.firstIndex(where: { $0.info.id == before }) {
                end = index
            } else if before != nil {
                end = 0
            } else {
                end = rows.count
            }
            let start = max(0, end - 100)
            let cursor = start > 0 ? rows[start].info.id : nil
            return livePage(Array(rows[start..<end]), cursor: cursor)
        }
        func add(_ role: String, _ text: String, done: Bool = true) -> String {
            seq += 1
            let id = "\(role.prefix(1))\(seq)"
            rows.append(liveRow(id: id, sessionID: "s", role: role, text: text, completed: done ? 2 : nil, finish: done ? "stop" : nil))
            return id
        }
        let token = await h.reserve(sessionID: "s", isNew: false)
        await h.bridge.accept(token)
        await h.bridge.flush()
        for round in 0..<13 {
            for _ in 0..<40 { _ = add("user", "垫") }
            _ = add("assistant", "轮次\(round)")
            await h.bridge.noteExplicitIdle(sessionID: "s")
            await h.bridge.flush()
            #expect(h.sent.contains { $0.text.contains("轮次\(round)") })
        }
        #expect(rows.count > 500)
        #expect(h.sent.filter { $0.text.contains("轮次") }.count == 13)

        let blocked = ReplyHarness()
        var blockedReads = 0
        var blockedRows = [
            liveRow(id: "base", sessionID: "s", role: "user", text: "旧"),
            liveRow(id: "hold", sessionID: "s", role: "assistant", text: "未完成", completed: nil, finish: nil),
            liveRow(id: "later", sessionID: "s", role: "assistant", text: "可先送"),
        ]
        blocked.pages = { _, _, _ in
            blockedReads += 1
            if blockedReads == 1 { return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]) }
            return livePage(blockedRows)
        }
        let blockedToken = await blocked.reserve(sessionID: "s", isNew: false)
        await blocked.bridge.accept(blockedToken)
        await blocked.bridge.flush()
        #expect(blocked.sent.contains { $0.text.contains("可先送") })
        #expect(!blocked.sent.contains { $0.text.contains("未完成") })
        blockedRows[1] = liveRow(id: "hold", sessionID: "s", role: "assistant", text: "未完成", completed: 4, finish: "stop")
        await blocked.bridge.noteExplicitIdle(sessionID: "s")
        await blocked.bridge.flush()
        #expect(blocked.sent.contains { $0.text.contains("未完成") })

        let failed = ReplyHarness()
        failed.bridge.submit = { text, eventID, owner in
            failed.sent.append((text, eventID, owner))
            return !text.contains("失败发送")
        }
        var failedReads = 0
        var failedRows = [
            liveRow(id: "base", sessionID: "s", role: "user", text: "旧"),
            liveRow(id: "bad", sessionID: "s", role: "assistant", text: "失败发送"),
        ]
        failed.pages = { _, _, _ in
            failedReads += 1
            if failedReads == 1 { return livePage([liveRow(id: "base", sessionID: "s", role: "user", text: "旧")]) }
            return livePage(failedRows)
        }
        let failedToken = await failed.reserve(sessionID: "s", isNew: false)
        await failed.bridge.accept(failedToken)
        await failed.bridge.flush()
        #expect(failed.sent.filter { $0.text.contains("失败发送") }.count == 1)
        failedRows.append(liveRow(id: "after", sessionID: "s", role: "assistant", text: "失败后的新回复"))
        let continued = await failed.reserve(sessionID: "s", userID: "u2", isNew: false)
        await failed.bridge.accept(continued)
        await failed.bridge.flush()
        #expect(failed.sent.filter { $0.text.contains("失败发送") }.count == 2)
        #expect(failed.sent.contains { $0.text.contains("失败后的新回复") })
    }
}

@MainActor
final class ReplyHarness {
    let bridge = CarLiveReplyBridge()
    var sent: [(text: String, eventID: String, owner: String)] = []
    var pages: (String, String?, String?) throws -> CarLiveMessagePage = { _, _, _ in
        CarLiveMessagePage(messages: [], hasOlder: false, requestedLimit: 100)
    }
    var statuses: (String?) throws -> [String: SessionStatus] = { _ in [:] }
    var open = true
    var revisionValue: UInt64 = 1
    var directories: [String?] = []
    let lease = CarLiveLease(hostID: UUID(), generation: 1, contextKey: "ctx", epoch: 1, ownerToken: "owner", transportToken: 9)

    init() {
        bridge.allows = { [weak self] _ in self?.open ?? false }
        bridge.page = { [weak self] id, before, directory, _ in
            guard let self else { throw CancellationError() }
            return try self.pages(id, before, directory)
        }
        bridge.status = { [weak self] directory, _ in
            self?.directories.append(directory)
            guard let self else { throw CancellationError() }
            return try self.statuses(directory)
        }
        bridge.submit = { [weak self] text, eventID, owner in
            self?.sent.append((text, eventID, owner))
            return true
        }
        bridge.revision = { [weak self] in self?.revisionValue ?? 0 }
        bridge.sleep = { _ in }
    }

    func reserve(sessionID: String, directory: String = "/work", userID: String = "u", title: String = "路线", isNew: Bool) async -> String {
        let token = UUID().uuidString
        await bridge.reserve(
            CarLiveReplyReservation(token: token, sessionID: sessionID, directory: directory, userMessageID: userID, title: title, isNewSession: isNew),
            lease: lease
        )
        return token
    }
}

final class Hold {
    private var resume: (() -> Void)?

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            resume = { cont.resume() }
        }
    }

    func release() {
        resume?()
        resume = nil
    }
}

private struct ReplyStubError: Error {}

private func livePage(_ messages: [MessageWithParts], cursor: String? = nil, gaps: Bool = false) -> CarLiveMessagePage {
    CarLiveMessagePage(messages: messages, hasOlder: cursor != nil, requestedLimit: 100, nextCursor: cursor, hasDecodeGaps: gaps)
}

private func liveRow(
    id: String,
    sessionID: String,
    role: String,
    parentID: String? = nil,
    text: String,
    completed: Int? = 2,
    finish: String? = "stop",
    agent: String? = nil
) -> MessageWithParts {
    MessageWithParts(
        info: Message(
            id: id,
            sessionID: sessionID,
            role: role,
            parentID: parentID,
            providerID: "openai",
            modelID: "gpt-6.1-sol",
            model: nil,
            error: nil,
            time: .init(created: 1, completed: completed),
            finish: finish,
            tokens: nil,
            cost: nil,
            agent: agent
        ),
        parts: [Part(id: "p-\(id)", messageID: id, sessionID: sessionID, type: "text", text: text, tool: nil, callID: nil, state: nil, metadata: nil, files: nil)]
    )
}

private func sseEvent(_ json: String) throws -> SSEEvent {
    try JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8))
}

private func replyWait(_ ready: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<50 {
        if await ready() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await ready()
}

private actor NaturalEndAPI: APIClientProtocol {
    private var rows: [MessageWithParts] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var entered = false
    private(set) var posts: [String] = []
    private(set) var retired: [UInt64] = []
    private(set) var abortCount = 0
    private var issued: UInt64 = 0
    private var active: UInt64 = 0

    var baselineStarted: Bool { entered }

    func setRows(_ rows: [MessageWithParts]) { self.rows = rows }

    func releaseBaseline() {
        gate?.resume()
        gate = nil
    }

    func configure(baseURL: String, username: String?, password: String?) {}
    func health() async throws -> HealthResponse { fatalError("unused") }
    func projects() async throws -> [Project] { fatalError("unused") }
    func projectCurrent() async throws -> Project? { fatalError("unused") }
    func sessions(directory: String?, limit: Int) async throws -> [Session] { fatalError("unused") }
    func session(sessionID: String) async throws -> Session { fatalError("unused") }
    func createSession(title: String?, directory: String?) async throws -> Session { fatalError("unused") }
    func updateSession(sessionID: String, title: String) async throws -> Session { fatalError("unused") }
    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session { fatalError("unused") }
    func deleteSession(sessionID: String) async throws { fatalError("unused") }
    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { fatalError("unused") }
    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws { fatalError("unused") }
    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts { fatalError("unused") }
    func abort(sessionID: String) async throws { abortCount += 1 }
    func sessionStatus() async throws -> [String: SessionStatus] { ["s1": SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { fatalError("unused") }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws { fatalError("unused") }
    func pendingQuestions() async throws -> [QuestionRequest] { fatalError("unused") }
    func replyQuestion(requestID: String, answers: [[String]]) async throws { fatalError("unused") }
    func rejectQuestion(requestID: String) async throws { fatalError("unused") }
    func providers() async throws -> ProvidersResponse { fatalError("unused") }
    func providerRegistry() async throws -> ProviderRegistryResponse { fatalError("unused") }
    func agents() async throws -> [AgentInfo] { fatalError("unused") }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] { fatalError("unused") }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { fatalError("unused") }
    func fileList(path: String, directory: String?) async throws -> [FileNode] { fatalError("unused") }
    func fileContent(path: String, directory: String?) async throws -> FileContent { fatalError("unused") }
    func findFile(query: String, limit: Int) async throws -> [String] { fatalError("unused") }
    func fileStatus() async throws -> [FileStatusEntry] { fatalError("unused") }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session { fatalError("unused") }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session { fatalError("unused") }

    func armLiveTransport() -> UInt64 {
        issued &+= 1
        active = issued
        return issued
    }

    func retireLiveTransport(token: UInt64) {
        retired.append(token)
        if active == token { active = 0 }
    }

    func sessionForLive(sessionID: String, directory: String?, transportToken: UInt64) async throws -> Session {
        naturalSession(sessionID)
    }

    func messagePageForLive(sessionID: String, limit: Int, before: String?, directory: String?, transportToken: UInt64) async throws -> CarLiveMessagePage {
        if !entered {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                gate = cont
                entered = true
            }
        }
        return CarLiveMessagePage(messages: rows, hasOlder: false, requestedLimit: limit, nextCursor: before, hasDecodeGaps: false)
    }

    func promptAsyncInherited(sessionID: String, messageID: String, text: String, agent: String?, variant: String?, directory: String?, transportToken: UInt64) async throws {
        posts.append(text)
    }

    func abortForLive(sessionID: String, transportToken: UInt64) async throws { abortCount += 1 }

    func sessionStatusForLive(directory: String?, transportToken: UInt64) async throws -> [String: SessionStatus] {
        ["s1": SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)]
    }
}

private func naturalSession(_ id: String) -> Session {
    Session(id: id, slug: id, projectID: "p", directory: "/work", parentID: nil, title: "路线", version: "1", time: .init(created: 1, updated: 2, archived: nil), share: nil, summary: nil)
}

private final class NaturalEndTransport: CarLiveTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var openCount = 0
    private var opened: [NaturalEndLink] = []

    func open(_ configuration: CarLiveConfiguration) async throws -> any CarLiveLink {
        let link = NaturalEndLink()
        lock.withLock {
            openCount += 1
            opened.append(link)
        }
        return link
    }

    var opens: Int { lock.withLock { openCount } }
    var links: [NaturalEndLink] { lock.withLock { opened } }
}

private final class NaturalEndLink: CarLiveLink, @unchecked Sendable {
    let events: AsyncStream<CarLiveServerEvent>
    private let continuation: AsyncStream<CarLiveServerEvent>.Continuation
    private let lock = NSLock()
    private var lines: [String] = []

    init() {
        var captured: AsyncStream<CarLiveServerEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    func emit(_ event: CarLiveServerEvent) { continuation.yield(event) }

    func send(_ event: CarLiveClientEvent) async throws {}

    func send(_ event: CarLiveClientEvent, eventID: String) async throws {
        if case .commentary(let text) = event {
            lock.withLock { lines.append(text) }
        }
    }

    func ping() async throws {}

    func close() async { continuation.finish() }

    var commentary: [String] { lock.withLock { lines } }
}

private final class NaturalEndAudio: CarLiveAudioEngine, @unchecked Sendable {
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
