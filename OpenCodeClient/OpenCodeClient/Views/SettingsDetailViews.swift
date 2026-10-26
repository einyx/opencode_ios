import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsInputVoiceView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                Picker(L10n.t(.settingsComposerActionSide), selection: $state.composerActionSide) {
                    Text(L10n.t(.settingsComposerLeftHand)).tag(ComposerActionSide.left)
                    Text(L10n.t(.settingsComposerRightHand)).tag(ComposerActionSide.right)
                }
                .accessibilityIdentifier("settings-composer-action-side")
                Toggle(L10n.t(.settingsShowImageButton), isOn: $state.showImageAttachmentButton)
                    .accessibilityIdentifier("settings-show-image-button")
                Toggle(L10n.t(.settingsVoiceFirst), isOn: $state.voiceFirstInput)
                    .accessibilityIdentifier("settings-voice-first")
            } footer: {
                Text(L10n.t(.settingsVoiceFirstFooter))
            }

            Section {
                // The hand-drawn microphone belongs next to the thing it names
                // (docs/design/artwork-placement.md: "inline, beside the
                // engine picker"). It is a section illustration, not a hero:
                // a small drawing that leads the picker row. Decorative — the
                // picker's own label carries the meaning, so the drawing is
                // hidden from assistive technology.
                HStack(spacing: DesignSpacing.xs) {
                    Image("VoiceArt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    Text(L10n.t(.settingsAppleOnDevice))
                        .font(DesignTypography.body)
                }
                // Apple's generative-AI guidance: people must know when their
                // input leaves the device. Here it never does.
                Text(L10n.t(.settingsAppleOnDeviceFooter))
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.t(.settingsSpeechRecognition))
            }
        }
        .modifier(SettingsPageStyle())
        .navigationTitle(L10n.t(.settingsInputVoice))
        .dismissableKeyboard()
    }
}

/// Everything about the OpenCode server, in one place: the connection, the
/// workspace, the models, the agent's capabilities. These used to live across
/// the settings root, Input & Voice and Advanced — three menus to hunt
/// through for one subject.
struct SettingsOpenCodeView: View {
    @Bindable var state: AppState
    @Binding var isCarModeEnabled: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var highlightModelShortlist = false

    private var supportsCarMode: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        Form {

            Section {
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
                            // HIG Buttons: a plain borderless label is
                            // indistinguishable from body text, so the one
                            // actionable control takes the house accent.
                            .fontWeight(.medium)
                            .frame(minHeight: ComposerHitTarget.minimum)
                    }
                    .buttonStyle(.borderless)
                    // HIG: an inactive control must look inactive. The dim
                    // strength comes from the shared disabled token.
                    .tint(canCheckConnection ? DesignColors.Brand.primary
                                             : DesignColors.dimmedFill(DesignColors.Brand.primary))
                    .accessibilityIdentifier("settings-test-connection")
                    .disabled(!canCheckConnection)
                }

