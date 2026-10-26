import Foundation
import Testing
@testable import OpenCodeClient

/// The session changes & diff surface: a "N files changed" card in chat, a diff
/// viewer, and the file state that refreshes when the agent writes.
///
/// Spec: `docs/features/file_changes_surface/design.md`
/// Plan: `docs/features/file_changes_surface/plan.md`
struct FileChangesSurfaceTests {

    // MARK: - Task 1 · V2 changed-file signal

    @Test func v2AssistantMessageWithSnapshotFilesYieldsOnePatchPart() throws {
        let messages = try V2Mapper.messages(from: Data(#"""
        {"data":[
          {"id":"msg_1","type":"user","text":"go","time":{"created":1}},
          {"id":"msg_2","type":"assistant","agent":"build","model":{"id":"claude","providerID":"anthropic"},"time":{"created":2},
           "content":[{"type":"text","text":"done"}],
           "snapshot":{"start":"snap_a","end":"snap_b","files":["model/Parser.swift","model/ParserTests.swift"]}}
        ]}
        """#.utf8), sessionID: "ses_1")

        let assistant = try #require(messages.last)
        let patchParts = assistant.parts.filter(\.isPatch)
        #expect(patchParts.count == 1)
        #expect(patchParts.first?.files?.map(\.path) == ["model/Parser.swift", "model/ParserTests.swift"])
        #expect(patchParts.first?.id == "msg_2-patch-0")
        #expect(assistant.info.parentID == "msg_1")
    }

    @Test func v2AssistantMessageWithoutSnapshotHasNoPatchPart() throws {
        let messages = try V2Mapper.messages(from: Data(#"""
        {"data":[{"id":"msg_1","type":"assistant","agent":"build","model":{"id":"claude","providerID":"anthropic"},
                  "time":{"created":1},"content":[{"type":"text","text":"done"}]}]}
        """#.utf8), sessionID: "ses_1")

        let assistant = try #require(messages.first)
        #expect(assistant.parts.filter(\.isPatch).isEmpty)
    }

    @Test func v2AssistantMessageWithEmptySnapshotFilesHasNoPatchPart() throws {
        let messages = try V2Mapper.messages(from: Data(#"""
        {"data":[{"id":"msg_1","type":"assistant","agent":"build","model":{"id":"claude","providerID":"anthropic"},
                  "time":{"created":1},"content":[{"type":"text","text":"done"}],
                  "snapshot":{"start":"snap_a","end":"snap_b","files":[]}}]}
        """#.utf8), sessionID: "ses_1")

        let assistant = try #require(messages.first)
        #expect(assistant.parts.filter(\.isPatch).isEmpty)
    }

    // MARK: - Task 1 · diff payload

    @Test func v2DiffKeepsTheServerPatchText() throws {
        let diffs = try V2Mapper.diff(from: Data(#"""
        {"data":[{"file":"a.swift","patch":"@@ -1 +1 @@\n-old\n+new","additions":1,"deletions":1,"status":"modified"}]}
        """#.utf8))
        let diff = try #require(diffs.first)
        #expect(diff.patchText == "@@ -1 +1 @@\n-old\n+new")
        #expect(diff.after == "@@ -1 +1 @@\n-old\n+new")
    }

    @Test func v1DiffHasNoPatchText() throws {
        let diffs = try JSONDecoder().decode([FileDiff].self, from: Data(#"""
        [{"file":"a.swift","before":"old","after":"new","additions":1,"deletions":1,"status":"modified"}]
        """#.utf8))
        #expect(diffs.first?.patchText == nil)
        #expect(diffs.first?.before == "old")
    }

    // MARK: - Task 2 · classification

    private func makePart(id: String = "p1", type: String, tool: String? = nil) throws -> Part {
        var obj: [String: Any] = [
            "id": id,
            "messageID": "m1",
            "sessionID": "s1",
            "type": type,
        ]
        if let tool { obj["tool"] = tool }
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(Part.self, from: data)
    }

    @Test func patchPartIsAChangePartNotAFileOperation() throws {
        let part = try makePart(type: "patch")
        #expect(ToolCardClassifier.isChangePart(part))
        #expect(!ToolCardClassifier.isFileOperation(part))
    }

    @Test func writeToolsAreWriteOperationsAndReadsAreNot() throws {
        for tool in ["write_file", "edit_file", "apply_patch", "write", "edit", "patch"] {
            let part = try makePart(type: "tool", tool: tool)
            #expect(ToolCardClassifier.isWriteOperation(part), "\(tool) should be a write operation")
        }
        for tool in ["read_file", "read", "bash", "grep"] {
            let part = try makePart(type: "tool", tool: tool)
            #expect(!ToolCardClassifier.isWriteOperation(part), "\(tool) should NOT be a write operation")
        }
    }

    @Test func splitRoutesPatchPartsToTheChangeBucket() throws {
        let parts = [
            try makePart(id: "1", type: "tool", tool: "read_file"),
            try makePart(id: "2", type: "tool", tool: "bash"),
            try makePart(id: "3", type: "patch"),
            try makePart(id: "4", type: "tool", tool: "edit"),
        ]
        let split = ToolCardClassifier.split(parts)
        #expect(split.fileParts.map(\.id) == ["1", "4"])
        #expect(split.changeParts.map(\.id) == ["3"])
        #expect(split.otherParts.map(\.id) == ["2"])
    }

    // MARK: - Task 2 · diff line parsing

    @Test func patchTextParsesIntoHunkAdditionDeletionAndContext() {
        let patch = """
        @@ -18,9 +18,24 @@
         func parse(_ input: String) throws -> Node {
        -   let tokens = lexer.scan(input)
        +   let tokens = try lexer.scan(input)
        """
        let lines = DiffLineParser.lines(fromPatch: patch)
        #expect(lines.count == 4)
        #expect(lines[0].kind == .hunk)
        #expect(lines[0].text == "@@ -18,9 +18,24 @@")
        #expect(lines[1].kind == .context)
        #expect(lines[1].oldNumber == 18)
        #expect(lines[1].newNumber == 18)
        #expect(lines[2].kind == .deletion)
        #expect(lines[2].oldNumber == 19)
        #expect(lines[2].newNumber == nil)
        #expect(lines[2].text == "   let tokens = lexer.scan(input)")
        #expect(lines[3].kind == .addition)
        #expect(lines[3].oldNumber == nil)
        #expect(lines[3].newNumber == 19)
    }

    @Test func patchWithoutHunkHeaderStillNumbersLines() {
        let lines = DiffLineParser.lines(fromPatch: "-old\n+new\n keep")
        #expect(lines.count == 3)
        #expect(lines[0].kind == .deletion)
        #expect(lines[0].oldNumber == 1)
        #expect(lines[1].kind == .addition)
        #expect(lines[1].newNumber == 1)
        #expect(lines[2].kind == .context)
        #expect(lines[2].oldNumber == 2)
        #expect(lines[2].newNumber == 2)
    }

    @Test func beforeAndAfterDeriveTheSameShape() {
        let lines = DiffLineParser.lines(before: "a\nb\nc\n", after: "a\nB\nc\n")
        #expect(lines.map(\.kind) == [.context, .deletion, .addition, .context])
        #expect(lines[0].text == "a")
        #expect(lines[1].text == "b")
        #expect(lines[1].oldNumber == 2)
        #expect(lines[2].text == "B")
        #expect(lines[2].newNumber == 2)
        #expect(lines[3].text == "c")
        #expect(lines[3].oldNumber == 3)
        #expect(lines[3].newNumber == 3)
    }

    @Test func identicalBeforeAndAfterProducesOnlyContext() {
        let lines = DiffLineParser.lines(before: "a\nb\n", after: "a\nb\n")
        #expect(lines.map(\.kind) == [.context, .context])
    }

    @Test func patchFileHeadersBeforeTheFirstHunkAreSkipped() {
        let patch = """
        --- a/model/Parser.swift
        +++ b/model/Parser.swift
        @@ -1,2 +1,2 @@
        -old
        +new
        """
        let lines = DiffLineParser.lines(fromPatch: patch)
        #expect(lines.count == 3)
        #expect(lines[0].kind == .hunk)
        #expect(lines[1].kind == .deletion)
        #expect(lines[1].text == "old")
    }

    @Test func aRemovedRuleInsideAHunkIsContent() {
        let patch = """
        @@ -1,2 +1,1 @@
        ----
        +---
        """
        let lines = DiffLineParser.lines(fromPatch: patch)
        #expect(lines.count == 3)
        #expect(lines[1].kind == .deletion)
        #expect(lines[1].text == "---")
        #expect(lines[2].kind == .addition)
    }

    @Test func emptyBeforeAndAfterProducesNoLines() {
        #expect(DiffLineParser.lines(before: "", after: "").isEmpty)
    }

    // MARK: - Task 3 · the card in the chat

    @Test func patchPartRendersAsTheChangesCard() throws {
        let part = try makePart(id: "p1", type: "patch")
        let tiles = MessageRowView.cardGridTiles(for: [part])
        #expect(tiles.count == 1)
        guard case .changes(let tilePart) = tiles[0] else {
            Issue.record("expected a changes tile, got \(tiles[0])")
            return
        }
        #expect(tilePart.id == part.id)
    }

    @Test func writeToolStillRendersAsAFileCard() throws {
        let part = try makePart(id: "p2", type: "tool", tool: "write_file")
        let tiles = MessageRowView.cardGridTiles(for: [part])
        #expect(tiles.count == 1)
        guard case .fileCard = tiles[0] else {
            Issue.record("expected a file card, got \(tiles[0])")
            return
        }
    }

    @Test func totalsComeFromTheTurnDiffWhenItHasLoaded() throws {
        let part = try makePart(id: "p3", type: "patch")
        let diff = FileDiff(file: "a.swift", before: "", after: "+x", additions: 12, deletions: 3, status: "modified")
        let totals = FileChangeTotals.resolve(turnDiff: [diff], part: part)
        #expect(totals?.additions == 12)
        #expect(totals?.deletions == 3)
    }

    @Test func totalsFallBackToThePartsOwnCounts() throws {
        let part = Part(
            id: "p4",
            messageID: "m1",
            sessionID: "s1",
            type: "patch",
            text: nil,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: [Part.FileChange(path: "a.swift", additions: 4, deletions: 1, status: "modified")]
        )
        let totals = FileChangeTotals.resolve(turnDiff: nil, part: part)
        #expect(totals?.additions == 4)
        #expect(totals?.deletions == 1)
    }

    @Test func totalsAreUnknownWhenNeitherSourceKnowsThem() throws {
        let part = try makePart(id: "p5", type: "patch")
        #expect(FileChangeTotals.resolve(turnDiff: nil, part: part) == nil)
        #expect(FileChangeTotals.resolve(turnDiff: [], part: part) == nil)
    }

    // MARK: - Task 5 · the changed-file list

    @Test func changedFileListKeepsReportedOrderAndAddsDiffOnlyFiles() {
        let diffs = [
            FileDiff(file: "model/Parser.swift", before: "", after: "+x", additions: 1, deletions: 0, status: "modified"),
            FileDiff(file: "docs/new.md", before: "", after: "+y", additions: 2, deletions: 0, status: "added"),
        ]
        let rows = SessionChangesModel.rows(
            paths: ["model/Parser.swift", "docs/parsing.md"],
            diffs: diffs
        )
        #expect(rows.map(\.path) == ["model/Parser.swift", "docs/parsing.md", "docs/new.md"])
        #expect(rows[0].diff?.additions == 1)
        #expect(rows[1].diff == nil)
        #expect(rows[2].diff?.status == "added")
    }

    @Test func changedFileListDoesNotRepeatTheSameFile() {
        let diffs = [FileDiff(file: "a.swift", before: "", after: "+x", additions: 1, deletions: 0, status: "modified")]
        let rows = SessionChangesModel.rows(paths: ["a.swift", "./a.swift"], diffs: diffs)
        #expect(rows.count == 1)
    }

    // MARK: - Task 4 · write signals

    private func assistantMessage(parts: [Part], parentID: String?) -> MessageWithParts {
        MessageWithParts(
            info: Message(
                id: "m1",
                sessionID: "s1",
                role: "assistant",
                parentID: parentID,
                providerID: nil,
                modelID: nil,
                model: nil,
                error: nil,
                time: Message.TimeInfo(created: 1, completed: 2),
                finish: nil,
                tokens: nil,
                cost: nil,
                structured: nil,
                agent: nil
            ),
            parts: parts
        )
    }

    private func toolPart(id: String, tool: String) -> Part {
        Part(
            id: id,
            messageID: "m1",
            sessionID: "s1",
            type: "tool",
            text: nil,
            tool: tool,
            callID: nil,
            state: nil,
            metadata: nil,
            files: nil
        )
    }

    @Test func readOnlyTurnHasNoWriteSignal() {
        let messages = [assistantMessage(parts: [toolPart(id: "p1", tool: "read_file")], parentID: "u1")]
        #expect(FileChangeSignalScanner.signals(in: messages).isEmpty)
    }

    @Test func writeToolIsASignalWithoutAChangedFileList() {
        let messages = [assistantMessage(parts: [toolPart(id: "p1", tool: "write_file")], parentID: "u1")]
        let signals = FileChangeSignalScanner.signals(in: messages)
        #expect(signals.count == 1)
        #expect(signals.first?.partID == "p1")
        #expect(signals.first?.changedFiles == false)
        #expect(signals.first?.turnUserMessageID == nil)
    }

    @Test func patchPartIsASignalThatCarriesTheTurn() {
        let patch = Part(
            id: "p2",
            messageID: "m1",
            sessionID: "s1",
            type: "patch",
            text: nil,
            tool: nil,
            callID: nil,
            state: nil,
            metadata: nil,
            files: [Part.FileChange(path: "a.swift")]
        )
        let messages = [assistantMessage(parts: [patch], parentID: "u1")]
        let signals = FileChangeSignalScanner.signals(in: messages)
        #expect(signals.count == 1)
        #expect(signals.first?.changedFiles == true)
        #expect(signals.first?.turnUserMessageID == "u1")
    }

    @Test func userMessagesNeverCarryAWriteSignal() throws {
        let userPart = try makePart(id: "p3", type: "tool", tool: "write_file")
        let message = MessageWithParts(
            info: Message(
                id: "u1",
                sessionID: "s1",
                role: "user",
                parentID: nil,
                providerID: nil,
                modelID: nil,
                model: nil,
                error: nil,
                time: Message.TimeInfo(created: 1, completed: 1),
                finish: nil,
                tokens: nil,
                cost: nil,
                structured: nil,
                agent: nil
            ),
            parts: [userPart]
        )
        #expect(FileChangeSignalScanner.signals(in: [message]).isEmpty)
    }
}
