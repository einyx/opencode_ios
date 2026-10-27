//
//  SetupPlanSheet.swift
//  OpenCodeClient
//
//  The first-run surface: one panel that explains what OpenCodex needs and
//  offers the ways to give it. Modelled on the reference's "plan your demo"
//  panel — a serif headline, one big input card, and a short grid of
//  concrete starting points — so the first thing a new user sees reads as an
//  invitation rather than a form.
//
//  Everything is decorative except the input and the suggestions; the sheet
//  never leaves the app's own accent language.
//

import SwiftUI

struct SetupPlanSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// The address the user is typing, before it becomes a host.
    @State private var address: String = ""
    @State private var isSubmitting = false
    /// How the sheet was opened, so it can hand the result to the right place.
    @State private var handoff: Handoff = .none

    enum Handoff {
        case none
        case address
        case editor
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                    headline
                    inputCard
                    suggestions
                }
                .padding(.horizontal, DesignSpacing.lg)
                .padding(.top, DesignSpacing.lg)
                .padding(.bottom, DesignSpacing.xl)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(DesignColors.Neutral.surfaceLight)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .foregroundStyle(DesignColors.Brand.primary)
                    .accessibilityIdentifier("setup-plan-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            // The serif wordmark is the identity; a hand-drawn scene at this
            // size is illegible, so the panel leads with the name.
            Text("OpenCodex")
                .font(.system(.title, design: .serif))
                .foregroundStyle(DesignColors.Neutral.text)

            Text(L10n.t(.setupPlanTitle))
                .font(.system(.title2, design: .serif))
                .foregroundStyle(DesignColors.Neutral.text)

            Text(L10n.t(.setupPlanSubtitle))
                .font(DesignTypography.body)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The input card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            TextField(L10n.t(.setupPlanAddressPlaceholder), text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(DesignTypography.body)
                .accessibilityIdentifier("setup-plan-address")

            HStack(alignment: .center, spacing: DesignSpacing.md) {
                Text(L10n.t(.setupPlanEnterToSend))
                    .font(DesignTypography.meta)
                    .foregroundStyle(DesignColors.Neutral.textSecondary)

                Spacer(minLength: 0)

                Button {
                    submitAddress()
                } label: {
                    Text(L10n.t(.setupPlanSend))
                        .font(DesignTypography.bodyProminent)
                        .foregroundStyle(canSubmit ? .white : DesignColors.Neutral.textTertiary)
                        .padding(.horizontal, DesignSpacing.lg)
                        .padding(.vertical, DesignSpacing.sm)
                        .background(
                            Capsule().fill(canSubmit
                                          ? DesignColors.Brand.primary
                                          : DesignColors.dimmedFill(DesignColors.Neutral.textSecondary))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isSubmitting)
                .accessibilityIdentifier("setup-plan-send")
            }
        }
        .padding(DesignSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignCorners.large)
                .fill(DesignColors.Neutral.surfaceLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignCorners.large)
                .strokeBorder(
                    DesignColors.stroke(of: DesignColors.Neutral.textSecondary, scheme: colorScheme),
                    lineWidth: 1
                )
        )
    }

    private var canSubmit: Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    // MARK: - Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Text(L10n.t(.setupPlanIdeasTitle))
                .font(DesignTypography.body)
                .foregroundStyle(DesignColors.Neutral.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: DesignSpacing.md),
                                GridItem(.flexible(), spacing: DesignSpacing.md)],
                      alignment: .leading, spacing: DesignSpacing.md) {
                ForEach(Suggestion.allCases) { suggestion in
                    Button {
                        apply(suggestion)
                    } label: {
                        HStack(spacing: DesignSpacing.sm) {
                            Image(systemName: suggestion.symbol)
                                .font(DesignTypography.body)
                                .foregroundStyle(DesignColors.Brand.primary)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(DesignColors.Brand.surface(for: colorScheme))
                                )
                            Text(L10n.t(suggestion.titleKey))
                                .font(DesignTypography.body)
                                .foregroundStyle(DesignColors.Neutral.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, DesignSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup-plan-suggestion-\(suggestion.identifier)")
                }
            }
        }
    }

    // MARK: - Actions

    private func apply(_ suggestion: Suggestion) {
        switch suggestion {
        case .localServer:
            address = "127.0.0.1:4096"
        case .sshTunnel:
            handoff = .editor
            dismiss()
        case .pasteCode:
            handoff = .editor
            dismiss()
        case .scanCode:
            handoff = .editor
            dismiss()
        }
    }

    private func submitAddress() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        handoff = .address
        dismiss()
    }

    /// The concrete ways to give the app a server.
    enum Suggestion: String, CaseIterable, Identifiable {
        case localServer
        case sshTunnel
        case pasteCode
        case scanCode

        var id: String { rawValue }
        var identifier: String { rawValue }

        var symbol: String {
            switch self {
            case .localServer: "server.rack"
            case .sshTunnel: "terminal"
            case .pasteCode: "doc.on.clipboard"
            case .scanCode: "qrcode.viewfinder"
            }
        }

        var titleKey: L10n.Key {
            switch self {
            case .localServer: .setupPlanIdeaLocal
            case .sshTunnel: .setupPlanIdeaSSH
            case .pasteCode: .setupPlanIdeaPaste
            case .scanCode: .setupPlanIdeaScan
            }
        }
    }
}
