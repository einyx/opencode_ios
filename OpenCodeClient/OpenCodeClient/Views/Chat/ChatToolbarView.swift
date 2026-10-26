//
//  ChatToolbarView.swift
//  OpenCodeClient
//

import SwiftUI

/// Installs the chat header controls into the enclosing navigation bar: the
/// session entry on the leading side, the quota badge and the context ring on
/// the trailing side. The session title is the bar's principal item, so the
/// whole header is one band.
struct ChatToolbarModifier: ViewModifier {
    @Bindable var state: AppState
    @Binding var showSessionList: Bool
    var showSettingsInToolbar: Bool
    var showSessionListInToolbar: Bool = true
    var onSettingsTap: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showSessionListInToolbar {
                        Button {
                            showSessionList = true
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.body)
                        }
                        .accessibilityIdentifier("chat-toolbar-session-list")
                        .accessibilityLabel(L10n.t(.sessionsTitle))
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    AIUsageQuotaButton(state: state)
                    ContextUsageButton(state: state)

                    if showSettingsInToolbar, let onSettingsTap {
                        Button {
                            onSettingsTap()
                        } label: {
                            Image(systemName: "gear")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }
    }
}

/// The model picker, moved out of the header into the chip row above the
/// composer: a session setting belongs next to the input, not in the title
/// bar.
struct ChatModelChip: View {
    @Bindable var state: AppState
    @State private var showConfigSheet = false

    var body: some View {
        Button {
            state.rebuildPickerModelItems(reason: "open")
            showConfigSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(state.selectedModel?.shortName ?? L10n.t(.configureModel))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            // Quiet by design: the send button is the only accent in the
            // composer, so the model chip reads as context, not as an action.
            .foregroundStyle(DesignColors.Neutral.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // The chip keeps its natural width; the counters next to it are the
            // ones that give way.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("chat-toolbar-model")
        .accessibilityLabel(L10n.t(.configureModel))
        .accessibilityValue(state.selectedModel?.shortName ?? L10n.t(.configureModel))
        .sheet(isPresented: $showConfigSheet) {
            ModelConfigSheet(state: state, isPresented: $showConfigSheet)
        }
    }
}

/// The todo panel entry, also a session-level chip.
struct ChatTodoChip: View {
    @Bindable var state: AppState
    @State private var showTodoPanel = false

    private var todos: [TodoItem] {
        guard let sessionID = state.currentSessionID else { return [] }
        return state.sessionTodos[sessionID] ?? []
    }

    private var badge: String {
        let total = todos.count
        guard total > 0 else { return "" }
        let completed = todos.count { $0.isCompleted }
        return "\(completed)/\(total)"
    }

    var body: some View {
        // Nothing to show without todos: an empty checklist chip is noise.
        if todos.isEmpty {
            EmptyView()
        } else {
            Button {
                showTodoPanel = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.caption)
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("chat-toolbar-todo")
            .accessibilityLabel(L10n.t(.todoPanelTitle))
            .accessibilityValue(badge)
            .popover(isPresented: $showTodoPanel) {
                NavigationStack {
                    TodoListPanel(todos: todos)
                        .navigationTitle(L10n.t(.todoPanelTitle))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.t(.appDone)) { showTodoPanel = false }
                            }
                        }
                }
                .frame(idealWidth: 320, idealHeight: 400)
            }
        }
    }
}

