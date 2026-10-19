import SwiftUI

@main
struct WatchAmbientApp: App {
    @State private var model = WatchAmbientModel()
    var body: some Scene {
        WindowGroup {
            WatchAmbientView(model: model)
                .task { model.activate() }
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
                    if connected { model.live.interruptPlayback() }
                    else { Task { await model.start() } }
                } label: {
                    Image(systemName: model.phase == .speaking ? "waveform" : "mic.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(model.live.isMuted ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(.blue.opacity(0.15 + min(model.live.inputLevel * 2, 0.7)), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .disabled(model.connecting || model.phase == .closing)
                .accessibilityLabel(connected ? "打断" : "开始语音")
                .accessibilityIdentifier("watch-start-interrupt")

                Text(model.latestCaption).font(.caption).lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .accessibilityIdentifier("watch-caption")
                if connected || model.connecting || model.phase == .closing {
                    HStack {
                        Button { model.live.setMuted(!model.live.isMuted) } label: {
                            Image(systemName: model.live.isMuted ? "mic.slash.fill" : "mic.fill")
                        }
                        .disabled(!connected)
                        .tint(model.live.isMuted ? .orange : .blue)
                        .accessibilityLabel(model.live.isMuted ? "取消静音" : "静音")
                        .accessibilityIdentifier("watch-mute")
                        Button(role: .destructive) { Task { await model.stop() } } label: {
                            Image(systemName: "phone.down.fill")
                        }
                        .accessibilityLabel("结束语音")
                        .accessibilityIdentifier("watch-end")
                    }
                }
                if let error = model.error ?? model.live.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ambient")
    }
}
