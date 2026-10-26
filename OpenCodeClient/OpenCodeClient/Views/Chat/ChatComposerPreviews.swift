// Preview-only design explorations. Not connected to ChatTabView or a server.
#if DEBUG
import SwiftUI

/// The previews persist into an isolated defaults domain.
///
/// A preview session must never write into the developer's standard
/// defaults, and a preview that reaches for a server points at an unroutable
/// host instead of a real one (POL-PREVIEW-02).
private enum ComposerPreviewStore {
    static let isolated: UserDefaults = {
        let name = "opencode.preview.composer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("http://host.example.invalid:9", forKey: AppState.serverURLKey)
        return defaults
    }()
}

private enum ComposerPreviewStyle: String, CaseIterable, Identifiable {
    case reference = "Reference · charcoal"
    case native = "Native · glass"
    case compact = "Compact · mobile"

    var id: Self { self }
    var radius: CGFloat { self == .native ? 26 : 20 }
    var usesCharcoal: Bool { self != .native }
}

private struct ComposerConcept: View {
    let style: ComposerPreviewStyle
    @State private var text: String
    @State private var isRunning: Bool
    /// The agent and model choices live in the isolated preview store, so
    /// one choice shows the same content in all three candidates.
    @AppStorage("composer.preview.agent", store: ComposerPreviewStore.isolated) private var agent = "Build"
    @AppStorage("composer.preview.model", store: ComposerPreviewStore.isolated) private var model = "MiniMax M3.1 Flash"
    @State private var hasAttachment = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(style: ComposerPreviewStyle, text: String = "", isRunning: Bool = false) {
        self.style = style
        _text = State(initialValue: text)
        _isRunning = State(initialValue: isRunning)
    }

    private var foreground: Color {
        style.usesCharcoal ? .white : .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasAttachment {
                HStack {
                    Label("Context.swift", systemImage: "doc.text")
                        .font(DesignTypography.micro)
                    Spacer()
                    Button { hasAttachment = false } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove context attachment")
                }
            }

            TextField("Add follow-up, / for commands, @ for context…", text: $text,
                      prompt: Text("Add follow-up, / for commands, @ for context…")
                        .foregroundStyle(DesignColors.Neutral.textTertiary), axis: .vertical)
                .font(DesignTypography.body)
                // Compact adapts the controls, not the reference's roomy text area.
                .lineLimit(3...6)
                .tint(foreground)
                .accessibilityLabel("Message")
                .padding(.horizontal, DesignSpacing.xs)
                .padding(.top, DesignSpacing.sm)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 2))

            layout {
                contextControls
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button {
                    // Local state only: no message is actually sent.
                    isRunning.toggle()
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                        .font(DesignControls.composerActionIconFont.bold())
                        .frame(width: 44, height: 44)
                        .foregroundStyle(style.usesCharcoal ? DesignColors.Neutral.surfaceDark : Color(uiColor: .systemBackground))
                        .background(isRunning || !text.isEmpty ? foreground : DesignColors.dimmedFill(foreground),
                                    in: RoundedRectangle(cornerRadius: DesignCorners.medium))
                }
                .disabled(!isRunning && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isRunning ? "Stop response (preview)" : "Send message (preview)")
            }
        }
        .padding(DesignSpacing.md)
        .foregroundStyle(foreground)
        .buttonStyle(.plain)
        .background {
            let shape = RoundedRectangle(cornerRadius: style.radius)
            if style.usesCharcoal {
                shape.fill(Color(white: 0.14))
            } else if style == .native && !reduceTransparency {
                // Uses the app's actual glass treatment, including its fallback.
                Color.clear.glassSurface(cornerRadius: style.radius, interactive: true)
            } else {
                shape.fill(Color(uiColor: .secondarySystemBackground))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: style.radius)
                .strokeBorder(DesignColors.stroke(of: foreground, scheme: colorScheme), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        // Charcoal remains dark in the light-mode comparison too, including
        // placeholder and menu-label colors. Native glass follows the device.
        .environment(\.colorScheme, style.usesCharcoal ? .dark : colorScheme)
    }

    private var contextControls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))

        return layout {
            Menu {
                Button("Add sample context", systemImage: "doc.badge.plus") { hasAttachment = true }
            } label: {
                Image(systemName: "plus")
                    .font(DesignControls.composerActionIconFont)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add attachment or context")

            Menu {
                Picker("Agent", selection: $agent) {
                    Text("Build").tag("Build")
                    Text("Plan").tag("Plan")
                }
            } label: {
                selector(agent)
            }
            .accessibilityLabel("Agent: \(agent)")

            Menu {
                Picker("Model", selection: $model) {
                    Text("MiniMax M3.1 Flash").tag("MiniMax M3.1 Flash")
                    Text("GPT-6.1 Sol").tag("GPT-6.1 Sol")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(DesignTypography.micro)
                        .accessibilityHidden(true)
                    selector(model)
                }
            }
            .accessibilityLabel("Model: \(model)")
            .layoutPriority(-1)
        }
        .foregroundStyle(DesignColors.Neutral.textSecondary)
    }

    private func selector(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Image(systemName: "chevron.down")
                .font(DesignTypography.micro)
                .accessibilityHidden(true)
        }
        .font(style == .compact ? DesignTypography.meta : DesignTypography.body)
        .padding(.horizontal, DesignSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct ComposerPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The composer").font(DesignTypography.display)
                    Text("Three directions · interactive local mockups")
                        .font(DesignTypography.body)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                }

                ForEach(ComposerPreviewStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(style.rawValue).font(DesignTypography.micro.weight(.semibold)).foregroundStyle(DesignColors.Neutral.textSecondary)
                        ComposerConcept(style: style)
                    }
                }
            }
            .padding(DesignSpacing.lg)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview("Composer · compare dark") {
    ComposerPreviewGallery().preferredColorScheme(.dark)
}

#Preview("Composer · compare light") {
    ComposerPreviewGallery().preferredColorScheme(.light)
}

#Preview("Composer · drafting", traits: .sizeThatFitsLayout) {
    ComposerConcept(style: .reference, text: "Can you simplify the navigation and keep the current styling?")
        .padding(DesignSpacing.lg)
        .frame(width: 393)
        .preferredColorScheme(.dark)
}

#Preview("Composer · running", traits: .sizeThatFitsLayout) {
    ComposerConcept(style: .reference, isRunning: true)
        .padding(DesignSpacing.lg)
        .frame(width: 393)
        .preferredColorScheme(.dark)
}

#Preview("Composer · compact reference match", traits: .sizeThatFitsLayout) {
    ComposerConcept(style: .compact, isRunning: true)
        .padding(DesignSpacing.lg)
        .frame(width: 393)
        .preferredColorScheme(.dark)
}

#Preview("Composer · narrow screen", traits: .sizeThatFitsLayout) {
    ComposerConcept(style: .compact, isRunning: true)
        .padding(DesignSpacing.lg)
        .frame(width: 320)
        .preferredColorScheme(.dark)
}

#Preview("Composer · accessibility") {
    ComposerPreviewGallery()
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
#endif
