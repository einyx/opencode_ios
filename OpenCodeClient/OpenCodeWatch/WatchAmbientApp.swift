import SwiftUI

@main
struct WatchAmbientApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WatchAmbientModel()
    var body: some Scene {
        WindowGroup {
            WatchAmbientView(model: model)
                .task { model.activate() }
                .onChange(of: scenePhase) { _, phase in
                    let event = phase == .active ? CarLiveLifecycleKind.watchActive :
                        (phase == .background ? CarLiveLifecycleKind.watchBackground : CarLiveLifecycleKind.watchInactive)
                    CarLiveLifecycleLog.shared.note(CarLiveLifecycleRecord(phase: "app", event: event))
                }
        }
    }
}

struct WatchAmbientView: View {
    @Bindable var model: WatchAmbientModel
    private var connected: Bool { model.phase == .listening || model.phase == .speaking }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("watch-status")
                Button {
                    if connected { model.interruptPlayback() }
                    else { Task { await model.start() } }
                } label: {
                    Image(systemName: model.phase == .speaking ? "waveform" : "mic.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(model.isMuted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(.blue.opacity(0.15 + min(model.inputLevel * 2, 0.7)), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .disabled(model.connecting || model.phase == .closing)
                .accessibilityLabel(connected ? String(localized: "Interrupt playback") : String(localized: "Start voice"))
                .accessibilityIdentifier("watch-start-interrupt")

                Text(model.latestCaption).font(.caption).lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .accessibilityIdentifier("watch-caption")
                if connected || model.connecting || model.phase == .closing {
                    HStack {
                        Button { model.setMuted(!model.isMuted) } label: {
                            Image(systemName: model.isMuted ? "mic.slash.fill" : "mic.fill")
                        }
                        .disabled(!connected)
                        .tint(model.isMuted ? .orange : .blue)
                        .accessibilityLabel(model.isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
                        .accessibilityIdentifier("watch-mute")
                        Button(role: .destructive) { Task { await model.stop() } } label: {
                            Image(systemName: "phone.down.fill")
                        }
                        .accessibilityLabel(String(localized: "End voice"))
                        .accessibilityIdentifier("watch-end")
                    }
                }
                if let error = model.error {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ambient")
    }
}
