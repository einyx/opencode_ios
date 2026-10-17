//
//  FileContentView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

enum ImageFileUtils {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico", "svg",
    ]

    static func isImage(_ path: String) -> Bool {
        let ext = path.lowercased().split(separator: ".").last.map(String.init) ?? ""
        return extensions.contains(ext)
    }
}

/// Markdown file preview modes. `native` is the default MarkdownUI renderer;
/// `web` is the WKWebView renderer for HTML-in-MD / cards / inline SVG; `source`
/// is the raw markdown text.
enum MarkdownPreviewMode: String, CaseIterable {
    case native
    case web
    case source

    var label: String {
        switch self {
        case .native: return L10n.t(.fileNativePreview)
        case .web: return L10n.t(.fileWebPreview)
        case .source: return L10n.t(.fileMarkdownSource)
        }
    }

    var menuSystemImage: String {
        switch self {
        case .native: return "doc.richtext"
        case .web: return "globe"
        case .source: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct FileContentView: View {
    @Bindable var state: AppState
    let filePath: String
    var workspaceDirectory: String? = nil
    var boundSessionID: String? = nil
    @State private var content: String?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var previewMode: MarkdownPreviewMode = .web
    @State private var refreshGeneration: UInt64 = 0
    @State private var activeLoadKey: FileContentLoadKey?
    @State private var renderedOpenOwner: ExternalFileOpenOwner?

    private var isImage: Bool {
        ImageFileUtils.isImage(filePath)
    }

    private var isMarkdown: Bool {
        filePath.lowercased().hasSuffix(".md") || filePath.lowercased().hasSuffix(".markdown")
    }

    private var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }

    private var effectiveWorkspaceDirectory: String? {
        workspaceDirectory ?? state.currentSession?.directory
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                bumpRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isLoading)
            .accessibilityLabel(L10n.t(.contentRefreshHelp))
            .help(L10n.t(.contentRefreshHelp))
        }
        if let content {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: content, subject: Text(fileName)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityIdentifier("file-content-share")
            }
        }
        if let imageData, let uiImage = UIImage(data: imageData) {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: Image(uiImage: uiImage),
                    preview: SharePreview(fileName, image: Image(uiImage: uiImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        if isMarkdown {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(L10n.t(.filePreviewMode), selection: $previewMode) {
                        ForEach(MarkdownPreviewMode.allCases, id: \.self) { mode in
                            Label(mode.label, systemImage: mode.menuSystemImage).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: previewMode.menuSystemImage)
                }
                .accessibilityIdentifier("markdown-preview-mode-menu")
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(L10n.t(.appLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("file-content-loading")
                    .refreshable { bumpRefresh() }
            } else if let err = loadError {
                ContentUnavailableView(L10n.t(.appError), systemImage: "exclamationmark.triangle", description: Text(err))
                    .accessibilityIdentifier("file-content-error")
                    .refreshable { bumpRefresh() }
            } else if let data = imageData, let uiImage = UIImage(data: data) {
                ImageView(uiImage: uiImage)
                    .refreshable { bumpRefresh() }
            } else if let text = content {
                contentView(text: text)
                    .accessibilityIdentifier("file-content-body")
            } else {
                ContentUnavailableView(L10n.t(.appNoContent), systemImage: "doc.text")
                    .refreshable { bumpRefresh() }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .toolbarBackground(.visible, for: .navigationBar)
        .accessibilityIdentifier("file-content-screen")
        .accessibilityValue(openOwnerForRender?.sessionID ?? "-")
        .task(id: loadKey) {
            let key = loadKey
            activeLoadKey = key
            renderedOpenOwner = ExternalFileOpenOwner(load: key, sessionID: boundSessionID)
            await loadContent(key)
        }
        .onChange(of: boundSessionID) { _, sessionID in
            rebindRenderedOpenOwner(sessionID: sessionID)
        }
    }

    private var openOwnerForRender: ExternalFileOpenOwner? {
        if var owner = renderedOpenOwner {
            owner.sessionID = boundSessionID
            return owner
        }
        if let key = activeLoadKey {
            return ExternalFileOpenOwner(load: key, sessionID: boundSessionID)
        }
        return nil
    }

    private func rebindRenderedOpenOwner(sessionID: String?) {
        if var owner = renderedOpenOwner {
            guard owner.sessionID != sessionID else { return }
            owner.sessionID = sessionID
            renderedOpenOwner = owner
        } else if let key = activeLoadKey {
            renderedOpenOwner = ExternalFileOpenOwner(load: key, sessionID: sessionID)
        }
    }

    private func bumpRefresh() {
        refreshGeneration &+= 1
    }

    private var loadKey: FileContentLoadKey {
        FileContentLoadKey.current(
            state: state,
            path: filePath,
            workspaceDirectory: effectiveWorkspaceDirectory,
            revision: refreshGeneration
        )
    }

    /// MarkdownUI crashes/freezes on long lines or large content. Skip it entirely for problematic files.
    private static let markdownMaxLineLength = 5000
    private static let markdownMaxTotalLength = 60_000

    private func useRawTextForMarkdown(_ text: String) -> Bool {
        return text.count > Self.markdownMaxTotalLength || MarkdownPreviewView.maxLineLength(in: text) > Self.markdownMaxLineLength
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        if isMarkdown {
            let useRaw = useRawTextForMarkdown(text)
            switch previewMode {
            case .native:
                if useRaw {
                    // MarkdownUI can freeze on long lines / large content: degrade to source.
                    RawTextView(text: text, monospaced: false, onRefresh: bumpRefresh)
                } else {
                    MarkdownPreviewView(
                        text: text,
                        state: state,
                        markdownFilePath: filePath,
                        workspaceDirectory: effectiveWorkspaceDirectory,
                        onRefresh: bumpRefresh
                    )
                }
            case .web:
                MarkdownWebPreviewContainer(
                    text: text,
                    state: state,
                    markdownFilePath: filePath,
                    workspaceDirectory: effectiveWorkspaceDirectory,
                    openOwner: openOwnerForRender,
                    isOversized: useRaw,
                    onSwitchToNative: { previewMode = .native },
                    onSwitchToSource: { previewMode = .source }
                )
                .refreshable { bumpRefresh() }
            case .source:
                RawTextView(text: text, monospaced: true, onRefresh: bumpRefresh)
            }
        } else {
            CodeView(text: text, path: filePath, onRefresh: bumpRefresh)
        }
    }

    private func loadContent(_ key: FileContentLoadKey) async {
        guard activeLoadKey == key else { return }
        isLoading = true
        loadError = nil
        imageData = nil
        content = nil
        let fetched: Result<FileContent, Error>
        do {
            fetched = .success(try await state.loadFileContent(path: key.path, workspaceDirectory: key.workspaceDirectory))
        } catch {
            fetched = .failure(error)
        }
        guard !Task.isCancelled, activeLoadKey == key else { return }
        switch fetched {
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            content = nil
            imageData = nil
            loadError = error.localizedDescription
        case .success(let fc):
            applyLoaded(fc, path: key.path)
        }
        isLoading = false
    }

    private func applyLoaded(_ fc: FileContent, path: String) {
        loadError = nil
        if ImageFileUtils.isImage(path) {
            content = nil
            if let rawContent = fc.content {
                if let data = Data(base64Encoded: rawContent), UIImage(data: data) != nil {
                    imageData = data
                } else {
                    let cleaned = rawContent
                        .replacingOccurrences(of: "\n", with: "")
                        .replacingOccurrences(of: "\r", with: "")
                        .replacingOccurrences(of: " ", with: "")
                    if let data = Data(base64Encoded: cleaned), UIImage(data: data) != nil {
                        imageData = data
                    } else {
                        imageData = nil
                        loadError = L10n.t(.contentImageDecodeFailed)
                    }
                }
            } else {
                imageData = nil
                loadError = L10n.t(.contentNoImageData)
            }
        } else if let text = fc.text {
            imageData = nil
            content = text
        } else if fc.content != nil, fc.type == "binary" {
            content = nil
            imageData = nil
            loadError = L10n.t(.fileBinary)
        } else {
            content = nil
            imageData = nil
        }
    }
}

/// Simple code view with line numbers
struct CodeView: View {
    let text: String
    let path: String
    var onRefresh: (() -> Void)? = nil

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        scrolling
    }

    private var scrolling: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: DesignSpacing.sm) {
                            Text("\(i + 1)")
                                .font(DesignTypography.microMono)
                                .foregroundStyle(DesignColors.Neutral.textSecondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, DesignSpacing.sm)
                .frame(minWidth: 400, alignment: .leading)
            }
        }
        .modifier(VerticalRefresh(action: onRefresh))
    }
}

private struct VerticalRefresh: ViewModifier {
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.refreshable { action() }
        } else {
            content
        }
    }
}