                NavigationLink {
                    HostProfilesView(state: state)
                } label: {
                    valueLabel(L10n.t(.settingsManageHosts), value: "\(state.hostProfiles.count)")
                }
                .accessibilityIdentifier("settings-manage-hosts")
            } header: {
                Text(L10n.t(.settingsConnection))
            }
            .listRowBackground(Color.clear)

            workspaceSection

            Section {
                if supportsCarMode {
                    Toggle(L10n.t(.settingsCarMode), isOn: $isCarModeEnabled)
                        .accessibilityIdentifier("settings-car-mode-toggle")
                }
                Text(L10n.t(.settingsAIUsageDashboard))
                    .font(DesignTypography.headline)
                TextField(L10n.t(.settingsAIUsageDashboardURL), text: $state.aiUsageDashboardURL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .accessibilityIdentifier("settings-ai-usage-url")
                HStack {
                    Button(L10n.t(.settingsTestConnection)) {
                        Task { await state.refreshAIUsageQuotas(force: true) }
                    }
                    .disabled(!state.isAIUsageQuotaConfigured || isLoadingQuotas)
                    .accessibilityIdentifier("settings-ai-usage-test")
                    Spacer()
                    if isLoadingQuotas {
                        ProgressView()
                    } else if state.aiUsageQuotaTestOK {
                        Label(L10n.t(.commonOk), systemImage: "checkmark.circle")
                    }
                }
                if let error = state.aiUsageQuotaError {
                    Text(error).font(DesignTypography.micro).foregroundStyle(DesignColors.Semantic.error)
                }
            } header: {
                Text(L10n.t(.settingsExperimentalFeatures))
            } footer: {
                Text(L10n.t(.settingsAIUsageDashboardFooter))
            }
            .listRowBackground(Color.clear)
            Section {
                // The hand-drawn pulse belongs next to the capability it names
                // (docs/design/artwork-placement.md: "inline illustration for
                // the section, small"). A small drawing leads the row; the
                // row keeps its text label and the drawing stays decorative.
                LabeledContent {
                    Text(L10n.t(state.healthExportAutoAllowIsActive
                              ? .capabilityAllowedAutomatically
                              : (state.healthExportPermission == .allowAlways
                                 ? .capabilityAllowedOtherHost : .capabilityAskEveryTime)))
                } label: {
                    HStack(spacing: DesignSpacing.xs) {
                        Image("HealthArt")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        Text(L10n.t(.capabilityHealthExportTitle))
                    }
                }
                if state.healthExportPermission == .allowAlways {
                    Button(L10n.t(.capabilityRevoke), role: .destructive) {
                        state.revokeHealthExportPermission()
                    }
                    .accessibilityIdentifier("capability-health-revoke")
                }
            } header: {
                Text(L10n.t(.capabilitySettingsTitle))
            } footer: {
                Text(L10n.t(.capabilitySettingsFooter))
            }
            .listRowBackground(Color.clear)
        }
        .modifier(SettingsPageStyle())
        .navigationTitle(L10n.t(.settingsOpenCode))
        .dismissableKeyboard()
    }

    // MARK: - Helpers

    /// The workspace: which project the agent works in, and the models it may use.
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
                    .font(DesignTypography.micro)
                    .foregroundStyle(SettingsStyle.secondary(scheme))
            }

            NavigationLink {
                ModelShortlistView(state: state)
            } label: {
                valueLabel(L10n.t(.settingsModelShortlist), value: "\(state.modelShortlist.count)")
            }
            .accessibilityIdentifier("settings-model-shortlist")
            .id("settings-model-shortlist-row")
            .listRowBackground(highlightModelShortlist ? DesignColors.Brand.selection(for: scheme) : Color.clear)
        } header: {
            Text(L10n.t(.settingsWorkspace))
                .font(DesignTypography.meta.weight(.medium))
                .foregroundStyle(SettingsStyle.secondary(scheme))
                .textCase(nil)
                .padding(.top, DesignSpacing.md)
        } footer: {
            Text(L10n.t(.settingsWorkspaceFooter))
                .font(DesignTypography.micro)
                .foregroundStyle(SettingsStyle.secondary(scheme))
        }
        .listRowBackground(Color.clear)
    }




    private var checking: Bool { state.isConnectionCheckInFlight }

    private var currentHostDiagnostic: ConnectionDiagnostic? {
        state.currentHostConnectionDiagnostic
    }

    private var canCheckConnection: Bool {
        !checking && state.currentHostProfile != nil
    }

    private var connectionStatus: some View {
        let failed = currentHostDiagnostic?.phase == .failed
        let label = checking ? L10n.t(.settingsChecking)
            : L10n.t(failed ? .connectionPhaseFailed : (state.isConnected ? .settingsConnected : .settingsDisconnected))
        return HStack(spacing: DesignSpacing.sm) {
            if checking {
                ProgressView().controlSize(.small).accessibilityHidden(true)
            } else {
                Image(systemName: failed ? "exclamationmark.circle" : (state.isConnected ? "circle.fill" : "circle"))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(label)
        }
        .font(DesignTypography.micro)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("host-connection-phase")
        .accessibilityLabel(L10n.t(.settingsConnection))
        .accessibilityValue(label)
    }

    private func valueLabel(_ title: String, value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(DesignTypography.meta)
                .foregroundStyle(SettingsStyle.secondary(scheme))
        } label: {
            Text(title)
        }
    }

    private var isLoadingQuotas: Bool {
        if case .loading = state.aiUsageQuotaState { return true }
        return false
    }
}

// Existing host-key and SSH help sheets are also used by HostProfilesView.
struct SSHTunnelSetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.t(.settingsSshSetupGuideBody)).textSelection(.enabled)
                }
            }
            .navigationTitle(L10n.t(.settingsSshSetupGuideTitle))
            .dismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone)) { dismiss() }
                }
            }
        }
    }
}

struct PublicKeySheet: View {
    let publicKey: String
    let onRotate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } header: {
                    Text(L10n.t(.settingsPublicKeyTitle))
                } footer: {
                    Text(L10n.t(.settingsPublicKeyFooter)).font(DesignTypography.micro)
                }
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = publicKey
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(L10n.t(copied ? .settingsPublicKeyCopied : .settingsCopyToClipboard),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(publicKey.isEmpty)
                Button(L10n.t(.settingsPublicKeyRotate), role: .destructive) {
                    onRotate()
                    dismiss()
                }
                .disabled(publicKey.isEmpty)
            }
            .navigationTitle(L10n.t(.settingsPublicKeyTitle))
            .dismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(.appDone)) { dismiss() }
                }
            }
        }
    }
}
