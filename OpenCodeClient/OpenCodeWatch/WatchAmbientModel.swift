import Foundation
import Observation
import WatchConnectivity
import WatchKit

private enum WatchBridgeError: Error { case unreachable, timeout, protocolError, remote(String), busy(String) }

@MainActor
private final class WatchRequestWaiter {
    var continuation: CheckedContinuation<[String: Any], Error>?
    var timeout: Task<Void, Never>?
    func finish(_ result: sending Result<[String: Any], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}

/// The watch's voice.
///
/// The watch has no Speech framework — watchOS does not ship one — so it
/// cannot recognise speech locally. Its microphone streams to the paired
/// phone, which recognises the words on-device, runs the turn against the
/// user's own OpenCode server, and sends the answer back for the watch to
/// speak. No portal and no credential cross the bridge.
@MainActor
@Observable
final class WatchAmbientModel: NSObject, WCSessionDelegate {
    /// What the watch is doing right now.
    enum Phase: Equatable {
        case idle
        case listening
        case speaking
        case closing
    }

    private let audio = CarLiveAudioEngines.makeDefault()
    private let speech = WatchSpeechOutput()
    private var capture: CarLiveCaptureHandle?
    private var captureTask: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var run = ""
    private var fixture = false
    private var didActivate = false
    private var lastWCErrorCode = 0
    private var muted = false
    private var framesSent = 0

    var connecting = false
    var error: String?
    var bridgeStatus = ""
    /// The last answer, and the words shown under the microphone.
    private(set) var latestCaption = ""
    /// The microphone level, 0...1.
    private(set) var inputLevel: Double = 0
    /// True while the microphone is muted.
    private(set) var isMuted = false

    var phase: Phase { fixture ? .listening : currentPhase }
    private var currentPhase: Phase = .idle

    var status: String {
        if fixture { return String(localized: "Listening") }
        if connecting { return String(localized: "Connecting…") }
        switch currentPhase {
        case .listening: return muted ? String(localized: "Muted") : String(localized: "Listening")
        case .speaking: return String(localized: "Speaking, tap to interrupt")
        case .closing: return String(localized: "Ending voice")
        case .idle: return bridgeStatus.isEmpty ? String(localized: "Start voice") : bridgeStatus
        }
    }