/// Markdown preview using MarkdownUI library for full GFM rendering.
/// Parent FileContentView skips this for large content; this is a secondary fallback.
struct MarkdownPreviewView: View {
    let text: String
    let state: AppState
    let markdownFilePath: String?
    let workspaceDirectory: String?
    var onRefresh: (() -> Void)? = nil
    @State private var resolvedPreviewText: String?

    private static let maxLineLength = 5000
    private static let maxTotalLength = 60_000

    static func maxLineLength(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
    }

    private var useRawTextFallback: Bool {
        return text.count > Self.maxTotalLength || Self.maxLineLength(in: text) > Self.maxLineLength
    }

    static func normalizeStandaloneImageBlocks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        var normalized: [String] = []
        normalized.reserveCapacity(lines.count)

        for index in lines.indices {
            let line = lines[index]
            normalized.append(line)

            guard isStandaloneMarkdownImageLine(line) else { continue }
            guard index + 1 < lines.count else { continue }

            let nextLine = lines[index + 1]
            if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                normalized.append("")
            }
        }

        return normalized.joined(separator: "\n")
    }

    private static func isStandaloneMarkdownImageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")") else { return false }
        guard let closeAlt = trimmed.firstIndex(of: "]") else { return false }
        let afterAlt = trimmed[trimmed.index(after: closeAlt)...]
        return afterAlt.hasPrefix("(") && !afterAlt.dropFirst().isEmpty
    }

    var body: some View {
        let previewText = Self.normalizeStandaloneImageBlocks(text)
        let displayText = resolvedPreviewText ?? previewText
        ScrollView {
            Group {
                if useRawTextFallback {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if resolvedPreviewText == nil {
                    ProgressView(L10n.t(.markdownPreviewLoading))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Markdown(
                        displayText,
                        imageBaseURL: WorkspaceMarkdownImageProvider.imageBaseURL(markdownFilePath: markdownFilePath)
                    )
                        .markdownImageProvider(
                            WorkspaceMarkdownImageProvider(
                                loadFileContent: { pathBytes in try await state.loadFileContent(pathBytes: pathBytes, workspaceDirectory: workspaceDirectory) },
                                workspaceDirectory: workspaceDirectory
                            )
                        )
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .modifier(VerticalRefresh(action: onRefresh))
        .task(id: "\(markdownFilePath ?? ""):\(previewText.hashValue)") {
            guard !useRawTextFallback else { return }
            resolvedPreviewText = nil
            let sourceText = previewText
            let resolved = await MarkdownImageResolver.resolveImages(
                in: sourceText,
                markdownFilePath: markdownFilePath,
                workspaceDirectory: workspaceDirectory,
                fetchContent: { path in try await state.loadFileContent(path: path, workspaceDirectory: workspaceDirectory) }
            )
            guard !Task.isCancelled, sourceText == Self.normalizeStandaloneImageBlocks(text) else { return }
            resolvedPreviewText = resolved
        }
    }
}

/// Raw text view for Markdown source (wraps to fill available width).
struct RawTextView: View {
    let text: String
    var monospaced: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .modifier(VerticalRefresh(action: onRefresh))
    }
}

struct ImageView: View {
    let uiImage: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(in: geometry.size)
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if scale < 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    lastScale = scale
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if scale > 1.01 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    let native = nativeScale(in: geometry.size)
                                    scale = min(max(native, 2.0), 5.0)
                                    lastScale = scale
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
        }
    }

    private func fittedImageSize(in geoSize: CGSize) -> CGSize {
        let imageSize = uiImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return geoSize }
        let ratio = min(geoSize.width / imageSize.width, geoSize.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    private func nativeScale(in geoSize: CGSize) -> CGFloat {
        let imageSize = uiImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return 2.0 }
        let fitRatio = min(geoSize.width / imageSize.width, geoSize.height / imageSize.height)
        return 1.0 / fitRatio
    }
}
