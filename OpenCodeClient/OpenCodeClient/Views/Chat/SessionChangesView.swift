//
//  SessionChangesView.swift
//  OpenCodeClient
//
//  The changes surface: the files a turn (or a session) changed, and the diff
//  of the selected one.
//
//  It is one view with two hosts — an iPhone sheet and the iPad files column
//  — because the HIG's Modality guidance keeps a modal task shallow: one
//  path (list → diff), never a file browser inside the diff.
//
//  Spec: docs/features/file_changes_surface/design.md
//

import SwiftUI

struct SessionChangesView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// The changed paths, in the order the turn reported them.
    let paths: [String]
    /// The diffs the server returned for this scope. May be empty while the
    /// diff is still loading.
    let diffs: [FileDiff]
    /// What the list covers.
    let scope: FileChangeScope
    /// The workspace the paths are relative to.
    let workspaceDirectory: String?
    /// Opens a changed file in the app's file preview.
    let onOpenFile: (String) -> Void
    /// Closes the surface. `nil` when the host owns the dismissal.
    var onClose: (() -> Void)? = nil

    @State private var selectedPath: String?

    /// Every changed file: the reported paths first, then any file only the
    /// diff knows about.
    private var fileRows: [SessionChangeFile] {
        SessionChangesModel.rows(paths: paths, diffs: diffs)
    }

    private var totals: FileChangeTotals? {
        guard !diffs.isEmpty else { return nil }
        return FileChangeTotals(
            additions: diffs.reduce(0) { $0 + $1.additions },
            deletions: diffs.reduce(0) { $0 + $1.deletions }
        )
    }

    private var selectedRow: SessionChangeFile? {
        let rows = fileRows
        if let selectedPath, let match = rows.first(where: { PathNormalizer.normalize($0.path) == PathNormalizer.normalize(selectedPath) }) {
            return match
        }
        return rows.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if fileRows.isEmpty {
                emptyState
            } else {
                fileList
                Divider()
                diffBody
            }
        }
        .background(DesignColors.Neutral.subtleFill(for: colorScheme))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.patchFilesChanged(max(fileRows.count, 1)))
                    .font(DesignTypography.headline)
                HStack(spacing: 6) {
                    if let totals {
                        Text(L10n.t(.changesAdded, totals.additions))
                            .foregroundStyle(DesignColors.Brand.primary)
                        Text(L10n.t(.changesDeleted, totals.deletions))
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                        Text("·").foregroundStyle(DesignColors.Neutral.textTertiary)
                    }
                    Text(scope.label)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                }
                .font(DesignTypography.microMono)
            }
            Spacer(minLength: DesignSpacing.sm)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(DesignTypography.meta)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .accessibilityLabel(L10n.t(.appClose))
            }
        }
        .padding(DesignSpacing.md)
    }

    // MARK: - File list

    private var fileList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(fileRows) { row in
                    Button {
                        selectedPath = row.path
                    } label: {
                        HStack(spacing: DesignSpacing.sm) {
                            Text(row.displayName)
                                .font(DesignTypography.microMono)
                                .foregroundStyle(DesignColors.Neutral.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let status = row.statusLabel {
                                Text(status)
                                    .font(DesignTypography.microMono)
                                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                                    .padding(.horizontal, DesignSpacing.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignCorners.small)
                                            .stroke(DesignColors.Neutral.textTertiary, lineWidth: 1)
                                    )
                            }
                            Spacer(minLength: DesignSpacing.sm)
                            if let diff = row.diff {
                                Text(L10n.t(.changesAdded, diff.additions))
                                    .foregroundStyle(DesignColors.Brand.primary)
                                Text(L10n.t(.changesDeleted, diff.deletions))
                                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                            }
                        }
                        .font(DesignTypography.microMono)
                        .padding(.horizontal, DesignSpacing.md)
                        .padding(.vertical, DesignSpacing.sm)
                        .background(
                            isSelected(row)
                                ? DesignColors.Brand.selection(for: colorScheme)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.accessibilityLabel)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Diff

    @ViewBuilder
    private var diffBody: some View {
        if let row = selectedRow {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                HStack(spacing: DesignSpacing.sm) {
                    Text(row.path)
                        .font(DesignTypography.microMono)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DesignSpacing.sm)
                    Button {
                        openFile(row.path)
                    } label: {
                        Text(L10n.t(.toolOpenFile))
                            .font(DesignTypography.meta)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignColors.Brand.primary)
                }
                if let lines = row.diffLines, !lines.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        DiffLinesView(lines: lines)
                    }
                } else if diffs.isEmpty {
                    HStack(spacing: DesignSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.t(.changesLoadingDiff))
                            .font(DesignTypography.meta)
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                    }
                } else {
                    Text(L10n.t(.changesNoDiffForFile))
                        .font(DesignTypography.meta)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                }
            }
            .padding(DesignSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSpacing.sm) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(DesignColors.Neutral.textTertiary)
            Text(L10n.t(.changesNoDiffForFile))
                .font(DesignTypography.meta)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func diff(for path: String) -> FileDiff? {
        let normalized = PathNormalizer.normalize(path)
        return diffs.first { PathNormalizer.normalize($0.file) == normalized }
    }

    /// Whether the row is the one whose diff is on screen.
    private func isSelected(_ row: SessionChangeFile) -> Bool {
        guard let selectedPath else { return fileRows.first?.id == row.id }
        return PathNormalizer.normalize(selectedPath) == row.id
    }

    private func openFile(_ path: String) {
        let resolved = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: workspaceDirectory)
        guard !resolved.isEmpty else { return }
        onOpenFile(resolved)
    }
}

