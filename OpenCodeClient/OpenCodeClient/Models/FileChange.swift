//
//  FileChange.swift
//  OpenCodeClient
//
//  The types the "files changed" surface shares: the totals a change card
//  shows, and the scope those totals belong to.
//
//  Spec: docs/features/file_changes_surface/design.md
//

import Foundation

/// How many lines a change added and removed.
///
/// Counts live in the diff payload, not in the part: V2's snapshot carries
/// paths only, so the totals are known only once the diff has loaded. When
/// they are unknown the surface shows the file count alone rather than
/// pretending the change added nothing.
struct FileChangeTotals: Equatable {
    let additions: Int
    let deletions: Int

    static let zero = FileChangeTotals(additions: 0, deletions: 0)

    /// The totals a change card shows.
    ///
    /// The turn's diff is authoritative when it has loaded. Otherwise the
    /// part's own per-file counts are used (V1 patch parts carry them), and
    /// when neither is known the answer is `nil` — the card then shows the
    /// file count alone rather than a misleading zero.
    static func resolve(turnDiff: [FileDiff]?, part: Part) -> FileChangeTotals? {
        if let turnDiff, !turnDiff.isEmpty {
            return FileChangeTotals(
                additions: turnDiff.reduce(0) { $0 + $1.additions },
                deletions: turnDiff.reduce(0) { $0 + $1.deletions }
            )
        }
        let files = part.files ?? []
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        guard additions > 0 || deletions > 0 else { return nil }
        return FileChangeTotals(additions: additions, deletions: deletions)
    }
}

/// What a change summary covers.
enum FileChangeScope: Equatable {
    /// One turn — the files that turn changed.
    case turn
    /// The whole session.
    case session

    var label: String {
        switch self {
        case .turn: return L10n.t(.changesScopeTurn)
        case .session: return L10n.t(.changesScopeSession)
        }
    }
}

/// Finds the parts of a transcript that mean "files may have changed".
enum FileChangeSignalScanner {
    /// One signal.
    struct Signal: Equatable {
        /// The part that carried the signal.
        let partID: String
        /// The user message that started the turn, when the signal is a
        /// change part (the server reported which files changed).
        let turnUserMessageID: String?
        /// True when the server reported the changed files themselves.
        let changedFiles: Bool
    }

    /// The signals of a transcript, in order.
    static func signals(in messages: [MessageWithParts]) -> [Signal] {
        var signals: [Signal] = []
        for message in messages {
            guard message.info.role == "assistant" else { continue }
            for part in message.parts {
                let changed = ToolCardClassifier.isChangePart(part)
                let wrote = ToolCardClassifier.isWriteOperation(part)
                guard changed || wrote else { continue }
                signals.append(Signal(
                    partID: part.id,
                    turnUserMessageID: changed ? message.info.parentID : nil,
                    changedFiles: changed
                ))
            }
        }
        return signals
    }
}
