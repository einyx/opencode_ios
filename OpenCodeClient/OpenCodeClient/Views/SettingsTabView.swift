import SwiftUI

struct SettingsTabView: View {
    @Bindable var state: AppState
    @Binding var isCarModeEnabled: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var highlightModelShortlist = false

    /// A connection check is running.
    ///
    /// The status follows the check, not the refresh that follows it: a
    /// refresh also reloads sessions, messages, diffs, todos and the file
    /// tree, and on a large project that takes far longer than the health
    /// check. Reporting "Checking…" for the whole refresh left this row
    /// spinning long after the connection was already proven.
    private var checking: Bool {
        state.isConnectionCheckInFlight
    }

    /// The diagnostic that belongs to the host that is current now. One
    /// left behind by another host says nothing about this host.
    private var currentHostDiagnostic: ConnectionDiagnostic? {
        state.currentHostConnectionDiagnostic
    }

    /// Check runs only with a host to test and no check already in flight.
    private var canCheckConnection: Bool {
        !checking && state.currentHostProfile != nil
    }

    /// The host is unreachable: the connection failed, or the app is left
    /// disconnected with an error to explain. This mirrors the two branches
    /// that render the failure copy, so the drawing never appears without the
    /// message that says why.
    private var showsOfflineArt: Bool {
        if checking { return false }
        if currentHostDiagnostic?.phase == .failed { return true }
        return state.connectionError != nil && !state.isConnected && currentHostDiagnostic == nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Text(L10n.t(.settingsTitle))
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, DesignSpacing.sm)

                    connectionSection
                    workspaceSection
                    preferencesSection

