import SwiftUI

struct ClientCapabilityPermissionView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isResponding = false
    @Bindable var state: AppState
    let request: PendingClientCapabilityRequest

    /// What the capability actually does, in the app's own words. Deliberately
    /// not derived from the request: the reason text below comes from the
    /// requesting agent and must never be presented as the app's description.
    private var canonicalDescription: String {
        L10n.t(.capabilityHealthExportDescription)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                Label(L10n.t(.capabilityHealthExportTitle), systemImage: "heart.text.clipboard")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text(L10n.t(.capabilityWhatHappens))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(canonicalDescription)
                        .font(.body)
                }

                // The agent's stated motivation, clearly attributed so the user
                // can weigh it as a claim from the requester, not a fact about
                // what will happen.
                if let agentReason = request.action.reason, !agentReason.isEmpty {
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text(L10n.t(.capabilityAgentNote))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(agentReason)
                            .font(.callout.italic())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Text(L10n.t(.capabilityPermissionFooter))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                let actions = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: DesignSpacing.sm))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: DesignSpacing.sm))
                actions {
                    Button {
                        respond(allow: true)
                    } label: {
                        permissionButtonLabel(L10n.t(.capabilityAllowOnce))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("capability-allow-once")

                    Button {
                        respond(allow: true, always: true)
                    } label: {
                        permissionButtonLabel(L10n.t(.capabilityAllowAlways))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("capability-allow-always")

                    Button(role: .cancel) {
                        respond(allow: false)
                    } label: {
                        permissionButtonLabel(L10n.t(.commonCancel))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("capability-cancel")
                }
                .controlSize(.large)
                .disabled(isResponding)
            }
            .padding(DesignSpacing.lg)
            }
            .navigationTitle(L10n.t(.capabilityPermissionTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func respond(allow: Bool, always: Bool = false) {
        guard !isResponding else { return }
        isResponding = true
        Task {
            await state.resolveClientCapabilityPermission(allow: allow, always: always)
            isResponding = false
        }
    }

    private func permissionButtonLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}