private struct ModelConfigSheet: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                modelSections
                agentSection
            }
            .navigationTitle(L10n.t(.configureTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone)) {
                        isPresented = false
                    }
                }
            }
            .onAppear { state.rebuildPickerModelItems(reason: "appear") }
            .onChange(of: state.modelSearchText) { _, _ in
                state.rebuildPickerModelItems(reason: "search")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var modelSections: some View {
        if state.modelShortlist.isEmpty {
            Section(L10n.t(.configureModel)) {
                settingsJumpRow(
                    title: L10n.t(.configureModelEmptyShortlist),
                    systemImage: "plus.circle.fill",
                    identifier: "configure-empty-shortlist"
                )
            }
        } else {
            Section {
                TextField(L10n.t(.configureModelSearchPlaceholder), text: $state.modelSearchText)
                    .autocorrectionDisabled()
            }
            Section(L10n.t(.configureModel)) {
                ForEach(state.pickerModelItems) { item in
                    pickerItemRow(item)
                }
            }
            if state.pickerModelItems.isEmpty {
                Section {
                    Text(L10n.t(.configureModelNoMatches))
                        .foregroundColor(.secondary)
                }
            }
            Section {
                settingsJumpRow(
                    title: L10n.t(.configureModelEditShortlist),
                    systemImage: "list.bullet.rectangle",
                    identifier: "configure-edit-shortlist"
                )
            }
        }
    }

    private func settingsJumpRow(title: String, systemImage: String, identifier: String) -> some View {
        Button {
            isPresented = false
            state.revealModelShortlistInSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title2)
            }
            .foregroundStyle(DesignColors.Brand.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var agentSection: some View {
        Section(L10n.t(.configureAgent)) {
            if state.isLoadingAgents {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if state.visibleAgents.isEmpty {
                Text(L10n.t(.configureNoAgents))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(state.visibleAgents.enumerated()), id: \.element.id) { index, agent in
                    agentRow(index: index, agent: agent)
                }
            }
        }
    }

    @ViewBuilder
    private func pickerItemRow(_ item: ModelPickerItem) -> some View {
        switch item {
        case .providerHeader(let providerID):
            providerHeaderRow(providerID)
        case .model(let index, let preset):
            modelRow(index: index, preset: preset)
        }
    }

    private func providerHeaderRow(_ providerID: String) -> some View {
        Text(state.providerDisplayNames[providerID] ?? providerID)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("model-picker-header-\(providerID)")
    }

    private func modelRow(index: Int, preset: ModelPreset) -> some View {
        Button {
            state.setSelectedModelIndex(index)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                    Text("\(state.providerDisplayNames[preset.providerID] ?? preset.providerID) / \(preset.modelID)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if state.selectedModelIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .accessibilityIdentifier("model-picker-row-\(preset.providerID)-\(preset.modelID)")
    }

    private func agentRow(index: Int, agent: AgentInfo) -> some View {
        Button {
            state.setSelectedAgentIndex(index)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.shortName)
                    if let desc = agent.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if state.selectedAgentIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundColor(DesignColors.Brand.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
    }
}

struct LayoutPreferenceMenu: View {
    @Bindable var state: AppState
    @State private var showChoices = false

    var body: some View {
        Button {
            showChoices = true
        } label: {
            Image(systemName: state.layoutPreference == .focus ? "iphone" : "rectangle.split.3x1")
                .font(.body)
                .frame(width: ComposerHitTarget.minimum, height: ComposerHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("layout-preference-menu")
        .accessibilityLabel(L10n.t(.settingsLayout))
        .confirmationDialog(L10n.t(.settingsLayout), isPresented: $showChoices, titleVisibility: .visible) {
            Button(L10n.t(.settingsLayoutAutomatic)) {
                state.layoutPreference = .automatic
            }
            Button(L10n.t(.settingsLayoutFocus)) {
                state.layoutPreference = .focus
            }
            Button(L10n.t(.commonCancel), role: .cancel) {}
        }
    }
}

extension View {
    /// Installs the chat header controls into the enclosing navigation bar.
    /// Apply it inside the navigation stack, on the stack's root content.
    func chatToolbar(
        state: AppState,
        showSessionList: Binding<Bool>,
        showSettingsInToolbar: Bool,
        showSessionListInToolbar: Bool = true,
        onSettingsTap: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ChatToolbarModifier(
                state: state,
                showSessionList: showSessionList,
                showSettingsInToolbar: showSettingsInToolbar,
                showSessionListInToolbar: showSessionListInToolbar,
                onSettingsTap: onSettingsTap
            )
        )
    }
}
