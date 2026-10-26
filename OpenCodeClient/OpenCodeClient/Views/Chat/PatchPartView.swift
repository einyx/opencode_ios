//
//  PatchPartView.swift
//  OpenCodeClient
//
//  The "files changed" card.
//
//  A patch part is the single signal that a turn changed files — V1 sends it,
//  V2 synthesizes it from the assistant message's snapshot. It renders as one
//  card that states how many files changed and how much was added/removed,
//  and tapping it opens the changes surface.
//
//  Spec: docs/features/file_changes_surface/design.md
//

import SwiftUI

struct PatchPartView: View {
    @Environment(\.colorScheme) private var colorScheme
    /// The patch part. Its `files` carry the changed paths.
    let part: Part
    /// The added/removed totals, when they are known.
    let totals: FileChangeTotals?
    /// What the totals cover.
    let scope: FileChangeScope
    /// Opens the changes surface.
    let onOpen: () -> Void

    private var fileCount: Int {
        max(part.files?.count ?? 0, 1)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(DesignColors.Brand.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.patchFilesChanged(fileCount))
                        .font(DesignTypography.bodyProminent)
                        .foregroundStyle(DesignColors.Brand.primary)
                    HStack(spacing: 6) {
                        if let totals {
                            Text(L10n.t(.changesAdded, totals.additions))
                                .foregroundStyle(DesignColors.Brand.primary)
                            Text(L10n.t(.changesDeleted, totals.deletions))
                                .foregroundStyle(DesignColors.Neutral.textSecondary)
                            Text("·")
                                .foregroundStyle(DesignColors.Neutral.textTertiary)
                        }
                        Text(scope.label)
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                    }
                    .font(DesignTypography.microMono)
                }
                Spacer(minLength: DesignSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(DesignTypography.micro)
                    .foregroundStyle(DesignColors.Neutral.textTertiary)
            }
            .font(DesignTypography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSpacing.cardPadding)
            .background(DesignColors.Brand.surface(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.t(.changesOpenInFiles))
    }

    private var accessibilityLabel: String {
        guard let totals else { return L10n.patchFilesChanged(fileCount) }
        return L10n.t(
            .changesAccessibilityLabel,
            fileCount,
            totals.additions,
            totals.deletions
        )
    }
}
