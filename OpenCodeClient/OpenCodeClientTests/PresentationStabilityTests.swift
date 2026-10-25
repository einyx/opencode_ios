import Foundation
import Testing
@testable import OpenCodeClient

struct PresentationStabilityTests {
    private static let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XGZ0AAAAASUVORK5CYII="

    @Test func assistantGroupIDStaysOnFirstMessageWhenStepAppended() throws {
        let user = try row(id: "u1", role: "user", parts: [part(id: "ut", messageID: "u1", type: "text", text: "ask")])
        let first = try row(id: "m1", parts: [part(id: "t1", messageID: "m1", type: "tool", tool: "bash")])
        let second = try row(id: "m2", parts: [part(id: "t2", messageID: "m2", type: "tool", tool: "bash")])
        let before = MessageGroupItem.grouped([user, first])
        let after = MessageGroupItem.grouped([user, first, second])

        #expect(before.map(\.id) == ["user-u1", "assistant-m1"])
        #expect(after.map(\.id) == before.map(\.id))
        #expect(after[1].messageIDs == ["m1", "m2"])
        #expect(!after[1].id.contains("m2"))
        #expect(AssistantTurnPresentation(messages: after[1].messages).parts.map(\.id) == ["t1", "t2"])
    }

    @Test func textPartStillEndsTheBatch() throws {
        let first = try row(id: "m1", parts: [part(id: "t1", messageID: "m1", type: "tool", tool: "bash")])
        let answer = try row(
            id: "m2",
            speech: "hidden because text exists",
            parts: [part(id: "p2", messageID: "m2", type: "text", text: "done")]
        )
        let later = try row(id: "m3", parts: [part(id: "t3", messageID: "m3", type: "tool", tool: "bash")])
        let groups = MessageGroupItem.grouped([first, answer, later])

        #expect(groups.map(\.id) == ["assistant-m1", "assistant-m3"])
        #expect(groups[0].messageIDs == ["m1", "m2"])
        #expect(AssistantTurnPresentation(messages: groups[0].messages).parts.map(\.id) == ["t1", "p2"])
        #expect(AssistantTurnPresentation(messages: groups[0].messages).speeches.isEmpty)
    }

    @Test func toolCallsTileIDStaysOnFirstPartWhenToolAppended() {
        let first = part(id: "p1", messageID: "m1", type: "tool", tool: "bash")
        let second = part(id: "p2", messageID: "m1", type: "tool", tool: "bash")
        let thinking = part(id: "r1", messageID: "m1", type: "reasoning", text: "next")
        let third = part(id: "p3", messageID: "m1", type: "tool", tool: "bash")
        let fourth = part(id: "p4", messageID: "m1", type: "tool", tool: "bash")

        let before = MessageRowView.cardGridTiles(for: [first])
        let after = MessageRowView.cardGridTiles(for: [first, second])
        // Every tool call is its own row now, so appending one appends a row
        // and never rewrites the identity of the rows before it.
        #expect(tileIDs(before) == ["tile-toolcall-p1"])
        #expect(tileIDs(after) == ["tile-toolcall-p1", "tile-toolcall-p2"])
        #expect(!tileIDs(after)[0].contains("p2"))

        let split = MessageRowView.cardGridTiles(for: [first, thinking, third])
        let grown = MessageRowView.cardGridTiles(for: [first, thinking, third, fourth])
        #expect(tileIDs(split) == ["tile-toolcall-p1", "tile-thinking-r1", "tile-toolcall-p3"])
        #expect(tileIDs(grown) == ["tile-toolcall-p1", "tile-thinking-r1", "tile-toolcall-p3", "tile-toolcall-p4"])
    }

