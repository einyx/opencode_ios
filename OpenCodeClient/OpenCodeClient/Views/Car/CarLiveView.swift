import SwiftUI

struct CarLiveView: View {
    @Bindable var state: AppState
    @AppStorage(CarVoiceMode.storageKey) private var carVoiceModeRaw = CarVoiceMode.hostedLive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var fixture = CarLiveFixture.connectedSnapshot()
    @State private var expandedToolIDs: Set<String> = []
    @State private var detailsExpanded = false
    @State private var showNewSessionConfirmation = false
    @State private var connectTask: Task<Void, Never>?
    @State private var stopTask: Task<Void, Never>?

    private var snapshot: CarLiveSnapshot {
        if CarLiveFixture.isActive {
            return fixture
        }
        guard let live = state.carLive else { return .disconnected }
        return CarLiveSnapshot(controller: live)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusRail
                transcript
                details
                controls
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.lg)
            .navigationTitle(L10n.t(.carTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(L10n.t(.carNewSessionPrompt), isPresented: $showNewSessionConfirmation) {
                Button(L10n.t(.carNewSession), role: .destructive) {
                    Task { await confirmNewSession() }
                }
                Button(L10n.t(.commonCancel), role: .cancel) {}
            }
        }
        .accessibilityIdentifier("car-live-root")
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            guard CarLiveScenePolicy.shouldRelinquish(Self.scenePolicyPhase(phase)) else { return }
            relinquishLive()
        }
        .onDisappear {
            relinquishLive()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            modeMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showNewSessionConfirmation = true
            } label: {
                Image(systemName: "plus.message")
            }
            .accessibilityLabel(L10n.t(.carNewSession))
            .accessibilityIdentifier("car-live-new-session")
        }
        if showsFixtureUpdate {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    fixture.updateToolResult()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityIdentifier("car-live-fixture-update")
            }
        }
    }

    private var showsFixtureUpdate: Bool {
        #if DEBUG
        CarLiveFixture.isActive
        #else
        false
        #endif
    }

    private var modeMenu: some View {
        Menu {
            Button(L10n.t(.carLiveModeRealtime)) {}
            Button(L10n.t(.carLiveModeTurnByTurn)) {
                Task { await switchToTurnByTurn() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L10n.t(.carLiveModeMenuTitle))
        .accessibilityIdentifier("car-voice-mode-menu")
    }

    private var statusRail: some View {
        HStack(spacing: DesignSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("car-live-status")
            Spacer()
        }
        .padding(.top, DesignSpacing.sm)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    if snapshot.rows.isEmpty {
                        Text(L10n.t(.carLiveEmptyConversation))
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("car-live-empty")
                    } else {
                        ForEach(snapshot.rows) { row in
                            rowView(row)
                        }
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
            .accessibilityIdentifier("car-live-transcript")
            .onAppear {
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onChange(of: snapshot.followToken) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Button {
                detailsExpanded.toggle()
            } label: {
                HStack {
                    Text(L10n.t(.carLiveDetailsTitle))
                    Spacer()
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("car-live-details")
            .accessibilityValue(detailsExpanded ? "expanded" : "collapsed")

            if detailsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        detailBody
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                .accessibilityIdentifier("car-live-details-body")
            }
        }
        .padding(.vertical, DesignSpacing.sm)
    }

    private var controls: some View {
        VStack(spacing: DesignSpacing.sm) {
            if CarLivePresentation.showsError(snapshot) {
                Text(CarLivePresentation.errorLine(snapshot))
                    .font(.callout)
                    .foregroundStyle(DesignColors.Semantic.error)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("car-live-error")
            }
            VStack(spacing: DesignSpacing.sm) {
                #if os(iOS)
                CarLiveVolumeControl()
                #endif
                if showsStandaloneConnect {
                    standaloneConnect
                }
                HStack(spacing: DesignSpacing.sm) {
                    muteControl
                    stopControl
                    if showsSessionEnd {
                        endControl
                    }
                }
            }
            .padding(DesignSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: CarLiveControlMetrics.trayRadius, style: .continuous)
                    .fill(trayFill)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: CarLiveRow) -> some View {
        switch row {
        case .caption(let id, let role, let text):
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(roleLabel(role))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("car-live-caption-\(roleToken(role))-\(id)")
            }
        case .tool(let id, let name, let arguments, let status, let result):
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Button {
                    if expandedToolIDs.contains(id) {
                        expandedToolIDs.remove(id)
                    } else {
                        expandedToolIDs.insert(id)
                    }
                } label: {
                    HStack {
                        Text(name.isEmpty ? L10n.t(.carLiveToolRow) : name)
                        Spacer()
                        Text(toolStatusText(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: expandedToolIDs.contains(id) ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("car-live-tool-\(id)")
                .accessibilityLabel(toolAccessibilityLabel(name: name, status: status))
                .accessibilityValue(expandedToolIDs.contains(id) ? "expanded" : "collapsed")
                if expandedToolIDs.contains(id) {
                    Text(L10n.t(.carLiveToolArgs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(arguments)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("car-live-tool-args-\(id)")
                    Text(L10n.t(.carLiveToolResult))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(result.isEmpty ? L10n.t(.carLiveToolResultPending) : result)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("car-live-tool-result-\(id)")
                }
            }
        }
    }

    private var detailBody: some View {
        Group {
            detailRow(L10n.t(.carLiveInputLevel), String(format: "%.2f", snapshot.inputLevel), id: "car-live-input-level")
            detailRow(L10n.t(.carLiveOutputLevel), String(format: "%.2f", snapshot.outputLevel), id: "car-live-output-level")
            detailRow(L10n.t(.carLiveVoiceDuration), clock(snapshot.voiceSeconds), id: "car-live-voice-seconds")
            detailRow(L10n.t(.carLiveSessionDuration), clock(Double(snapshot.elapsedSeconds)), id: "car-live-session-seconds")
            detailRow(L10n.t(.carLiveInputUsage), "\(snapshot.inputTokens)", id: "car-live-input-usage")
            detailRow(L10n.t(.carLiveOutputUsage), "\(snapshot.outputTokens)", id: "car-live-output-usage")
            detailRow(L10n.t(.carLiveCacheRead), "\(snapshot.cachedRead)", id: "car-live-cache-read")
            detailRow(L10n.t(.carLiveCacheWrite), "\(snapshot.cacheWrite)", id: "car-live-cache-write")
            Text(L10n.t(.carLiveLocalCostEstimate, Self.money(snapshot.localEstimatedUSD)))
                .font(.callout)
                .accessibilityIdentifier("car-live-cost-local")
            Text(CarLiveBackendUsage.estimateNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("car-live-estimate-note")
            Text(portalCostText)
                .font(.callout)
                .accessibilityIdentifier("car-live-cost-portal")
            if snapshot.usageUnconfirmed {
                Text(L10n.t(.carLiveUsageUnconfirmed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("car-live-usage-unconfirmed")
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, id: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var portalCostText: String {
        guard let portal = snapshot.portalEstimatedUSD else {
            return L10n.t(.carLivePortalNoSnapshot)
        }
        return L10n.t(.carLivePortalCostSnapshot, Self.money(portal))
    }

    private var statusText: String {
        switch snapshot.phase {
        case .failed:
            return CarLivePresentation.errorLine(snapshot)
        case .closing:
            return L10n.t(.carLiveEnding)
        case .connecting:
            return L10n.t(.carLiveConnecting)
        case .idle:
            if CarLivePresentation.showsError(snapshot) {
                return CarLivePresentation.errorLine(snapshot)
            }
            return L10n.t(.settingsDisconnected)
        case .listening, .speaking:
            if snapshot.inputLevel > 0.05, snapshot.outputLevel > 0.05 {
                return L10n.t(.carLiveListeningAndSpeaking)
            }
            if snapshot.phase == .speaking || snapshot.outputLevel > 0.05 {
                return L10n.t(.carSpeaking)
            }
            return L10n.t(.carListening)
        }
    }

    private var statusColor: Color {
        switch snapshot.phase {
        case .failed:
            return DesignColors.Semantic.error
        case .connecting, .closing:
            return DesignColors.Brand.gold
        case .listening, .speaking:
            return DesignColors.Semantic.success
        case .idle:
            return snapshot.hasVisibleError ? DesignColors.Semantic.error : DesignColors.Neutral.textTertiary
        }
    }

    private var showsStandaloneConnect: Bool {
        switch snapshot.phase {
        case .idle, .failed:
            return true
        case .connecting, .listening, .speaking, .closing:
            return false
        }
    }

    private var showsSessionEnd: Bool {
        !showsStandaloneConnect
    }

    private var trayFill: Color {
        colorScheme == .dark ? DesignColors.Neutral.surfaceDark : DesignColors.Neutral.surfaceLight
    }

    private var neutralFill: Color {
        colorScheme == .dark ? DesignColors.Neutral.composerDark : Color.white
    }

    private var controlStrokeOpacity: Double {
        colorScheme == .dark ? DesignColors.Opacity.borderStrokeDark : DesignColors.Opacity.borderStroke
    }

    private var standaloneConnect: some View {
        let failed = snapshot.phase == .failed
        return iconControl(
            symbol: "phone.fill",
            label: L10n.t(failed ? .carLiveReconnect : .carLiveConnect),
            identifier: failed ? "car-live-reconnect" : "car-live-connect",
            value: nil,
            selected: false,
            enabled: true,
            fill: DesignColors.Brand.primary,
            foreground: .white,
            bordered: false,
            action: connect
        )
    }

    private var muteControl: some View {
        let muted = snapshot.isMuted
        return iconControl(
            symbol: muted ? "mic.slash" : "mic",
            label: L10n.t(muted ? .carLiveUnmute : .carLiveMute),
            identifier: "car-live-mute",
            value: muted ? "muted" : "unmuted",
            selected: muted,
            enabled: snapshot.isSessionUp,
            fill: muted ? DesignColors.Brand.primary : neutralFill,
            foreground: muted ? .white : DesignColors.Brand.primary,
            bordered: !muted,
            action: toggleMute
        )
    }

    private var stopControl: some View {
        iconControl(
            symbol: "waveform.slash",
            label: L10n.t(.carLiveInterruptPlayback),
            identifier: "car-live-interrupt",
            value: nil,
            selected: false,
            enabled: snapshot.isSessionUp,
            fill: neutralFill,
            foreground: DesignColors.Neutral.text,
            bordered: true,
            action: interrupt
        )
    }

    private var endControl: some View {
        let cancelling = snapshot.phase == .connecting
        let closing = snapshot.phase == .closing
        return iconControl(
            symbol: cancelling ? "xmark" : "phone.down.fill",
            label: L10n.t(cancelling ? .commonCancel : (closing ? .carLiveEnding : .carLiveDisconnect)),
            identifier: "car-live-close",
            value: nil,
            selected: false,
            enabled: !closing,
            fill: cancelling ? neutralFill : DesignColors.Semantic.error,
            foreground: cancelling ? DesignColors.Neutral.text : .white,
            bordered: cancelling,
            role: cancelling ? .cancel : .destructive,
            action: { Task { await endVoice() } }
        )
    }

    private func iconControl(
        symbol: String,
        label: String,
        identifier: String,
        value: String?,
        selected: Bool,
        enabled: Bool,
        fill: Color,
        foreground: Color,
        bordered: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .accessibilityIdentifier("\(identifier)-icon-\(symbol)")
        }
        .buttonStyle(
            CarLiveIconButtonStyle(
                fill: fill,
                foreground: foreground,
                bordered: bordered,
                strokeOpacity: controlStrokeOpacity
            )
        )
        .disabled(!enabled)
        .frame(maxWidth: .infinity)
        .frame(height: CarLiveControlMetrics.buttonHeight)
        .contentShape(RoundedRectangle(cornerRadius: DesignCorners.large, style: .continuous))
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .modifier(CarLiveAccessibilityValue(value: value))
        .modifier(CarLiveSelectionTrait(selected: selected))
    }

    private func roleToken(_ role: String) -> String {
        switch role {
        case "assistant":
            return "assistant"
        case "user":
            return "user"
        default:
            return "unknown"
        }
    }

    private func roleLabel(_ role: String) -> String {
        switch roleToken(role) {
        case "assistant":
            return L10n.t(.carLiveRoleAssistant)
        case "user":
            return L10n.t(.carLiveRoleUser)
        default:
            return role
        }
    }

    private func toolAccessibilityLabel(name: String, status: String) -> String {
        let title = name.isEmpty ? L10n.t(.carLiveToolRow) : name
        let statusText = toolStatusText(status)
        guard !statusText.isEmpty else { return title }
        return "\(title) \(statusText)"
    }

    private func toolStatusText(_ status: String) -> String {
        switch status {
        case "running":
            return L10n.t(.carLiveToolRunning)
        case "sent":
            return L10n.t(.carLiveToolSent)
        case "failed":
            return L10n.t(.taskNotificationFailed)
        case "dropped":
            return L10n.t(.carLiveToolDropped)
        default:
            return ""
        }
    }

    private func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func toggleMute() {
        if CarLiveFixture.isActive {
            fixture.isMuted.toggle()
            return
        }
        guard let live = state.carLive else { return }
        live.setMuted(!live.isMuted)
    }

    private func interrupt() {
        guard !CarLiveFixture.isActive else { return }
        state.carLive?.interruptPlayback()
    }

    private func connect() {
        if CarLiveFixture.isActive {
            fixture.phase = .listening
            fixture.errorMessage = nil
            return
        }
        connectTask?.cancel()
        connectTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            state.prepareCarLive()
            guard !Task.isCancelled else { return }
            await state.startCarLive()
        }
    }

    private func endVoice() async {
        if CarLiveFixture.isActive {
            fixture.phase = .idle
            fixture.inputLevel = 0
            fixture.outputLevel = 0
            fixture.isMuted = false
            return
        }
        connectTask?.cancel()
        connectTask = nil
        await state.stopCarLive()
    }

    private func confirmNewSession() async {
        if CarLiveFixture.isActive {
            fixture.captions = []
            fixture.activities = []
            fixture.errorMessage = nil
            return
        }
        await state.resetCarLiveSession()
    }

    private func switchToTurnByTurn() async {
        connectTask?.cancel()
        connectTask = nil
        if !CarLiveFixture.isActive {
            await state.stopCarLive()
        }
        carVoiceModeRaw = CarVoiceMode.turnByTurn
    }

    private static func scenePolicyPhase(_ phase: ScenePhase) -> CarLiveScenePolicy.Phase {
        switch phase {
        case .background:
            return .background
        case .inactive:
            return .inactive
        case .active:
            return .active
        @unknown default:
            return .active
        }
    }

    private func relinquishLive() {
        guard !CarLiveFixture.isActive else { return }
        connectTask?.cancel()
        connectTask = nil
        guard stopTask == nil else { return }
        stopTask = Task { @MainActor in
            await state.stopCarLive()
            stopTask = nil
        }
    }

    private static let bottomID = "car-live-bottom"
}

extension CarLiveSnapshot {
    init(controller: CarLiveController) {
        phase = controller.phase
        captions = controller.captions
        activities = controller.activities
        inputLevel = controller.inputLevel
        outputLevel = controller.outputLevel
        elapsedSeconds = controller.elapsedSeconds
        voiceSeconds = controller.voiceSeconds
        inputTokens = controller.backendUsage.inputTokens
        cachedRead = controller.backendUsage.cachedRead
        cacheWrite = controller.backendUsage.cacheWrite
        outputTokens = controller.backendUsage.outputTokens
        localEstimatedUSD = controller.backendUsage.estimatedUSD
        portalEstimatedUSD = controller.portalEstimatedUSD
        usageUnconfirmed = controller.usageUnconfirmed
        errorMessage = controller.errorMessage
        isMuted = controller.isMuted
    }
}

private enum CarLiveControlMetrics {
    static let buttonHeight: CGFloat = 72
    static let iconPointSize: CGFloat = 28
    static let trayRadius: CGFloat = 24
}

private struct CarLiveIconButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    var bordered: Bool
    var strokeOpacity: Double
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: CarLiveControlMetrics.iconPointSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: CarLiveControlMetrics.buttonHeight)
            .background {
                RoundedRectangle(cornerRadius: DesignCorners.large, style: .continuous)
                    .fill(fill)
            }
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: DesignCorners.large, style: .continuous)
                        .strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignCorners.large, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
    }
}

private struct CarLiveAccessibilityValue: ViewModifier {
    var value: String?

    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

private struct CarLiveSelectionTrait: ViewModifier {
    var selected: Bool

    func body(content: Content) -> some View {
        if selected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content.accessibilityRemoveTraits(.isSelected)
        }
    }
}
