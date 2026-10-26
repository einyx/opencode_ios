//
//  FileTreeView.swift
//  OpenCodeClient
//

import SwiftUI

struct FileTreeView: View {
    @Bindable var state: AppState
    @Environment(\.effectiveLayout) private var effectiveLayout
    @State private var isLoadingChildren: Set<String> = []

    /// Force iPad split behavior (preview in middle column instead of push).
    var forceSplitPreview: Bool = false

    /// Regular workspace previews in the middle column; compact pushes.
    private var useSplitPreview: Bool {
        forceSplitPreview || effectiveLayout == .regular
    }

    var body: some View {
        Group {
            switch state.fileSearchListState {
            case .tree:
                treeList
            case .loading:
                ProgressView(L10n.t(.appLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("file-search-loading")
            case .empty:
                // The magnifier explains what was searched. The scene replaces
                // the system symbol in the content region; the copy and the
                // identifier stay as they were.
                ContentUnavailableView {
                    Label {
                        Text(L10n.t(.fileNoContent))
                    } icon: {
                        Image("SearchArt")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("file-search-empty")
            case .failed(let message):
                ContentUnavailableView(
                    L10n.t(.appError),
                    systemImage: "exclamationmark.triangle",
                    description: Text(message ?? "")
                )
                .accessibilityIdentifier("file-search-failed")
            case .results(let paths):
                searchResultList(paths)
            }
        }
        .navigationDestination(for: String.self) { path in
            FileContentView(
                state: state,
                filePath: path,
                workspaceDirectory: pinnedPushWorkspace,
                boundSessionID: nil
            )
        }
        .onAppear {
            state.discardUnownedFileSearch()
        }
        .onChange(of: state.captureHostRequestSnapshot()) { _, _ in
            state.discardUnownedFileSearch()
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
        .onChange(of: state.effectiveProjectDirectory) { _, _ in
            state.discardUnownedFileSearch()
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
    }

    private var openedWorkspaceDirectory: String {
        state.effectiveProjectDirectory ?? ""
    }

    private var pinnedPushWorkspace: String {
        state.filesNavigationWorkspace ?? openedWorkspaceDirectory
    }

    private var treeList: some View {
        List {
            if let error = state.fileStore.fileTreeError {
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Label(error, systemImage: "exclamationmark.triangle")
                    Button(L10n.t(.commonRetry)) { Task { await state.loadFileTree() } }
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("file-tree-error")
            } else if state.fileStore.isLoadingFileTree {
                ProgressView(L10n.t(.appLoading))
            } else if visibleNodes.isEmpty {
                // The hand-drawn folder is the content-region placeholder for
                // an empty workspace. It replaces the system symbol; the copy
                // ("This workspace is empty") stays the one that is localized.
                ContentUnavailableView {
                    Label {
                        Text(L10n.t(.fileTreeEmpty))
                    } icon: {
                        Image("FilesArt")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .accessibilityHidden(true)
                    }
                }
            }
            ForEach(visibleNodes, id: \.path) { item in
                if item.node.type == "directory" {
                    Button {
                        Task { await loadAndExpand(item.node.path) }
                    } label: {
                    DirectoryRow(
                        state: state,
                        node: item.node,
                        indent: item.indent,
                        isLoading: isLoadingChildren.contains(item.node.path))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.node.name)
                    .accessibilityValue(L10n.t(state.isFileExpanded(item.node.path) ? .expanded : .collapsed))
                    .accessibilityIdentifier("file-tree-row-\(item.node.path)")
                    if let error = state.fileStore.fileChildrenErrors[item.node.path] {
                        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                            Label(error, systemImage: "exclamationmark.triangle")
                            Button(L10n.t(.commonRetry)) {
                                Task { await retryChildren(item.node.path) }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } else if useSplitPreview {
                    Button {
                        openFile(item.node.path)
                    } label: {
                        FileRow(
                            node: item.node,
                            indent: item.indent,
                            status: state.fileStatusMap[item.node.path])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("file-tree-row-\(item.node.path)")
                } else {
                    NavigationLink(value: item.node.path) {
                        FileRow(
                            node: item.node,
                            indent: item.indent,
                            status: state.fileStatusMap[item.node.path])
                    }
                    .accessibilityIdentifier("file-tree-row-\(item.node.path)")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("file-tree")
        .onAppear {
            Task { await state.ensureFileRootMatchesCurrentScope() }
        }
        .refreshable {
            await state.loadFileTree()
            await state.loadFileStatus()
        }
    }

    private func searchResultList(_ paths: [String]) -> some View {
        List {
            ForEach(paths, id: \.self) { path in
                if useSplitPreview {
                    Button {
                        openFile(path)
                    } label: {
                        SearchResultRow(path: path)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("file-search-result-\(path)")
                } else {
                    NavigationLink(value: path) {
                        SearchResultRow(path: path)
                    }
                    .accessibilityIdentifier("file-search-result-\(path)")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("file-search-results")
    }

    private func openFile(_ path: String) {
        state.presentFilesColumnPreview(path: path, workspaceDirectory: openedWorkspaceDirectory)
    }

    private var visibleNodes: [TreeNodeItem] {
        func flatten(_ nodes: [FileNode], indent: Int) -> [TreeNodeItem] {
            var result: [TreeNodeItem] = []
            for node in nodes {
                result.append(TreeNodeItem(node: node, indent: indent))
                if node.type == "directory", state.isFileExpanded(node.path),
                   let children = state.cachedChildren(for: node.path) {
                    result.append(contentsOf: flatten(children, indent: indent + 1))
                }
            }
            return result
        }
        return flatten(state.visibleFileTreeRoot, indent: 0)
    }

    private func loadAndExpand(_ path: String) async {
        guard !isLoadingChildren.contains(path) else { return }
        let willExpand = !state.isFileExpanded(path)
        let cached = state.cachedChildren(for: path)
        state.toggleFileExpanded(path)
        guard willExpand, cached == nil else { return }
        isLoadingChildren.insert(path)
        _ = await state.loadFileChildren(path: path)
        isLoadingChildren.remove(path)
    }

    private func retryChildren(_ path: String) async {
        guard !isLoadingChildren.contains(path) else { return }
        isLoadingChildren.insert(path)
        _ = await state.loadFileChildren(path: path)
        isLoadingChildren.remove(path)
    }
}

private struct SearchResultRow: View {
    let path: String

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(DesignColors.Neutral.text)
            Text(path)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct TreeNodeItem {
    let node: FileNode
    let indent: Int
    var path: String { node.path }
}

struct DirectoryRow: View {
    @Bindable var state: AppState
    let node: FileNode
    let indent: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: state.isFileExpanded(node.path) ? "chevron.down" : "chevron.right")
                .font(DesignTypography.micro)
                .frame(width: 12)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Image(systemName: "folder.fill")
                .foregroundStyle(DesignColors.Brand.gold)
            Text(node.name)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, CGFloat(indent) * DesignSpacing.lg)
    }
}

struct FileRow: View {
    let node: FileNode
    let indent: Int
    let status: String?

    private var statusPresentation: (symbol: String, label: String)? {
        switch status {
        case "added": return ("plus.circle", L10n.t(.fileStatusAdded))
        case "deleted": return ("minus.circle", L10n.t(.fileStatusDeleted))
        case "modified": return ("pencil.circle", L10n.t(.fileStatusModified))
        case "untracked": return ("questionmark.circle", L10n.t(.fileStatusUntracked))
        default: return nil
        }
    }

    private var statusColor: Color {
        switch status {
        case "added": return DesignColors.Semantic.success
        case "deleted": return DesignColors.Semantic.error
        case "modified", "untracked": return DesignColors.Semantic.warning
        default: return DesignColors.Neutral.text
        }
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "chevron.right")
                .font(DesignTypography.micro)
                .opacity(0)
                .frame(width: 12)
            Image(systemName: "doc.text")
                .foregroundStyle(statusColor)
            Text(node.name)
                .font(DesignTypography.body)
                .lineLimit(1)
            Spacer()
            if let statusPresentation {
                Image(systemName: statusPresentation.symbol)
                    .accessibilityLabel(statusPresentation.label)
            }
        }
        .padding(.leading, CGFloat(indent) * DesignSpacing.lg)
        .accessibilityElement(children: .combine)
    }
}
