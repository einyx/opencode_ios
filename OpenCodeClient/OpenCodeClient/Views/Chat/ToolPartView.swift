//
//  ToolPartView.swift
//  OpenCodeClient
//

import SwiftUI

struct ToolPartView: View {
    private static let outputPreviewCharacterLimit = 12_000

    @Environment(\.colorScheme) private var colorScheme
    let part: Part
    let sessionTodos: [TodoItem]
    let workspaceDirectory: String?
    let onOpenResolvedPath: (String) -> Void
    @State private var isExpanded: Bool
    @State private var showOpenFileSheet = false
    @State private var decodedImage: UIImage? = nil
    @State private var showImageSheet: Bool = false

    init(
        part: Part,
        sessionTodos: [TodoItem],
        workspaceDirectory: String?,
        onOpenResolvedPath: @escaping (String) -> Void
    ) {
        self.part = part
        self.sessionTodos = sessionTodos
        self.workspaceDirectory = workspaceDirectory
        self.onOpenResolvedPath = onOpenResolvedPath
        self._isExpanded = State(initialValue: part.stateDisplay?.lowercased() == "running")
    }

    private var toolDisplayName: String {
        let raw = part.tool ?? L10n.t(.toolOpenFile)
        if raw == "apply_patch" { return "patch" }
        return raw
    }

    // The card body stays neutral (a plain surface fill, not an accent tint),
    // but a tool card IS actionable — it expands to show input/output and can
    // jump to a file preview. So the tool icon + name carry the electric-blue
    // accent as the "you can tap this" affordance, rather than reading as inert
    // gray metadata. Blue lives on the interactive bits, not the whole card.
    private var toolAccentColor: Color {
        isReadOnlyTool ? DesignColors.Neutral.textSecondary : DesignColors.Brand.primary
    }

    private var isReadOnlyTool: Bool {
        guard let tool = part.tool?.lowercased() else { return false }
        return ["read_file", "read", "grep", "glob", "list", "webfetch", "task", "todoread"]
            .contains { tool.hasPrefix($0) }
    }

