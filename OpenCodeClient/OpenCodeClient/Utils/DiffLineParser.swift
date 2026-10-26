//
//  DiffLineParser.swift
//  OpenCodeClient
//
//  Turns a diff into renderable lines. Two sources feed it:
//
//  - V2 sends the server's unified patch text (`FileDiff.patchText`) and
//    leaves `before` empty, so the patch is the only body it can show.
//  - V1 sends the file's before/after content and no patch, so the diff is
//    derived here.
//
//  The two are kept apart on purpose: the renderer must never guess whether
//  `after` holds a patch or file content.
//
//  Spec: docs/features/file_changes_surface/design.md
//

import Foundation

/// What a diff line is.
enum DiffLineKind: Equatable {
    /// A `@@ … @@` hunk header.
    case hunk
    /// A line the change adds.
    case addition
    /// A line the change removes.
    case deletion
    /// A line that did not change.
    case context
}

/// One renderable diff line.
struct DiffLine: Identifiable, Equatable {
    /// Position in the diff. Stable for a given parse, unique within it.
    let id: Int
    let kind: DiffLineKind
    /// The line number in the file before the change, when the line exists there.
    let oldNumber: Int?
    /// The line number in the file after the change, when the line exists there.
    let newNumber: Int?
    /// The line's content, without the diff marker.
    let text: String
}

enum DiffLineParser {
    /// Above this many lines the derived diff stops trying to align them and
    /// reports the whole before/after block as removed/added. A phone is not
    /// the place to run an expensive alignment.
    static let derivedAlignmentLimit = 400

    // MARK: - Patch text