                    Section {
                        aboutIdentityRow
                        aboutLicencesLink
                    } header: {
                        sectionTitle(.settingsAbout)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 54)
                .listRowSpacing(0)
                .modifier(SettingsPageStyle())
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Text("OpenCodex")
                            .font(.system(.title2, design: .serif))
                            .foregroundStyle(SettingsStyle.foreground(scheme))
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .toolbarBackground(SettingsStyle.background(scheme), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .dismissableKeyboard()
                .refreshable { await state.refresh() }
                .onAppear { focusModelsIfNeeded(proxy) }
                .onChange(of: state.settingsFocus) { _, _ in focusModelsIfNeeded(proxy) }
                .alert(
                    L10n.t(.settingsTrustHostKeyTitle),
                    isPresented: Binding(
                        get: { state.pendingSSHHostKeyMismatch != nil },
                        set: { if !$0 { state.dismissPendingSSHHostKeyMismatch() } }
                    ),
                    presenting: state.pendingSSHHostKeyMismatch
                ) { _ in
                    Button(L10n.t(.commonCancel), role: .cancel) { state.dismissPendingSSHHostKeyMismatch() }
                    Button(L10n.t(.settingsTrustHostKeyConfirm)) {
                        Task { await state.trustPendingSSHHostKeyAndReconnect() }
                    }
                } message: { mismatch in
                    Text(L10n.t(.settingsTrustHostKeyMessage, mismatch.host, mismatch.port,
                                mismatch.expectedFingerprint, mismatch.presentedFingerprint))
                }
            }
        }
    }

    private var connectionSection: some View {
        Section {
            NavigationLink {
                HostProfilesView(state: state)
            } label: {
                HStack(spacing: DesignSpacing.md) {
                    Image(systemName: state.currentHostProfile?.transport == .sshTunnel ? "terminal" : "server.rack")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(SettingsStyle.foreground(scheme).opacity(DesignColors.Opacity.surfaceFill),
                                    in: RoundedRectangle(cornerRadius: DesignCorners.medium))
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text(state.currentHostProfile?.displayName ?? L10n.t(.hostNoHost))
                            .font(.headline)
                        Text(state.currentHostProfile?.transport.label ?? L10n.t(.hostAddToConnect))
                            .font(.caption)
                            .foregroundStyle(SettingsStyle.secondary(scheme))
                    }
                }
                .padding(.vertical, DesignSpacing.xs)
            }
            .accessibilityIdentifier("settings-current-host")

            HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
                connectionStatus
                Spacer(minLength: DesignSpacing.sm)
                Button {
                    guard !checking else { return }
                    Task { @MainActor in
                        await state.refresh()
                    }
                } label: {
                    Text(L10n.t(.settingsCheck))
                        // HIG Buttons: on this ink-tinted screen a plain borderless
                        // label is indistinguishable from body text, so the one
                        // actionable control takes the house interactive accent.
                        .fontWeight(.medium)
                        .frame(minHeight: ComposerHitTarget.minimum)
                }
                .buttonStyle(.borderless)
                // HIG: an inactive control must look inactive. The dim strength
                // comes from the shared disabled token (POL-COLOR-09).
                .tint(canCheckConnection ? DesignColors.Brand.primary
                                         : DesignColors.dimmedFill(DesignColors.Brand.primary))
                .accessibilityIdentifier("settings-test-connection")
                .disabled(!canCheckConnection)
            }

            // Host unreachable: the unplugged-plug scene states the condition
            // visually. The reason below and the Check action above stay
            // exactly as they are — the drawing states the state, it never
            // replaces the copy or the way out (HIG Feedback).
            if showsOfflineArt {
                Image("OfflineArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("settings-offline-art")
            }

            if let diagnostic = currentHostDiagnostic, diagnostic.phase == .failed, !checking {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(diagnostic.message)
                        .foregroundStyle(DesignColors.Semantic.error)
                        .accessibilityIdentifier("host-connection-diagnostic")
                    if let hint = diagnostic.recoveryHint {
                        Text(hint).foregroundStyle(SettingsStyle.secondary(scheme))
                    }
                }
                .font(.caption)
            } else if let error = state.connectionError, !checking,
                      !state.isConnected, currentHostDiagnostic == nil {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignColors.Semantic.error)
                    .accessibilityIdentifier("settings-connection-error")
            }

            NavigationLink {
                HostProfilesView(state: state)
            } label: {
                valueLabel(L10n.t(.settingsManageHosts), value: "\(state.hostProfiles.count)")
            }
            .accessibilityIdentifier("settings-manage-hosts")
        } header: {
            sectionTitle(.settingsConnection)
        }
        .listRowBackground(Color.clear)
    }

    private var connectionStatus: some View {
        let failed = currentHostDiagnostic?.phase == .failed
        let label = checking ? L10n.t(.settingsChecking)
            : L10n.t(failed ? .connectionPhaseFailed : (state.isConnected ? .settingsConnected : .settingsDisconnected))
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DesignSpacing.xs))
            : AnyLayout(HStackLayout(spacing: DesignSpacing.sm))
        return layout {
            statusLabel(label, failed: failed)
            serverVersion
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-connection-status")
    }

    private func statusLabel(_ text: String, failed: Bool) -> some View {
        HStack(spacing: DesignSpacing.sm) {
            if checking {
                ProgressView().controlSize(.small).accessibilityHidden(true)
            } else {
                Image(systemName: failed ? "exclamationmark.circle" : (state.isConnected ? "circle.fill" : "circle"))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .foregroundStyle(checking ? SettingsStyle.secondary(scheme)
                         : (failed ? DesignColors.Semantic.error
                            : (state.isConnected ? SettingsStyle.connected(scheme) : SettingsStyle.secondary(scheme))))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("host-connection-phase")
        .accessibilityLabel(L10n.t(.settingsConnection))
        .accessibilityValue(text)
    }

    @ViewBuilder private var serverVersion: some View {
        if let version = state.serverVersion, state.isConnected {
            Text("OpenCode \(version)")
                .foregroundStyle(SettingsStyle.secondary(scheme))
        }
    }

    private var workspaceSection: some View {
        Section {
            Picker(L10n.t(.settingsProjectShort), selection: Binding(
                get: { state.selectedProjectWorktree ?? "" },
                set: { state.selectedProjectWorktree = $0.isEmpty ? nil : $0 }
            )) {
                Text(L10n.t(.settingsProjectServerDefault)).tag("")
                ForEach(state.projects) { Text($0.displayName).tag($0.worktree) }
                Text(L10n.t(.settingsProjectCustomPath)).tag(AppState.customProjectSentinel)
            }
            .tint(SettingsStyle.secondary(scheme))
            .disabled(!state.isConnected || state.isLoadingProjects)
            .accessibilityIdentifier("settings-project")
            .onChange(of: state.selectedProjectWorktree) { _, _ in Task { await state.refreshSessions() } }

            if state.selectedProjectWorktree == AppState.customProjectSentinel {
                TextField(L10n.t(.settingsProjectCustomPathPlaceholder), text: $state.customProjectPath)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .onChange(of: state.customProjectPath) { _, _ in Task { await state.refreshSessions() } }
            }
            if let warning = state.projectMismatchWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(SettingsStyle.secondary(scheme))
            }

            NavigationLink {
                ModelShortlistView(state: state)
            } label: {
                valueLabel(L10n.t(.settingsModelShortlist), value: "\(state.modelShortlist.count)")
            }
            .accessibilityIdentifier("settings-model-shortlist")
            .id("settings-model-shortlist-row")
            .listRowBackground(highlightModelShortlist ? DesignColors.Brand.primary.opacity(DesignColors.Opacity.selectionFill) : Color.clear)
        } header: {
            sectionTitle(.settingsWorkspace)
        } footer: {
            Text(L10n.t(.settingsWorkspaceFooter))
                .font(.caption)
                .foregroundStyle(SettingsStyle.secondary(scheme))
        }
        .listRowBackground(Color.clear)
    }

    private var preferencesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                if typeSize.isAccessibilitySize {
                    Text(L10n.t(.settingsAppearance))
                    themePicker
                } else {
                    HStack {
                        Text(L10n.t(.settingsAppearance))
                        Spacer()
                        themePicker.frame(maxWidth: 220)
                    }
                }
            }
            Picker(L10n.t(.settingsLanguage), selection: $state.languagePreference) {
                Text(L10n.t(.settingsLanguageSystem)).tag(L10n.LanguagePreference.system)
                Text(L10n.t(.settingsLanguageEnglish)).tag(L10n.LanguagePreference.en)
                Text(L10n.t(.settingsLanguageChinese)).tag(L10n.LanguagePreference.zh)
            }
            .tint(SettingsStyle.secondary(scheme))
            .accessibilityIdentifier("settings-language")

            NavigationLink(L10n.t(.settingsInputVoice)) {
                SettingsInputVoiceView(state: state)
            }
            .accessibilityIdentifier("settings-input-voice")
            NavigationLink(L10n.t(.settingsAdvanced)) {
                SettingsAdvancedView(state: state, isCarModeEnabled: $isCarModeEnabled)
            }
            .accessibilityIdentifier("settings-advanced")
        } header: {
            sectionTitle(.settingsPreferences)
        }
        .listRowBackground(Color.clear)
    }

    private var themePicker: some View {
        Picker(L10n.t(.settingsTheme), selection: $state.themePreference) {
            Text(L10n.t(.settingsAutoTheme)).tag("auto")
            Text(L10n.t(.settingsLightTheme)).tag("light")
            Text(L10n.t(.settingsDarkTheme)).tag("dark")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("settings-appearance")
    }

    private func sectionTitle(_ key: L10n.Key) -> some View {
        Text(L10n.t(key))
            .font(.footnote.weight(.medium))
            .foregroundStyle(SettingsStyle.secondary(scheme))
            .textCase(nil)
            .padding(.top, DesignSpacing.md)
    }

    private func valueLabel(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.footnote)
                .foregroundStyle(SettingsStyle.secondary(scheme))
        } label: {
            Text(title)
        }
    }

    /// The About identity block: the hand-drawn spark next to the app name.
    ///
    /// The drawing is decoration — the name and the version carry the
    /// information, so the art is hidden from assistive technology.
    private var aboutIdentityRow: some View {
        HStack(spacing: DesignSpacing.md) {
            Image("AgentArt")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("OpenCodex")
                    .font(DesignTypography.display)
                    .foregroundStyle(SettingsStyle.foreground(scheme))
                Text(appVersion)
                    .font(DesignTypography.meta)
                    .foregroundStyle(SettingsStyle.secondary(scheme))
            }
            Spacer(minLength: DesignSpacing.sm)
        }
        .padding(.vertical, DesignSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// The licences link, with the small hand-drawn terminal as its mark.
    ///
    /// TerminalArt stays secondary here: the row is a text link into the
    /// licence notices, not a second picture to look at.
    private var aboutLicencesLink: some View {
        NavigationLink {
            OpenSourceLicencesView()
        } label: {
            HStack(spacing: DesignSpacing.md) {
                Image("TerminalArt")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(L10n.t(.settingsOpenSourceLicences))
                    .font(DesignTypography.body)
                    .foregroundStyle(SettingsStyle.foreground(scheme))
            }
        }
        .accessibilityIdentifier("settings-open-source-licences")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func focusModelsIfNeeded(_ proxy: ScrollViewProxy) {
        guard state.settingsFocus == .modelShortlist else { return }
        proxy.scrollTo("settings-model-shortlist-row", anchor: .center)
        highlightModelShortlist = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            highlightModelShortlist = false
            if state.settingsFocus == .modelShortlist { state.settingsFocus = nil }
        }
    }
}
