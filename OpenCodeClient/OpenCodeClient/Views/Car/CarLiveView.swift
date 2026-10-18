import SwiftUI

struct CarLiveView: View {
    @Bindable var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var expandedToolIDs: Set<String> = []
    @State private var detailsExpanded = CarLiveFixture.opensDetails

    private var snapshot: CarLiveSnapshot {
        if CarLiveFixture.isActive {
            return CarLiveFixtureSession.shared.snapshot
        }
        guard let live = state.carLive else { return .disconnected }
        return CarLiveSnapshot(controller: live)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let viewport = detailsViewport(availableHeight: proxy.size.height)
                VStack(spacing: 0) {
                    statusRail
                    transcript
                    details(viewport: viewport)
                        .layoutPriority(1)
                    controls
                        .layoutPriority(2)
                }
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.lg)
            .navigationTitle(L10n.t(.carTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .accessibilityIdentifier("car-live-root")
        .onAppear {
            state.noteCarLivePageShown()
        }
        .onDisappear {
            state.noteCarLivePageHidden()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsFixtureUpdate {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    mutateFixture { $0.updateToolResult() }
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

    /// Keeps a non-zero Details scroller when the conversation ScrollView and the
    /// control tray compete for a short landscape or large-text height.
    private func detailsViewport(availableHeight: CGFloat) -> CGFloat {
        let compact = verticalSizeClass == .compact
        let preferred: CGFloat = compact ? 112 : 240
        let floor: CGFloat = 72
        let reserved: CGFloat = compact ? 200 : 220
        let room = availableHeight - reserved
        return min(preferred, max(floor, room))
    }

    private func details(viewport: CGFloat) -> some View {
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
                .frame(minHeight: 72, idealHeight: viewport, maxHeight: viewport)
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

    private var detailsDynamicTypeSize: DynamicTypeSize {
        if CarLiveFixture.usesAccessibilityText {
            return .accessibility5
        }
        return dynamicTypeSize
    }

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            detailMetrics
            costSection
            if snapshot.usageUnconfirmed {
                Text(L10n.t(.carLiveUsageUnconfirmed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("car-live-usage-unconfirmed")
            }
        }
        .dynamicTypeSize(detailsDynamicTypeSize)
    }

    private var detailMetrics: some View {
        let voice = CarLiveDetailsFormat.voiceDuration(
            seconds: snapshot.voiceSeconds,
            known: snapshot.voiceDurationKnown,
            unconfirmed: snapshot.voiceDurationUnconfirmed
        )
        let session = CarLiveDetailsFormat.sessionDuration(seconds: snapshot.elapsedSeconds)
        let ordinary = CarLiveDetailsFormat.tokens(snapshot.inputTokens)
        let output = CarLiveDetailsFormat.tokens(snapshot.outputTokens)
        let cacheRead = CarLiveDetailsFormat.tokens(snapshot.cachedRead)
        let cacheWrite = CarLiveDetailsFormat.tokens(snapshot.cacheWrite)
        let unconfirmed = L10n.t(.carLiveUsageUnconfirmed)
        return CarLiveMetricGrid(
            accessibilityText: detailsDynamicTypeSize.isAccessibilitySize,
            spacing: DesignSpacing.sm
        ) {
            durationCell(L10n.t(.carLiveVoiceDuration), voice, fallback: unconfirmed, id: "car-live-voice-seconds")
            durationCell(L10n.t(.carLiveSessionDuration), session, fallback: unconfirmed, id: "car-live-session-seconds")
            tokenCell(L10n.t(.carLiveInputUsage), ordinary, id: "car-live-input-usage")
            tokenCell(L10n.t(.carLiveOutputUsage), output, id: "car-live-output-usage")
            tokenCell(L10n.t(.carLiveCacheRead), cacheRead, id: "car-live-cache-read")
            tokenCell(L10n.t(.carLiveCacheWrite), cacheWrite, id: "car-live-cache-write")
            metricCell(
                L10n.t(.carLiveInputLevel),
                value: CarLiveDetailsFormat.level(snapshot.inputLevel) ?? unconfirmed,
                exact: CarLiveDetailsFormat.level(snapshot.inputLevel) ?? unconfirmed,
                id: "car-live-input-level"
            )
            metricCell(
                L10n.t(.carLiveOutputLevel),
                value: CarLiveDetailsFormat.level(snapshot.outputLevel) ?? unconfirmed,
                exact: CarLiveDetailsFormat.level(snapshot.outputLevel) ?? unconfirmed,
                id: "car-live-output-level"
            )
        }
    }

    private var costSection: some View {
        let unconfirmed = L10n.t(.carLiveUsageUnconfirmed)
        let local = CarLiveDetailsFormat.localCost(
            usd: snapshot.localEstimatedUSD,
            unpricedCount: snapshot.localUnpricedCount
        )
        let portal = CarLiveDetailsFormat.portalCost(
            usd: snapshot.portalEstimatedUSD,
            settled: snapshot.portalSettled
        )
        return VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text(L10n.t(.carLiveCostHeading))
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("car-live-cost-heading")
            costLine(
                title: L10n.t(.carLiveLocalCostEstimate),
                presentation: local,
                unknown: unconfirmed,
                id: "car-live-cost-local"
            )
            costLine(
                title: L10n.t(.carLivePortalCostSnapshot),
                presentation: portal,
                unknown: L10n.t(.carLivePortalNoSnapshot),
                id: "car-live-cost-portal"
            )
            Text(L10n.t(.carLiveCostExplanation))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("car-live-estimate-note")
        }
    }

    private func durationCell(
        _ title: String,
        _ presentation: CarLiveDetailsFormat.DurationPresentation,
        fallback: String,
        id: String
    ) -> some View {
        let shown: String
        switch presentation {
        case .unknown:
            shown = fallback
        case .clock(let text, let unconfirmed):
            shown = unconfirmed ? "\(text) \(fallback)" : text
        }
        return metricCell(title, value: shown, exact: shown, id: id)
    }

    private func tokenCell(_ title: String, _ token: CarLiveDetailsFormat.TokenText, id: String) -> some View {
        metricCell(title, value: token.display, exact: token.exactAccessibility, id: id)
    }

    private func metricCell(_ title: String, value: String, exact: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
        .accessibilityValue(exact)
    }

    private func costLine(
        title: String,
        presentation: CarLiveDetailsFormat.CostPresentation,
        unknown: String,
        id: String
    ) -> some View {
        Text("\(title)\n\(presentation.valueText(unknown: unknown, unconfirmedLabel: L10n.t(.carLiveUsageUnconfirmed)))")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
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
        let foreground: Color = muted ? .white : DesignColors.Brand.primary
        return iconControl(
            symbol: muted ? "mic.slash" : "mic",
            label: L10n.t(muted ? .carLiveUnmute : .carLiveMute),
            identifier: "car-live-mute",
            value: muted ? "muted" : "unmuted",
            selected: muted,
            enabled: snapshot.isSessionUp,
            fill: muted ? DesignColors.Brand.primary : neutralFill,
            foreground: foreground,
            bordered: !muted,
            hidesIconAccessibility: true,
            action: toggleMute
        ) {
            CarLiveMicrophoneMeterIcon(
                inputLevel: snapshot.inputLevel,
                phase: snapshot.phase,
                isMuted: muted,
                foreground: foreground
            )
        }
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
        iconControl(
            symbol: symbol,
            label: label,
            identifier: identifier,
            value: value,
            selected: selected,
            enabled: enabled,
            fill: fill,
            foreground: foreground,
            bordered: bordered,
            role: role,
            action: action
        ) {
            Image(systemName: symbol)
        }
    }

    private func iconControl<Icon: View>(
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
        hidesIconAccessibility: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(role: role, action: action) {
            icon()
                .accessibilityIdentifier("\(identifier)-icon-\(symbol)")
                .modifier(CarLiveIconAccessibility(hidden: hidesIconAccessibility))
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

    private func toggleMute() {
        if CarLiveFixture.isActive {
            mutateFixture { $0.isMuted.toggle() }
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
            mutateFixture {
                $0.phase = .listening
                $0.errorMessage = nil
            }
            return
        }
        state.beginCarLiveConnect()
    }

    private func endVoice() async {
        if CarLiveFixture.isActive {
            mutateFixture {
                $0.phase = .idle
                $0.inputLevel = 0
                $0.outputLevel = 0
                $0.isMuted = false
            }
            return
        }
        await state.stopCarLive()
    }

    private func mutateFixture(_ change: (inout CarLiveSnapshot) -> Void) {
        var next = CarLiveFixtureSession.shared.snapshot
        change(&next)
        CarLiveFixtureSession.shared.snapshot = next
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
        voiceDurationKnown = controller.voiceDurationKnown
        voiceDurationUnconfirmed = controller.voiceDurationUnconfirmed
        localUnpricedCount = controller.backendUsage.unpricedCount
        portalSettled = controller.portalUsageSettled
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

private struct CarLiveIconAccessibility: ViewModifier {
    var hidden: Bool

    func body(content: Content) -> some View {
        if hidden {
            content.accessibilityHidden(true)
        } else {
            content
        }
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

private struct CarLiveMetricGrid: Layout {
    var accessibilityText: Bool
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measure(width: proposal.width ?? 360, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = measure(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() where index < plan.frames.count {
            let frame = plan.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: nil)
            )
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> Plan {
        let columns = max(
            1,
            CarLiveDetailsFormat.metricColumnCount(containerWidth: width, accessibilityText: accessibilityText)
        )
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var index = 0
        while index < subviews.count {
            let end = min(index + columns, subviews.count)
            var rowHeight: CGFloat = 0
            var sizes: [CGSize] = []
            for item in index..<end {
                let size = subviews[item].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
                sizes.append(size)
                rowHeight = max(rowHeight, size.height)
            }
            for column in 0..<(end - index) {
                let x = CGFloat(column) * (columnWidth + spacing)
                frames.append(CGRect(x: x, y: y, width: columnWidth, height: sizes[column].height))
            }
            y += rowHeight
            index = end
            if index < subviews.count {
                y += spacing
            }
        }
        return Plan(frames: frames, size: CGSize(width: width, height: y))
    }

    private struct Plan {
        var frames: [CGRect]
        var size: CGSize
    }
}
