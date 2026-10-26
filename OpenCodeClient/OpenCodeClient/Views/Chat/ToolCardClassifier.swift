//
//  ToolCardClassifier.swift
//  OpenCodeClient
//
//  Classification logic for the "tool card render redo": which parts render as
//  file cards (2-column grid) vs. collapse into a single "N tool calls" row.
//  Extracted from MessageRowView so the behavior is unit-testable without a View.
//

import Foundation

enum ToolCardClassifier {
    /// A "file operation" is a tool whose name matches one of the file-op
    /// verbs. Loose prefix match so aliases like "edit"/"write"/"read"/"patch"
    /// and full forms like "edit_file"/"apply_patch" all count.
    static let fileOpToolPrefixes = [
        "apply_patch", "edit_file", "write_file", "read_file",
        "patch", "edit", "write", "read",
    ]

    static func isFileOperation(_ part: Part) -> Bool {
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        return fileOpToolPrefixes.contains { tool.hasPrefix($0) }
    }

    /// The "files changed" signal. A patch part is not a single file
    /// operation: it summarizes the files a turn changed and renders as the
    /// changes card, not as one file card.
    static func isChangePart(_ part: Part) -> Bool {
        part.isPatch
    }

    /// Tool names that mutate the workspace. A read is not a write.
    static let writeToolPrefixes = [
        "apply_patch", "edit_file", "write_file",
        "patch", "edit", "write",
    ]

    /// True when the part is a tool that can change files on disk. Used to
    /// decide when the file tree and status need a refresh.
    static func isWriteOperation(_ part: Part) -> Bool {
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        return writeToolPrefixes.contains { tool.hasPrefix($0) }
    }

    /// `read` tool names (and aliases) — a directory read can only come from one of
    /// these, never from edit/write/patch.
    static let readToolPrefixes = ["read_file", "read"]

    /// True when this part is a `read` whose tool output reports a directory.
    /// The server embeds `<type>directory</type>` in the read output for a folder
    /// (vs. `<type>file</type>` for a file); see Models/Message.swift toolOutput.
    static func isDirectoryRead(_ part: Part) -> Bool {
        guard part.isTool, let tool = part.tool?.lowercased() else { return false }
        guard readToolPrefixes.contains(where: { tool.hasPrefix($0) }) else { return false }
        guard let output = part.toolOutput else { return false }
        return output.contains("<type>directory</type>")
    }

    /// One entry in a directory read: a child file or subdirectory.
    struct DirectoryEntry: Identifiable, Equatable {
        let name: String
        let isDirectory: Bool
        var id: String { name }
    }

    /// Parse the `<entries>…</entries>` block out of a directory read's output.
    /// Each line is a child name; names ending in "/" are subdirectories. Blank
    /// lines and trailing summary lines like "(12 entries)" are dropped. The
    /// display name keeps the trailing "/" stripped so the UI can render it
    /// uniformly with its own icon.
    static func parseDirectoryEntries(_ output: String?) -> [DirectoryEntry] {
        guard let output else { return [] }
        guard let openRange = output.range(of: "<entries>") else { return [] }
        let afterOpen = output[openRange.upperBound...]
        let body: Substring
        if let closeRange = afterOpen.range(of: "</entries>") {
            body = afterOpen[..<closeRange.lowerBound]
        } else {
            body = afterOpen
        }

        var entries: [DirectoryEntry] = []
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // Drop summary lines such as "(12 entries)" or "(0 entries)".
            if line.hasPrefix("(") && line.hasSuffix("entries)") { continue }
            let isDir = line.hasSuffix("/")
            let name = isDir ? String(line.dropLast()) : line
            if name.isEmpty { continue }
            entries.append(DirectoryEntry(name: name, isDirectory: isDir))
        }
        return entries
    }

    /// Split a buffered run of tool/patch parts into the file-card group (grid),
    /// the changes group (the "N files changed" card) and the "other tools"
    /// group (merged into one "N tool calls" disclosure row).
    static func split(_ parts: [Part]) -> (fileParts: [Part], changeParts: [Part], otherParts: [Part]) {
        var fileParts: [Part] = []
        var changeParts: [Part] = []
        var otherParts: [Part] = []
        for part in parts {
            if isChangePart(part) {
                changeParts.append(part)
            } else if isFileOperation(part) {
                fileParts.append(part)
            } else {
                otherParts.append(part)
            }
        }
        return (fileParts, changeParts, otherParts)
    }

    /// Number shown in the merged "N tool calls" row: the tools that are
    /// neither file operations nor change parts.
    ///
    /// It counts the `otherParts` group of `split`, so the three-way
    /// classification stays in one place — a change part is not a tool call
    /// and must not be counted as one.
    static func toolCallsCount(_ parts: [Part]) -> Int {
        split(parts).otherParts.count
    }
}