/// How a file changed.
enum FileChangeStatus {
    case added
    case modified
    case deleted

    init?(raw: String?) {
        guard let raw = raw?.lowercased() else { return nil }
        switch raw {
        case "added", "new", "untracked": self = .added
        case "deleted", "removed": self = .deleted
        default: self = .modified
        }
    }

    var label: String {
        switch self {
        case .added: return L10n.t(.changesBadgeAdded)
        case .modified: return L10n.t(.changesBadgeModified)
        case .deleted: return L10n.t(.changesBadgeDeleted)
        }
    }
}

/// The changed-file list of the changes surface.
enum SessionChangesModel {
    /// Every changed file: the reported paths first, then any file only the
    /// diff knows about. Paths are matched after normalization, so the same
    /// file never appears twice.
    static func rows(paths: [String], diffs: [FileDiff]) -> [SessionChangeFile] {
        var seen = Set<String>()
        var rows: [SessionChangeFile] = []
        for path in paths {
            let normalized = PathNormalizer.normalize(path)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            rows.append(SessionChangeFile(path: path, diff: diff(for: path, in: diffs)))
        }
        for diff in diffs {
            let normalized = PathNormalizer.normalize(diff.file)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            rows.append(SessionChangeFile(path: diff.file, diff: diff))
        }
        return rows
    }

    private static func diff(for path: String, in diffs: [FileDiff]) -> FileDiff? {
        let normalized = PathNormalizer.normalize(path)
        return diffs.first { PathNormalizer.normalize($0.file) == normalized }
    }
}

/// One row of the changed-file list.
struct SessionChangeFile: Identifiable {
    let path: String
    let diff: FileDiff?

    var id: String { PathNormalizer.normalize(path) }

    var displayName: String {
        let normalized = PathNormalizer.normalize(path)
        return normalized.isEmpty ? path : normalized
    }

    var status: FileChangeStatus? {
        FileChangeStatus(raw: diff?.status)
    }

    var statusLabel: String? { status?.label }

    /// The diff lines of this file, when the payload carries any.
    ///
    /// V2 sends the server's patch text; V1 sends the file's before/after
    /// content, and the diff is derived from it. The two are never guessed
    /// apart.
    var diffLines: [DiffLine]? {
        guard let diff else { return nil }
        if let patch = diff.patchText, !patch.isEmpty {
            return DiffLineParser.lines(fromPatch: patch)
        }
        if !diff.before.isEmpty || !diff.after.isEmpty {
            return DiffLineParser.lines(before: diff.before, after: diff.after)
        }
        return nil
    }

    var accessibilityLabel: String {
        guard let diff else { return displayName }
        return L10n.t(.changesFileAccessibility, displayName, diff.additions, diff.deletions)
    }
}
