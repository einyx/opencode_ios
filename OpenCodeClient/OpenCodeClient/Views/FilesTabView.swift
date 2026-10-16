//
//  FilesTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct FilesTabView: View {
    @Bindable var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            FileTreeView(state: state)
                .fileSearchQueryHandlers(state: state)
            .navigationTitle(L10n.t(.navFiles))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sizeClass == .regular {
                    ToolbarItem(placement: .primaryAction) {
                        LayoutPreferenceMenu(state: state)
                    }
                }
            }
        }
    }
}

extension View {
    func fileSearchQueryHandlers(state: AppState) -> some View {
        modifier(FileSearchQueryModifier(state: state))
    }
}

private struct FileSearchQueryModifier: ViewModifier {
    @Bindable var state: AppState

    func body(content: Content) -> some View {
        if FileSearchFixture.isActive {
            content
                .searchable(
                    text: $state.fileSearchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L10n.t(.appSearchFiles)
                )
                .onSubmit(of: .search) {
                    Task { await state.submitFileSearch() }
                }
                .onChange(of: state.fileSearchQuery) { _, newValue in
                    state.fileSearchQueryChanged(newValue)
                }
        } else {
            content
                .searchable(text: $state.fileSearchQuery, prompt: L10n.t(.appSearchFiles))
                .onSubmit(of: .search) {
                    Task { await state.submitFileSearch() }
                }
                .onChange(of: state.fileSearchQuery) { _, newValue in
                    state.fileSearchQueryChanged(newValue)
                }
        }
    }
}