    @Test func laterStepErrorSpeechAndFooterStayWithTheirMessage() throws {
        let tool = try partWithToolTime(id: "t1", messageID: "m1")
        let first = try row(
            id: "m1",
            model: Message.ModelInfo(providerID: "p", modelID: "step"),
            error: "first failed",
            parts: [tool]
        )
        let second = try decodedRow(
            """
            {
              "id": "m2",
              "sessionID": "s",
              "role": "assistant",
              "model": { "providerID": "p", "modelID": "answer" },
              "time": { "created": 0, "completed": 10000 },
              "tokens": { "input": 0, "output": 100, "reasoning": 0, "total": 100 },
              "error": { "name": "APIError", "data": { "message": "later failed" } }
            }
            """,
            speech: "The garage door is closed.",
            parts: []
        )
        let bare = try row(id: "m3", parts: [part(id: "t3", messageID: "m3", type: "tool", tool: "bash")])
        let speechOnly = try row(id: "m4", speech: "later speech", parts: [])
        let presentation = AssistantTurnPresentation(messages: [first, second])
        let speechTurn = AssistantTurnPresentation(messages: [first, speechOnly])
        let noModel = AssistantTurnPresentation(messages: [first, bare])
        let footer = try #require(presentation.footer)
        let speechFooter = try #require(speechTurn.footer)

        #expect(presentation.errors.map(\.messageID) == ["m1", "m2"])
        #expect(presentation.errors.map(\.text) == ["first failed", "later failed"])
        #expect(presentation.speeches.map(\.messageID) == ["m2"])
        #expect(presentation.speeches.map(\.text) == ["The garage door is closed."])
        #expect(footer.messageID == "m2")
        #expect(footer.model?.modelID == "answer")
        #expect(footer.generalThroughput == "10 t/s")
        #expect(
            footer.generalThroughput
                != second.info.throughputLabelExcludingToolSeconds(first.toolRunSeconds + second.toolRunSeconds)
        )
        #expect(speechFooter.messageID == "m4")
        #expect(speechFooter.model == nil)
        #expect(speechTurn.speeches.map(\.text) == ["later speech"])
        #expect(speechTurn.errors.map(\.text) == ["first failed"])
        #expect(noModel.footer == nil)
        #expect(noModel.errors.map(\.text) == ["first failed"])
    }

    @Test func codeExampleImageSyntaxIsNotFetchedOrRewritten() async {
        let markdown = [
            "![real](assets/real.png)",
            "",
            "\\![escaped](assets/escaped.png)",
            "\\\\![kept](assets/kept.png)",
            "",
            "`![inline](assets/inline.png)`",
            "``![double](assets/double.png)``",
            "",
            "```markdown",
            "![fenced](assets/fenced.png)",
            "```",
            "",
            "````",
            "![wide](assets/wide.png)",
            "```",
            "still fenced",
            "````",
            "",
            "~~~",
            "![tilde](assets/tilde.png)",
            "~~~",
            "",
            "> ```",
            "> ![quoted-fence](assets/quoted-fence.png)",
            "> ```",
            "",
            "> > ```",
            "> > ![nested-fence](assets/nested-fence.png)",
            "> > ```",
            "",
            "> ```",
            "![dropped](assets/dropped.png)",
            "",
            "> ![quoted-real](assets/quoted-real.png)",
            "",
            "`orphan ![still-real](assets/still-real.png)",
            "",
            "```",
            "![unclosed](assets/unclosed.png)",
        ].joined(separator: "\n")

        var fetches: [String] = []
        let resolved = await resolve(markdown, fetches: &fetches)
        var expected = markdown
        for name in ["real", "kept", "dropped", "quoted-real", "still-real"] {
            expected = expected.replacingOccurrences(
                of: "![\(name)](assets/\(name).png)",
                with: "![\(name)](data:image/png;base64,\(Self.png))"
            )
        }

        #expect(Set(fetches) == [
            "assets/real.png",
            "assets/kept.png",
            "assets/dropped.png",
            "assets/quoted-real.png",
            "assets/still-real.png",
        ])
        #expect(fetches.count == 5)
        #expect(resolved == expected)
    }

    @Test func indentedCodeBlockStaysVerbatimAndFollowingImageResolves() async {
        let markdown = [
            "Example:",
            "",
            "    ![chart](assets/chart.png)",
            "",
            "![real](assets/real.png)",
        ].joined(separator: "\n")
        var fetches: [String] = []
        let resolved = await resolve(markdown, fetches: &fetches)
        #expect(fetches == ["assets/real.png"])
        #expect(resolved == markdown.replacingOccurrences(
            of: "![real](assets/real.png)",
            with: "![real](data:image/png;base64,\(Self.png))"
        ))
        #expect(resolved.contains("    ![chart](assets/chart.png)"))

        let only = "    ![chart](assets/chart.png)\n"
        var none: [String] = []
        let kept = await resolve(only, fetches: &none)
        #expect(none.isEmpty)
        #expect(kept == only)

        let continuation = [
            "hello",
            "    ![real](assets/real.png)",
        ].joined(separator: "\n")
        var continued: [String] = []
        let continuedResolved = await resolve(continuation, fetches: &continued)
        #expect(continued == ["assets/real.png"])
        #expect(continuedResolved.contains("data:image/png;base64,"))
    }

    @Test func extraQuoteInsideFenceDoesNotCloseIt() async {
        let top = [
            "```markdown",
            "> ```",
            "![sample](assets/chart.png)",
            "```",
        ].joined(separator: "\n")
        var topFetches: [String] = []
        let topResolved = await resolve(top, fetches: &topFetches)
        #expect(topFetches.isEmpty)
        #expect(topResolved == top)

        let quoted = [
            "> ```markdown",
            "> > ```",
            "> ![sample](assets/chart.png)",
            "> ```",
        ].joined(separator: "\n")
        var quotedFetches: [String] = []
        let quotedResolved = await resolve(quoted, fetches: &quotedFetches)
        #expect(quotedFetches.isEmpty)
        #expect(quotedResolved == quoted)

        let dropped = [
            "> ```",
            "![dropped](assets/dropped.png)",
        ].joined(separator: "\n")
        var droppedFetches: [String] = []
        let droppedResolved = await resolve(dropped, fetches: &droppedFetches)
        #expect(droppedFetches == ["assets/dropped.png"])
        #expect(droppedResolved == dropped.replacingOccurrences(
            of: "![dropped](assets/dropped.png)",
            with: "![dropped](data:image/png;base64,\(Self.png))"
        ))
    }

    @Test func escapedBacktickDoesNotOpenInlineCode() async {
        let odd = "\\` ![real](assets/real.png) \\`"
        var oddFetches: [String] = []
        let oddResolved = await resolve(odd, fetches: &oddFetches)
        #expect(oddFetches == ["assets/real.png"])
        #expect(oddResolved == odd.replacingOccurrences(
            of: "![real](assets/real.png)",
            with: "![real](data:image/png;base64,\(Self.png))"
        ))

        let even = "\\\\`![even](assets/even.png)`"
        var evenFetches: [String] = []
        let evenResolved = await resolve(even, fetches: &evenFetches)
        #expect(evenFetches.isEmpty)
        #expect(evenResolved == even)

        let closer = "`![inside](assets/inside.png)\\`\n![after](assets/after.png)"
        var closerFetches: [String] = []
        let closerResolved = await resolve(closer, fetches: &closerFetches)
        #expect(closerFetches == ["assets/after.png"])
        #expect(closerResolved.hasPrefix("`![inside](assets/inside.png)\\`"))
        #expect(closerResolved.contains("![after](data:image/png;base64,\(Self.png))"))
    }

    private func resolve(_ markdown: String, fetches: inout [String]) async -> String {
        await MarkdownImageResolver.resolveImages(
            in: markdown,
            workspaceDirectory: "/workspace",
            fetchContent: { path in
                fetches.append(path)
                return FileContent(type: "text", content: Self.png)
            }
        )
    }

    private func tileIDs(_ tiles: [MessageRowView.CardGridTile]) -> [String] {
        tiles.map(\.id)
    }

    private func part(
        id: String,
        messageID: String,
        type: String,
        tool: String? = nil,
        text: String? = nil
    ) -> Part {
        Part(
            id: id,
            messageID: messageID,
            sessionID: "s",
            type: type,
            text: text,
            tool: tool,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )
    }

    private func partWithToolTime(id: String, messageID: String) throws -> Part {
        let json = """
        {"id":"\(id)","messageID":"\(messageID)","sessionID":"s","type":"tool","tool":"bash","state":{"status":"completed","time":{"start":0,"end":9000}}}
        """
        return try JSONDecoder().decode(Part.self, from: Data(json.utf8))
    }

    private func row(
        id: String,
        role: String = "assistant",
        model: Message.ModelInfo? = nil,
        error: String? = nil,
        speech: String? = nil,
        parts: [Part]
    ) throws -> MessageWithParts {
        let structured = try speech.map { text in
            try WireJSON(encoding: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: text,
                confirmation: nil,
                clientActions: []
            ))
        }
        let info = Message(
            id: id,
            sessionID: "s",
            role: role,
            parentID: nil,
            providerID: nil,
            modelID: nil,
            model: model,
            error: error.map { Message.MessageError(name: "Error", data: ["message": AnyCodable($0)]) },
            time: .init(created: 1, completed: 2),
            finish: nil,
            tokens: nil,
            cost: nil,
            structured: structured
        )
        return MessageWithParts(info: info, parts: parts)
    }

    private func decodedRow(_ json: String, speech: String?, parts: [Part]) throws -> MessageWithParts {
        var info = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        if let speech {
            info = Message(
                id: info.id,
                sessionID: info.sessionID,
                role: info.role,
                parentID: info.parentID,
                providerID: info.providerID,
                modelID: info.modelID,
                model: info.model,
                error: info.error,
                time: info.time,
                finish: info.finish,
                tokens: info.tokens,
                cost: info.cost,
                structured: try WireJSON(encoding: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: speech,
                    confirmation: nil,
                    clientActions: []
                ))
            )
        }
        return MessageWithParts(info: info, parts: parts)
    }
}