    func activate() {
        guard !didActivate else { return }
        didActivate = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("WATCH_UI_FIXTURE") { fixture = true; return }
        #endif
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Starts the watch's voice.
    func start(readOnly: Bool = false) async {
        guard run.isEmpty, !connecting, currentPhase != .closing else { return }
        let owner = UUID().uuidString
        run = owner
        connecting = true
        error = nil
        do {
            var begin = WatchBridgeWire.envelope("begin", run: owner)
            begin["readOnly"] = readOnly
            let setup: [String: Any]
            do {
                setup = try await request(begin)
            } catch WatchBridgeError.busy(let previous) {
                guard run == owner, !Task.isCancelled else { throw CancellationError() }
                // The user explicitly started a new local voice session. Replace
                // only the exact leftover lease reported by the paired phone.
                begin["replacing"] = previous
                setup = try await request(begin)
            }
            guard run == owner else { await end(owner); return }
            // The phone hands back the run and nothing else: it recognises the
            // words and sends the answer, so there is no portal and no token
            // to carry.
            guard setup["run"] as? String == owner else { throw WatchBridgeError.protocolError }
            let handle = try await audio.startCapture()
            capture = handle
            audio.setLevelHandler { [weak self] input, _ in
                Task { @MainActor in self?.inputLevel = input }
            }
            captureTask = Task { [weak self] in
                await self?.forwardAudio(handle)
            }
            connecting = false
            currentPhase = .listening
            WKInterfaceDevice.current().play(.start)
            startPoll(owner)
        } catch {
            if run == owner {
                if case WatchBridgeError.unreachable = error {
                    self.error = String(localized: "iPhone unavailable. Open OpenCode on your iPhone first.")
                } else {
                    // A reply such as busy or a phone-side health failure is
                    // evidence that the companion was reached, not unreachable.
                    self.error = String(localized: "Voice session is not ready")
                }
                connecting = false
                run = ""
            }
            await end(owner)
        }
    }

    /// Stops the voice.
    func stop() async {
        let owner = run
        run = ""
        connecting = false
        currentPhase = .closing
        poll?.cancel()
        poll = nil
        captureTask?.cancel()
        captureTask = nil
        if let capture {
            await audio.stopCapture(generation: capture.generation)
        }
        capture = nil
        audio.setLevelHandler(nil)
        speech.stop()
        await end(owner)
        currentPhase = .idle
        bridgeStatus = String(localized: "Voice ended. Background work continues.")
    }

    /// Stops the current answer so the user can talk over it.
    func interruptPlayback() {
        speech.stop()
        if currentPhase == .speaking { currentPhase = .listening }
    }

    /// Mutes the microphone without ending the session.
    func setMuted(_ muted: Bool) {
        self.muted = muted
        isMuted = muted
        audio.setMuted(muted)
    }

    private func end(_ owner: String) async {
        guard !owner.isEmpty else { return }
        _ = try? await request(WatchBridgeWire.envelope("end", run: owner))
    }

    /// Streams the watch's microphone to the phone.
    private func forwardAudio(_ handle: CarLiveCaptureHandle) async {
        for await pcm in handle.frames {
            guard !run.isEmpty, !Task.isCancelled else { return }
            if muted { continue }
            framesSent += 1
            var message = WatchBridgeWire.envelope("audio", run: run)
            message["data"] = pcm
            send(message)
        }
    }

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        // Activation is asynchronous, including immediately after the first tap.
        // sendMessage from watchOS can wake the companion, so isReachable must
        // not gate the attempt.
        var waited = 0
        while WCSession.default.activationState != .activated && waited < 20 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        guard WCSession.default.activationState == .activated else {
            throw WatchBridgeError.unreachable
        }

        let waiter = WatchRequestWaiter()
        let timeoutSeconds: TimeInterval = payload["op"] as? String == "begin" ? 30 : 8
        return try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            waiter.timeout = Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                waiter.finish(.failure(WatchBridgeError.timeout))
            }
            WCSession.default.sendMessage(payload, replyHandler: { reply in
                if let error = reply["error"] as? String {
                    if error == "busy", let active = reply["activeRun"] as? String {
                        waiter.finish(.failure(WatchBridgeError.busy(active)))
                    } else {
                        waiter.finish(.failure(WatchBridgeError.remote(error)))
                    }
                } else {
                    waiter.finish(.success(reply))
                }
            }, errorHandler: { error in
                Task { @MainActor in self.lastWCErrorCode = (error as NSError).code }
                waiter.finish(.failure(WatchBridgeError.unreachable))
            })
        }
    }

    /// Sends without waiting for an answer: the microphone cannot wait for a
    /// round trip per frame.
    private func send(_ payload: [String: Any]) {
        WCSession.default.sendMessage(payload, replyHandler: { _ in }, errorHandler: { error in
            Task { @MainActor in self.lastWCErrorCode = (error as NSError).code }
        })
    }

    /// Asks the phone for the answer the engine produced.
    private func startPoll(_ owner: String) {
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.run == owner else { return }
                do {
                    let response = try await self.request(WatchBridgeWire.envelope("voice", run: owner))
                    guard self.run == owner else { return }
                    if let text = response["text"] as? String, !text.isEmpty {
                        self.latestCaption = text
                        self.currentPhase = .speaking
                        await self.speech.speak(text)
                        guard self.run == owner else { return }
                        self.currentPhase = .listening
                    }
                } catch WatchBridgeError.remote("stale_context") {
                    guard self.run == owner, !Task.isCancelled else { return }
                    self.error = "连接已变更，请重新开始语音"
                    await self.stop()
                    return
                } catch {
                    guard self.run == owner, !Task.isCancelled else { return }
                    self.bridgeStatus = "手机不可达"
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if DEBUG
    /// Writes what the watch is doing into its Documents folder, so a run on a
    /// device can be inspected without a debugger.
    func runProbe() {
        let record: [String: Any] = [
            "phase": String(describing: currentPhase),
            "framesSent": framesSent,
            "caption": latestCaption,
            "level": inputLevel,
            "speaking": speech.isSpeaking,
            "time": Date().timeIntervalSince1970
        ]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch-probe.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif
}