    private var toolBackgroundColor: Color {
        DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme))
    }

    /// The tool's subject line: the reason when the call carries one, else
    /// the raw status word. Shown trailing so the tool name never has to
    /// share a line with it.
    private var toolSubjectText: String? {
        if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
            return reason
        }
        return nil
    }

    /// The status word, shown as a pill. It is dropped when the call already
    /// carries a subject line, so the row never repeats itself.
    private var toolStatusText: String? {
        guard toolSubjectText == nil else { return nil }
        if let status = part.stateDisplay, !status.isEmpty {
            return status
        }
        return nil
    }

    private var imageCandidatePaths: [String] {
        var candidates = part.filePathsForNavigation
        if let path = part.state?.pathFromInput, !path.isEmpty {
            candidates.append(path)
        }
        if let path = part.metadata?.path, !path.isEmpty {
            candidates.append(path)
        }
        return candidates
    }

    private var isImageFile: Bool {
        imageCandidatePaths.contains { ImageFileUtils.isImage($0) }
    }

    private var imageDisplayName: String {
        let raw = imageCandidatePaths.first(where: { ImageFileUtils.isImage($0) }) ?? L10n.t(.attachmentImageTitle)
        return raw.split(separator: "/").last.map(String.init) ?? raw
    }

    private static func outputPreview(_ output: String) -> String {
        guard output.count > outputPreviewCharacterLimit else { return output }
        return String(output.prefix(outputPreviewCharacterLimit))
    }

    private static func isOutputTruncated(_ output: String) -> Bool {
        output.count > outputPreviewCharacterLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                toolTag
                if !part.filePathsForNavigation.isEmpty {
                    headerFileOpenButton
                }
            }

            if isExpanded {
                detailContent
                    .transition(.opacity)
            }
        }
        .onChange(of: part.stateDisplay) { _, newValue in
            if newValue?.lowercased() == "completed" {
                isExpanded = false
            }
        }
    }

    /// Compact tag: icon, tool name, subject line, status, chevron. It hugs
    /// its content — a full-width slab per tool call turned the transcript
    /// into a stack of grey rectangles.
    private var toolTag: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(toolAccentColor)
                .font(.caption)
            Text(toolDisplayName)
                .fontWeight(.medium)
                .foregroundStyle(toolAccentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let subject = toolSubjectText {
                Text(subject)
                    .font(DesignTypography.micro)
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let status = toolStatusText {
                Text(status)
                    .font(DesignTypography.micro)
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(
                            DesignColors.Neutral.textSecondary.opacity(DesignColors.Opacity.chipFill)
                        )
                    )
            }
            if part.stateDisplay?.lowercased() == "running" {
                ProgressView()
                    .scaleEffect(0.5)
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(DesignColors.Neutral.textTertiary)
        }
        .font(DesignTypography.micro)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DesignAnimation.spring) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toolcard.detail.\(part.id)")
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityAddTraits(.isButton)
    }

    /// The expanded detail: indented under the tag, with no container of its
    /// own — the mono type carries the hierarchy.
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = part.toolReason ?? part.metadata?.title, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.toolReason))
                        .font(DesignTypography.micro)
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .font(DesignTypography.micro)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if part.tool == "todowrite" {
                let todos = sessionTodos.isEmpty ? part.toolTodos : sessionTodos
                if !todos.isEmpty {
                    let completed = todos.count { $0.isCompleted }
                    Text(String(format: L10n.t(.todoUpdatedBadge), completed, todos.count))
                        .font(DesignTypography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            if part.tool != "todowrite",
               let input = part.toolInputSummaryForDisplay ?? part.metadata?.input.map(DisplayTextDecoder.decodeJSONUnicodeEscapes),
               !input.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.toolCommandInput))
                        .font(DesignTypography.micro)
                        .foregroundStyle(.secondary)
                    Text(input)
                        .font(DesignTypography.microMono)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let path = part.metadata?.path {
                LabeledContent(L10n.t(.toolPath), value: path)
            }
            switch part.toolDetailPresentation(isImageFile: isImageFile) {
            case .hidden:
                EmptyView()
            case .successImage:
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.toolOutput))
                        .font(DesignTypography.micro)
                        .foregroundStyle(.secondary)
                    if let img = decodedImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DesignCorners.small))
                            .onTapGesture { showImageSheet = true }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                            Text(L10n.t(.toolImageFile))
                                .font(DesignTypography.micro)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .text(let output):
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.toolOutput))
                        .font(DesignTypography.micro)
                        .foregroundStyle(.secondary)
                    detailOutputText(output)
                    if Self.isOutputTruncated(output) {
                        Text("Output truncated: showing first \(Self.outputPreviewCharacterLimit.formatted()) of \(output.count.formatted()) characters.")
                            .font(DesignTypography.micro)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !part.filePathsForNavigation.isEmpty {
                ForEach(part.filePathsForNavigation, id: \.self) { path in
                    Button {
                        openFile(path)
                    } label: {
                        Label(L10n.toolOpenFileLabel(path: path), systemImage: "folder.badge.plus")
                            .font(DesignTypography.micro)
                    }
                }
            }
        }
        .font(DesignTypography.micro)
        .padding(.leading, DesignSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailOutputText(_ output: String) -> some View {
        if part.showsToolErrorBody {
            Text(Self.outputPreview(output))
                .font(DesignTypography.microMono)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("toolcard.error.\(part.id)")
        } else {
            Text(Self.outputPreview(output))
                .font(DesignTypography.microMono)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerFileOpenButton: some View {
        Button {
            if part.filePathsForNavigation.count == 1 {
                openFile(part.filePathsForNavigation[0])
            } else {
                showOpenFileSheet = true
            }
        } label: {
            Image(systemName: "folder.badge.plus")
                .font(DesignControls.toolOpenFileIconFont)
                .frame(
                    width: DesignControls.toolOpenFileButtonSize,
                    height: DesignControls.toolOpenFileButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openFile(_ path: String) {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = PathNormalizer.resolveWorkspaceRelativePath(raw, workspaceDirectory: workspaceDirectory)
        guard !p.isEmpty else { return }
        onOpenResolvedPath(p)
    }
}

nonisolated enum ToolDetailPresentation: Equatable {
    case hidden
    case successImage
    case text(String)
}

extension Part {
    nonisolated var showsToolErrorBody: Bool {
        (toolOutput?.isEmpty != false) && !(toolError ?? "").isEmpty
    }

    nonisolated func toolDetailPresentation(isImageFile: Bool) -> ToolDetailPresentation {
        guard let output = toolOutputForDisplay, !output.isEmpty else { return .hidden }
        if tool == "todowrite" && !showsToolErrorBody { return .hidden }
        if isImageFile && !showsToolErrorBody { return .successImage }
        return .text(output)
    }
}
