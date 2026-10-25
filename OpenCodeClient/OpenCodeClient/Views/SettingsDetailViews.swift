import SwiftUI
import VoiceFlowKit
#if canImport(UIKit)
import UIKit
#endif

struct SettingsInputVoiceView: View {
    @Bindable var state: AppState
    @State private var showStrategyHelp = false

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
                Text(L10n.t(state.isChatSpeechConfigured ? .settingsVoiceFirstFooter : .settingsVoiceFirstNeedsToken))
            }

            Section {
                Picker(L10n.t(.settingsRecordingStrategy), selection: $state.speechRecognitionEngine) {
                    Text(L10n.t(.settingsAppleOnDevice)).tag(SpeechRecognitionEngine.appleOnDevice)
                    Text(L10n.t(.settingsGPTLiveTranscribe)).tag(SpeechRecognitionEngine.gptLiveTranscribe)
                    Text(L10n.t(.settingsOpenAIRealtime)).tag(SpeechRecognitionEngine.openAIRealtime)
                    Text(L10n.t(.settingsGrokBatch)).tag(SpeechRecognitionEngine.grokBatch)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("settings-recording-strategy")
                // Apple's generative-AI guidance: people must know when their
                // input leaves the device. The cloud engines upload audio; the
                // on-device engine does not.
                Text(L10n.t(state.speechRecognitionEngine.usesVoiceFlowService
                            ? .settingsVoiceCloudDisclosure : .settingsAppleOnDeviceFooter))
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
                if state.speechRecognitionEngine.usesVoiceFlowService {
                    Button {
                        showStrategyHelp = true
                    } label: {
                        Label(L10n.t(.settingsStrategyHelp), systemImage: "info.circle")
                    }
                    .alert(Text(L10n.t(.settingsStrategyDialogTitle)), isPresented: $showStrategyHelp) {
                        Button(L10n.t(.commonOk), role: .cancel) {}
                    } message: {
                        Text(L10n.t(.settingsStrategyDialogBody))
                    }
                    TextField(L10n.t(.settingsAiBuilderBaseURL), text: $state.aiBuilderBaseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    SecureField(L10n.t(.settingsAiBuilderToken), text: $state.aiBuilderToken)
                        .textContentType(.password)
                    if state.speechRecognitionEngine == .gptLiveTranscribe {
                        TextField(L10n.t(.settingsCustomPrompt), text: $state.aiBuilderCustomPrompt, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("settings-custom-prompt")
                    }
                    TextField(L10n.t(.settingsTerminology), text: $state.aiBuilderTerminology)
                        .textContentType(.none)
                        .autocapitalization(.none)
                    HStack {
                        Button {
                            Task { await state.testAIBuilderConnection() }
                        } label: {
                            if state.isTestingAIBuilderConnection {
                                ProgressView(L10n.t(.settingsTesting))
                            } else {
                                Text(L10n.t(.settingsTestConnection))
                            }
                        }
                        .disabled(state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || state.isTestingAIBuilderConnection)
                        Spacer()
                        if state.aiBuilderConnectionOK {
                            Label(L10n.t(.commonOk), systemImage: "checkmark.circle")
                        }
                    }
                    if let error = state.aiBuilderConnectionError {
                        Text(error).font(DesignTypography.micro).foregroundStyle(DesignColors.Semantic.error)
                    }
                }
            } header: {
                Text(L10n.t(.settingsSpeechRecognition))
            } footer: {
                if state.speechRecognitionEngine.usesVoiceFlowService {
                    Text(L10n.t(.settingsTestConnectionScope))
                }
            }
        }
        .modifier(SettingsPageStyle())
        .navigationTitle(L10n.t(.settingsInputVoice))
        .dismissableKeyboard()
    }
}

struct SettingsAdvancedView: View {
    @Bindable var state: AppState
    @Binding var isCarModeEnabled: Bool

    private var supportsCarMode: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        Form {
            Section(L10n.t(.settingsLayout)) {
                Picker(L10n.t(.settingsLayout), selection: $state.layoutPreference) {
                    Text(L10n.t(.settingsLayoutAutomatic)).tag(LayoutPreference.automatic)
                    Text(L10n.t(.settingsLayoutFocus)).tag(LayoutPreference.focus)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-layout-preference")
                Text(L10n.t(.settingsLayoutFooter))
                    .font(DesignTypography.micro)
                    .foregroundStyle(.secondary)
            }
            Section {
                if supportsCarMode {
                    Toggle(L10n.t(.settingsCarMode), isOn: $isCarModeEnabled)
                        .accessibilityIdentifier("settings-car-mode-toggle")
                }
                Text(L10n.t(.settingsAIUsageDashboard))
                    .font(.subheadline.weight(.semibold))
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
            Section {
                LabeledContent(L10n.t(.capabilityHealthExportTitle),
                               value: L10n.t(state.healthExportAutoAllowIsActive
                                             ? .capabilityAllowedAutomatically
                                             : (state.healthExportPermission == .allowAlways
                                                ? .capabilityAllowedOtherHost : .capabilityAskEveryTime)))
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
        }
        .modifier(SettingsPageStyle())
        .navigationTitle(L10n.t(.settingsAdvanced))
        .dismissableKeyboard()
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
