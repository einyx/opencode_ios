//
//  DiffLinesView.swift
//  OpenCodeClient
//
//  Renders parsed diff lines.
//
//  The Quiet Tech palette allows one colour on screen, so the diff carries
//  its meaning in shape, not in red/green: additions use the accent, removals
//  use secondary text, and every line keeps its marker, its line numbers and
//  its spoken label. The diff still reads in greyscale.
//
//  Spec: docs/features/file_changes_surface/design.md
//

import SwiftUI

struct DiffLinesView: View {
    let lines: [DiffLine]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    DiffLineRow(line: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DiffLineRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let line: DiffLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: 34, alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 34, alignment: .trailing)
                .padding(.trailing, DesignSpacing.sm)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(DesignTypography.microMono)
        .padding(.horizontal, DesignSpacing.sm)
        .background(background)
        .foregroundStyle(foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var background: Color {
        switch line.kind {
        case .addition: return DesignColors.Brand.surface(for: colorScheme)
        case .deletion: return DesignColors.Neutral.subtleFill(for: colorScheme)
        case .hunk, .context: return Color.clear
        }
    }

    private var foreground: Color {
        switch line.kind {
        case .addition: return DesignColors.Brand.primary
        case .deletion: return DesignColors.Neutral.textSecondary
        case .hunk: return DesignColors.Neutral.textTertiary
        case .context: return DesignColors.Neutral.text
        }
    }

    private var accessibilityLabel: String {
        switch line.kind {
        case .hunk:
            return line.text
        case .addition:
            return "added, line \(line.newNumber ?? 0): \(line.text)"
        case .deletion:
            return "removed, line \(line.oldNumber ?? 0): \(line.text)"
        case .context:
            return "line \(line.newNumber ?? line.oldNumber ?? 0): \(line.text)"
        }
    }
}
