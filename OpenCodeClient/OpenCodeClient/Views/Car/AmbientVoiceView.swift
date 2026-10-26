//
//  AmbientVoiceView.swift
//  OpenCodeClient
//

import SwiftUI

/// Ambient Mode, running on the device: what you say, what your own server
/// answers, and the control to start and stop.
///
/// Everything here is local — the microphone, the recognition and the voice
/// all stay on the device. The only thing that leaves is the transcript, sent
/// to the OpenCode server the user configured.
struct AmbientVoiceView: View {
    @Bindable var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var engine: DeviceVoiceEngine { state.deviceVoice }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusRail
                conversation
                controls
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.lg)
            .navigationTitle(L10n.t(.carTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("ambient-voice-root")
        .onDisappear {
            // The microphone must not stay open behind another screen.
            Task { await engine.stop() }
        }
    }

    private var statusRail: some View {
        HStack(spacing: DesignSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(DesignTypography.microMono)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
                .accessibilityIdentifier("ambient-voice-status")
            Spacer()
        }
        .padding(.top, DesignSpacing.sm)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    if engine.entries.isEmpty, engine.transcript.isEmpty {
                        Text(L10n.t(.carLiveEmptyConversation))
                            .font(DesignTypography.display)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("ambient-voice-empty")
                    } else {
                        ForEach(engine.entries) { entry in
                            entryRow(entry)
                        }
                    }
                    if !engine.transcript.isEmpty {
                        liveRow
                    }
                    if let navigation = navigationAction {
                        navigationActionRow(navigation)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignSpacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("ambient-voice-conversation")
            .onChange(of: engine.entries.count) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private func entryRow(_ entry: AmbientVoiceEntry) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(entry.role == .you ? L10n.t(.carVoiceYou) : L10n.t(.carVoiceOpenCode))
                .font(DesignTypography.micro)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
            Text(entry.text)
                .font(DesignTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ambient-voice-entry-\(entry.role == .you ? "you" : "opencode")-\(entry.id.uuidString)")
        }
    }

    /// What the user is saying right now, before it becomes a turn.
    private var liveRow: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(L10n.t(.carVoiceYou))
                .font(DesignTypography.micro)
                .foregroundStyle(DesignColors.Neutral.textSecondary)
            Text(engine.transcript)
                .font(DesignTypography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ambient-voice-live")
        }
    }

    /// `open_navigation` is the one typed client action the agent can drive on
    /// the phone; it travels in the structured reply envelope.
    private var navigationAction: CarClientAction? {
        state.carLastResponse?.clientActions.first { action in
            if case .openNavigation = action { return true }
            return false
        }
    }

    /// The navigation request. The pin carries no information of its own, so
    /// the destination stays fully readable; the request is confirmed by
    /// voice, not by a button.
    @ViewBuilder
    private func navigationActionRow(_ action: CarClientAction) -> some View {
        if case .openNavigation(_, let destination, let waypoints) = action {
            let target = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty, target.count <= 240 {
                HStack(alignment: .top, spacing: DesignSpacing.md) {
                    Image("NavigationArt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text(target)
                            .font(DesignTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                        let stops = (waypoints ?? [])
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty && $0.count <= 240 }
                        if !stops.isEmpty {
                            Text(stops.joined(separator: " → "))
                                .font(DesignTypography.meta)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ambient-voice-navigation-action")
            }
        }
    }

    private var controls: some View {
        VStack(spacing: DesignSpacing.sm) {
            if case .failed(let message) = engine.phase {
                Text(message)
                    .font(DesignTypography.body)
                    .foregroundStyle(DesignColors.Brand.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("ambient-voice-error")
            }
            HStack(spacing: DesignSpacing.sm) {
                listenControl
                endControl
            }
            .padding(DesignSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(trayFill)
            }
        }
    }

    private var listenControl: some View {
        let listening = engine.isListening
        return Button {
            Task {
                if listening {
                    await engine.stop()
                } else {
                    await engine.start()
                }
            }
        } label: {
            Label(
                L10n.t(listening ? .carVoiceStop : .carVoiceStart),
                systemImage: listening ? "mic.fill" : "mic"
            )
            .font(DesignTypography.body)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(listening ? DesignColors.Brand.primary : DesignColors.Neutral.textSecondary)
        .accessibilityIdentifier("ambient-voice-listen")
    }

    private var endControl: some View {
        Button {
            Task {
                await engine.stop()
                await state.cancelCarInteraction()
            }
        } label: {
            Image(systemName: "phone.down.fill")
                .font(DesignTypography.display)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(DesignColors.Brand.primary)
        .accessibilityLabel(L10n.t(.carVoiceEnd))
        .accessibilityIdentifier("ambient-voice-end")
    }

    private var statusText: String {
        switch engine.phase {
        case .idle: L10n.t(.carVoiceReady)
        case .listening: L10n.t(.carVoiceListening)
        case .thinking: L10n.t(.carVoiceThinking)
        case .speaking: L10n.t(.carVoiceSpeaking)
        case .failed(let message): L10n.t(.carVoiceUnavailable, message)
        }
    }

    private var statusColor: Color {
        switch engine.phase {
        case .idle: DesignColors.Neutral.textTertiary
        case .listening, .thinking, .speaking: DesignColors.Brand.primary
        case .failed: DesignColors.Brand.gold
        }
    }

    private var trayFill: Color {
        colorScheme == .dark ? DesignColors.Neutral.surfaceDark : DesignColors.Neutral.surfaceLight
    }

    private static let bottomID = "ambient-voice-bottom"
}