    /// Parse a unified patch into lines.
    static func lines(fromPatch patch: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldNumber = 1
        var newNumber = 1
        var seenHunk = false

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(raw)
            if text.isEmpty { continue }
            if text.hasPrefix("@@") {
                seenHunk = true
                lines.append(DiffLine(id: lines.count, kind: .hunk, oldNumber: nil, newNumber: nil, text: text))
                if let header = parseHunkHeader(text) {
                    oldNumber = header.oldStart
                    newNumber = header.newStart
                }
                continue
            }
            // "\ No newline at end of file" carries no content. The "---"/"+++"
            // file headers only appear before the first hunk — inside a hunk a
            // line starting with "---" is content (a removed rule, say).
            if text.hasPrefix("\\") { continue }
            if !seenHunk && (text.hasPrefix("---") || text.hasPrefix("+++")) { continue }

            if text.hasPrefix("+") {
                lines.append(DiffLine(id: lines.count, kind: .addition, oldNumber: nil, newNumber: newNumber, text: String(text.dropFirst())))
                newNumber += 1
            } else if text.hasPrefix("-") {
                lines.append(DiffLine(id: lines.count, kind: .deletion, oldNumber: oldNumber, newNumber: nil, text: String(text.dropFirst())))
                oldNumber += 1
            } else {
                // Context lines may or may not carry the leading space.
                let content = text.hasPrefix(" ") ? String(text.dropFirst()) : text
                lines.append(DiffLine(id: lines.count, kind: .context, oldNumber: oldNumber, newNumber: newNumber, text: content))
                oldNumber += 1
                newNumber += 1
            }
        }
        return lines
    }

    /// `@@ -12,7 +12,9 @@` → old start 12, new start 12.
    private static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int)? {
        guard let range = header.range(of: "@@") else { return nil }
        let body = header[range.upperBound...].prefix { $0 != "@" }
        let parts = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        func start(_ token: String) -> Int? {
            guard token.hasPrefix("-") || token.hasPrefix("+") else { return nil }
            let digits = token.dropFirst().prefix { $0.isNumber }
            return Int(digits)
        }
        guard let oldStart = start(parts[0]), let newStart = start(parts[1]) else { return nil }
        return (oldStart, newStart)
    }

    // MARK: - Derived from before/after

    /// Derive diff lines from the file's content before and after the change.
    ///
    /// Common prefix and suffix become context; the middle is aligned with a
    /// longest-common-subsequence pass, unless it is too large to align.
    static func lines(before: String, after: String) -> [DiffLine] {
        let beforeLines = splitLines(before)
        let afterLines = splitLines(after)

        var prefix = 0
        while prefix < beforeLines.count, prefix < afterLines.count, beforeLines[prefix] == afterLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (beforeLines.count - prefix), suffix < (afterLines.count - prefix),
              beforeLines[beforeLines.count - 1 - suffix] == afterLines[afterLines.count - 1 - suffix] {
            suffix += 1
        }

        var lines: [DiffLine] = []
        var oldNumber = 1
        var newNumber = 1

        for index in 0..<prefix {
            lines.append(DiffLine(id: lines.count, kind: .context, oldNumber: oldNumber, newNumber: newNumber, text: beforeLines[index]))
            oldNumber += 1
            newNumber += 1
        }

        let beforeMiddle = Array(beforeLines[prefix..<(beforeLines.count - suffix)])
        let afterMiddle = Array(afterLines[prefix..<(afterLines.count - suffix)])
        let script = editScript(before: beforeMiddle, after: afterMiddle)
        for step in script {
            switch step {
            case .keep(let text):
                lines.append(DiffLine(id: lines.count, kind: .context, oldNumber: oldNumber, newNumber: newNumber, text: text))
                oldNumber += 1
                newNumber += 1
            case .remove(let text):
                lines.append(DiffLine(id: lines.count, kind: .deletion, oldNumber: oldNumber, newNumber: nil, text: text))
                oldNumber += 1
            case .insert(let text):
                lines.append(DiffLine(id: lines.count, kind: .addition, oldNumber: nil, newNumber: newNumber, text: text))
                newNumber += 1
            }
        }

        let afterSuffixStart = afterLines.count - suffix
        for index in 0..<suffix {
            lines.append(DiffLine(
                id: lines.count,
                kind: .context,
                oldNumber: oldNumber,
                newNumber: newNumber,
                text: afterLines[afterSuffixStart + index]
            ))
            oldNumber += 1
            newNumber += 1
        }
        return lines
    }

    private enum EditStep: Equatable {
        case keep(String)
        case remove(String)
        case insert(String)
    }

    /// Align two line blocks. Falls back to "remove everything, then insert
    /// everything" when the blocks are too large to align cheaply.
    private static func editScript(before: [String], after: [String]) -> [EditStep] {
        guard !before.isEmpty || !after.isEmpty else { return [] }
        guard !before.isEmpty else { return after.map { .insert($0) } }
        guard !after.isEmpty else { return before.map { .remove($0) } }
        guard before.count <= derivedAlignmentLimit, after.count <= derivedAlignmentLimit else {
            return before.map { .remove($0) } + after.map { .insert($0) }
        }

        // Longest common subsequence over the two blocks.
        let rows = before.count
        let columns = after.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: columns + 1), count: rows + 1)
        for row in stride(from: rows - 1, through: 0, by: -1) {
            for column in stride(from: columns - 1, through: 0, by: -1) {
                if before[row] == after[column] {
                    table[row][column] = table[row + 1][column + 1] + 1
                } else {
                    table[row][column] = max(table[row + 1][column], table[row][column + 1])
                }
            }
        }

        var steps: [EditStep] = []
        var row = 0
        var column = 0
        while row < rows && column < columns {
            if before[row] == after[column] {
                steps.append(.keep(before[row]))
                row += 1
                column += 1
            } else if table[row + 1][column] >= table[row][column + 1] {
                steps.append(.remove(before[row]))
                row += 1
            } else {
                steps.append(.insert(after[column]))
                column += 1
            }
        }
        while row < rows {
            steps.append(.remove(before[row]))
            row += 1
        }
        while column < columns {
            steps.append(.insert(after[column]))
            column += 1
        }
        return steps
    }

    /// Split file content into lines, dropping a trailing empty line so a
    /// file that ends with a newline does not grow a phantom line.
    private static func splitLines(_ content: String) -> [String] {
        guard !content.isEmpty else { return [] }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
