import Foundation
import Observation

@MainActor
@Observable
final class CarLiveController {
    private(set) var phase: CarLivePhase = .idle
    private(set) var captions: [CarLiveCaption] = []
    private(set) var activities: [CarLiveActivity] = []
    private var captionBook = CarLiveCaptionBook()
    private(set) var inputLevel: Double = 0
    private(set) var outputLevel: Double = 0
    private(set) var elapsedSeconds: Int = 0
    private(set) var voiceSeconds: Double = 0
    private(set) var backendUsage = CarLiveBackendUsage()
    private(set) var portalEstimatedUSD: Double?
    private(set) var usageUnconfirmed = false
    var errorMessage: String?
    var isMuted = false
    var toolExecutor: (@MainActor (CarLiveFunctionCall) async -> CarLiveToolResult)?

    private let transport: any CarLiveTransporting
    private let audio: any CarLiveAudioEngine
    private var link: (any CarLiveLink)?
    private var reader: Task<Void, Never>?
    private var audioPump: Task<Void, Never>?
    private var clock: Task<Void, Never>?
    private let closeGrace: TimeInterval
    private var runToken: UInt64 = 0
    private var captureGeneration: UInt64 = 0
    private var captureToken: UInt64 = 0
    private var closing = false
    private var draining = false
    private var stopping = false
    private var stopTask: Task<Void, Never>?
    private var stopID: UInt64 = 0
    private var closeSeen = false
    private var startedReady = false
    private var startWaiter: CheckedContinuation<Bool, Never>?
    private var sessionOwner = ""
    private var sessionExecutor: (@MainActor (CarLiveFunctionCall) async -> CarLiveToolResult)?
    private var calls = CarLiveCallBook(generation: 0)
    private var flight = CarLiveFlightBook()
    private var ledger = CarLiveUsageLedger()
    private var portal = CarLivePortalLedger()
    private var voice = CarLiveVoiceNote()
    private var clockStart: Date?
    private var barge = CarLiveBargeGate()
    private var suppressPlayback = false
    private var diagnostics = CarLiveDiagnostics()
    private let bargeSustain: TimeInterval
    private let bargeRelease: TimeInterval
    private let timeSource: CarLiveClock
    private let lifecycle: CarLiveLifecycleLog

    init(
        transport: any CarLiveTransporting = CarLiveTransport(),
        audio: (any CarLiveAudioEngine)? = nil,
        closeGrace: TimeInterval = CarLiveProtocol.closeGrace,
        bargeSustain: TimeInterval = 0.18,
        bargeRelease: TimeInterval = 0.45,
        clock: CarLiveClock = CarLiveClock(),
        lifecycle: CarLiveLifecycleLog = .shared
    ) {
        self.transport = transport
        self.audio = audio ?? CarLiveAudioEngines.makeDefault()
        self.closeGrace = closeGrace
        self.bargeSustain = bargeSustain
        self.bargeRelease = bargeRelease
        self.timeSource = clock
        self.lifecycle = lifecycle
        self.barge = CarLiveBargeGate(sustain: bargeSustain, releaseAfter: bargeRelease)
    }

    func start(configuration: CarLiveConfiguration) async {
        if link != nil {
            await stop()
        } else if phase != .idle {
            phase = .idle
            errorMessage = nil
            closing = false
        }
        runToken &+= 1
        let token = runToken
        releasePlaybackHold()
        diagnostics.reset()
        calls.bind(token)
        flight = CarLiveFlightBook()
        voice = CarLiveVoiceNote()
        voiceSeconds = 0
        elapsedSeconds = 0
        usageUnconfirmed = false
        closeSeen = false
        startedReady = false
        closing = false
        sessionOwner = configuration.ownerToken
        sessionExecutor = toolExecutor
        phase = .connecting
        errorMessage = nil
        guard !configuration.builderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await failStart(CarLiveCopy.missingToken, token: token)
            return
        }
        let granted = await audio.requestRecordPermission()
        guard token == runToken else { return }
        guard granted else {
            await failStart(CarLiveCopy.microphone, token: token)
            return
        }
        guard token == runToken else { return }
        replaceVisibleConversation(configuration.history)
        let opened: any CarLiveLink
        do {
            opened = try await transport.open(configuration)
        } catch {
            guard token == runToken else { return }
            await failStart(message(for: error), token: token)
            return
        }
        guard token == runToken else {
            await opened.close()
            return
        }
        link = opened
        reader = Task { [weak self] in
            for await event in opened.events {
                if Task.isCancelled { return }
                await self?.handle(event, token: token)
            }
        }
        let ready = await waitStarted(token: token)
        guard token == runToken else { return }
        if !ready || phase == .failed {
            if phase == .connecting {
                await failStart(CarLiveCopy.notReady, token: token)
            }
        }
    }

    func stop(requestedAt: ContinuousClock.Instant = .now) async {
        await beginStop(requestedAt: requestedAt, sendClose: true)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audio.setMuted(muted)
        let opened = link
        Task { try? await opened?.send(muted ? .mute : .unmute) }
    }

    func interruptPlayback() {
        outputLevel = 0
        if phase == .speaking { phase = .listening }
        guard phase == .listening || phase == .speaking else {
            audio.clearPlayback()
            return
        }
        let action = barge.beginManual(now: timeSource.now())
        guard action == .begin else { return }
        applyBarge(action)
    }

    func resetConversation() async {
        await stop()
        captionBook.reset(history: [])
        captions = []
        activities = []
        errorMessage = nil
    }

    func appendCommentary(_ text: String) async {
        await append(.commentary(text))
    }

    func appendThinking(_ text: String) async {
        await append(.thinking(text))
    }

    private func append(_ event: CarLiveClientEvent) async {
        guard let link, phase == .listening || phase == .speaking else {
            errorMessage = CarLiveCopy.notConnected
            return
        }
        do {
            try await link.send(event)
        } catch {
            errorMessage = CarLiveCopy.disconnected
        }
    }

    private func handle(_ event: CarLiveServerEvent, token: UInt64) async {
        guard token == runToken else { return }
        switch event {
        case .started:
            await beginAudio(token: token)
        case .outputAudio(let pcm):
            guard !closing, !pcm.isEmpty else { return }
            if suppressPlayback {
                noteDiagnostic("playback_drop")
                return
            }
            audio.enqueuePlayback(pcm)
            if phase == .listening { phase = .speaking }
        case .inputTranscript(let fragment):
            appendCaption(role: "user", fragment: fragment)
        case .outputTranscript(let fragment):
            appendCaption(role: "assistant", fragment: fragment)
        case .hosted(.functionCall(let callID, let name, let arguments)):
            guard !closing else { return }
            calls.collect(callID: callID, name: name)
            guard calls.claim(callID: callID, generation: token) == .accepted else { return }
            flight.begin()
            upsertActivity(id: callID, name: name, arguments: arguments, status: "running", result: "")
            let owner = sessionOwner
            let executor = sessionExecutor
            Task { [weak self] in
                await self?.runTool(callID: callID, name: name, arguments: arguments, owner: owner, executor: executor, token: token)
            }
        case .hosted(.lifecycle(let life)):
            calls.noteLifecycle(outputCount: life.outputCount)
            _ = ledger.record(life)
            backendUsage = ledger.usage
        case .voiceUsage(let seconds):
            voice.replace(seconds)
            voiceSeconds = voice.seconds
        case .closed(let seconds):
            voice.close(seconds)
            voiceSeconds = voice.seconds
            if voice.unconfirmed { usageUnconfirmed = true }
            closeSeen = true
            if !closing {
                Task { [weak self] in
                    await self?.finishServerClose(token: token)
                }
            }
        case .portalUsage(let requestID, let estimatedUSD, let confirmed, let status):
            portal.replace(requestID: requestID, estimatedUSD: estimatedUSD, confirmed: confirmed, status: status)
            portalEstimatedUSD = portal.total
            if !portal.settled { usageUnconfirmed = true }
        case .usageUnconfirmed:
            usageUnconfirmed = true
        case .failed(let code):
            if code == "invalid_audio" || code == "usage_unconfirmed" { return }
            if closing || closeSeen {
                closeSeen = true
                return
            }
            if code == "upstream_slow" {
                errorMessage = CarLiveCopy.rejected
                return
            }
            await failLive(code == "connection_lost" ? CarLiveCopy.disconnected : CarLiveCopy.rejected, token: token)
        case .hosted(.ignored), .ignored:
            break
        }
    }

    private func beginAudio(token: UInt64) async {
        guard phase == .connecting, token == runToken else { return }
        do {
            let handle = try await audio.startCapture()
            guard token == runToken, !closing else {
                handle.finish()
                await audio.stopCapture(generation: handle.generation)
                resumeWaiter(false)
                return
            }
            captureGeneration = handle.generation
            captureToken = token
            audio.setFailureHandler { [weak self] _ in
                Task { @MainActor in
                    await self?.failLive(CarLiveCopy.microphoneUnavailable, token: token)
                }
            }
            audio.setMuted(isMuted)
            audio.setLevelHandler { [weak self] input, output in
                Task { @MainActor in
                    guard let self, self.runToken == token else { return }
                    self.inputLevel = input
                    if output > 0 { self.outputLevel = output }
                    self.noteBarge(input: input)
                }
            }
            audio.setPlaybackIdleHandler { [weak self] in
                Task { @MainActor in
                    guard let self, self.runToken == token, self.phase == .speaking else { return }
                    self.phase = .listening
                    self.outputLevel = 0
                }
            }
            let opened = link
            audioPump = Task { [weak self] in
                for await frame in handle.frames {
                    let payload = await MainActor.run { () -> Data? in
                        guard let self, self.runToken == token, !self.closing else { return nil }
                        return self.isMuted ? CarLivePCM.silence(byteCount: frame.count) : frame
                    }
                    guard let payload, payload.count >= 2, let opened else { return }
                    do {
                        try await opened.send(.audio(payload))
                    } catch {
                        await self?.noteAudioSendFailure(token: token)
                        return
                    }
                }
            }
            if isMuted { try? await opened?.send(.mute) }
            phase = .listening
            clockStart = Date()
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.runToken == token, let clockStart = self.clockStart else { return }
                    self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(clockStart)))
                }
            }
            resumeWaiter(true)
        } catch {
            resumeWaiter(false)
            await failLive(CarLiveCopy.microphoneUnavailable, token: token)
        }
    }

    private func runTool(
        callID: String,
        name: String,
        arguments: String,
        owner: String,
        executor: (@MainActor (CarLiveFunctionCall) async -> CarLiveToolResult)?,
        token: UInt64
    ) async {
        guard runToken == token, sessionOwner == owner, !closing else {
            await finishFlight(token: token, sent: false)
            return
        }
        let call = CarLiveFunctionCall(callID: callID, name: name, arguments: arguments, ownerToken: owner)
        let result: CarLiveToolResult
        if let executor {
            result = await executor(call)
        } else {
            result = CarLiveToolResult(output: CarLiveWire.errorOutput(code: "no_executor", message: "工具没有执行"))
        }
        guard runToken == token, sessionOwner == owner else {
            await finishFlight(token: token, sent: false)
            return
        }
        if closing || link == nil {
            noteActivity(token: token, owner: owner, id: callID, name: name, arguments: arguments, status: "dropped", result: "")
            await finishFlight(token: token, sent: false)
            return
        }
        guard let link else { return }
        do {
            try await link.send(.functionOutput(callID: callID, output: result.output))
            noteActivity(token: token, owner: owner, id: callID, name: name, arguments: arguments, status: "sent", result: result.output)
            await finishFlight(token: token, sent: true)
        } catch {
            noteActivity(token: token, owner: owner, id: callID, name: name, arguments: arguments, status: "failed", result: "")
            await finishFlight(token: token, sent: false)
        }
    }

    private func noteActivity(token: UInt64, owner: String, id: String, name: String, arguments: String, status: String, result: String) {
        guard runToken == token, sessionOwner == owner else { return }
        if status == "dropped", !closing { return }
        upsertActivity(id: id, name: name, arguments: arguments, status: status, result: result)
    }

    private func noteAudioSendFailure(token: UInt64) async {
        guard runToken == token, !closing else { return }
        await failLive(CarLiveCopy.disconnected, token: token)
    }

    private func finishServerClose(token: UInt64) async {
        guard token == runToken, !closing, !draining, stopTask == nil else { return }
        noteLifecycle(CarLiveLifecycleKind.serverClose, errorCode: "none", deadline: .now)
        await beginStop(requestedAt: .now, sendClose: false)
    }

    private func stopOwnedCapture(token: UInt64) async {
        guard token == captureToken, captureGeneration != 0 else { return }
        let generation = captureGeneration
        await audio.stopCapture(generation: generation)
    }

    private func finishFlight(token: UInt64, sent: Bool) async {
        guard token == runToken else { return }
        let shouldContinue = flight.finish(outputSent: sent, accepting: !closing && calls.accepting)
        guard shouldContinue, let link else { return }
        do {
            try await link.send(.continueResponse)
        } catch {
            errorMessage = CarLiveCopy.disconnected
        }
    }

    private func waitStarted(token: UInt64) async -> Bool {
        if startedReady { return phase != .failed }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    if self.startedReady {
                        continuation.resume(returning: true)
                    } else {
                        self.startWaiter = continuation
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(CarLiveProtocol.startedDeadline))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            if !first {
                resumeWaiter(false)
            }
            return first && runToken == token && phase != .failed
        }
    }

    private func resumeWaiter(_ value: Bool) {
        startedReady = value || startedReady
        startWaiter?.resume(returning: value)
        startWaiter = nil
    }

    private func failStart(_ message: String, token: UInt64) async {
        guard token == runToken else { return }
        let ownedLink = link
        let ownedReader = reader
        resumeWaiter(false)
        await stopOwnedCapture(token: token)
        ownedReader?.cancel()
        await abandonClose(ownedLink, deadline: ContinuousClock.now.advanced(by: .seconds(closeGrace)))
        guard token == runToken else { return }
        link = nil
        phase = .failed
        errorMessage = message
        runToken &+= 1
    }

    private func failLive(_ message: String, token: UInt64) async {
        guard token == runToken, phase != .failed, phase != .idle, !closing else { return }
        let ownedLink = link
        let ownedReader = reader
        let ownedPump = audioPump
        usageUnconfirmed = true
        ownedPump?.cancel()
        clock?.cancel()
        await stopOwnedCapture(token: token)
        ownedReader?.cancel()
        await abandonClose(ownedLink, deadline: ContinuousClock.now.advanced(by: .seconds(closeGrace)))
        guard token == runToken else { return }
        link = nil
        phase = .failed
        errorMessage = message
        inputLevel = 0
        releasePlaybackHold()
        runToken &+= 1
    }

    private func message(for error: Error) -> String {
        guard let error = error as? CarLiveTransportError else {
            return CarLiveCopy.disconnected + "。" + CarLiveCopy.noFallback
        }
        switch error {
        case .missingBuilderToken:
            return CarLiveCopy.missingToken + "。" + CarLiveCopy.noFallback
        case .unauthorized:
            return CarLiveCopy.unauthorized + "。" + CarLiveCopy.noFallback
        case .forbidden:
            return CarLiveCopy.forbidden + "。" + CarLiveCopy.noFallback
        default:
            return CarLiveCopy.rejected + "。" + CarLiveCopy.noFallback
        }
    }

    private func replaceVisibleConversation(_ history: [CarLiveHistoryTurn]) {
        captionBook.reset(history: history)
        captions = captionBook.captions
        activities = []
    }

    private func appendCaption(role: String, fragment: CarLiveTranscriptFragment) {
        _ = captionBook.append(role: role, text: fragment.text, startMS: fragment.startMS, endMS: fragment.endMS)
        captions = captionBook.captions
    }

    private func upsertActivity(id: String, name: String, arguments: String, status: String, result: String) {
        if let index = activities.firstIndex(where: { $0.id == id }) {
            activities[index].status = status
            if !result.isEmpty { activities[index].result = result }
            return
        }
        captionBook.closeAll()
        let sequence = captionBook.advance()
        activities.append(
            CarLiveActivity(
                id: id,
                name: name,
                arguments: arguments,
                status: status,
                result: result,
                sequence: sequence
            )
        )
        if activities.count > 50 {
            activities.removeFirst(activities.count - 50)
        }
    }

    private func noteBarge(input: Double) {
        guard !closing, phase == .listening || phase == .speaking else { return }
        let outputActive = phase == .speaking || outputLevel > 0
        let action = barge.noteInput(level: input, outputActive: outputActive, now: timeSource.now())
        applyBarge(action)
    }

    private func applyBarge(_ action: CarLiveBargeGate.Action) {
        switch action {
        case .none:
            return
        case .begin:
            suppressPlayback = true
            audio.setPlaybackHeld(true)
            outputLevel = 0
            if phase == .speaking { phase = .listening }
            noteDiagnostic("barge_begin")
            noteDiagnostic("playback_clear")
        case .end:
            suppressPlayback = false
            audio.setPlaybackHeld(false)
            noteDiagnostic("barge_end")
        }
    }

    private func cutPlaybackOnce() {
        suppressPlayback = true
        barge.stop()
        audio.setPlaybackHeld(true)
        outputLevel = 0
    }

    private func releasePlaybackHold() {
        suppressPlayback = false
        barge.stop()
        audio.setPlaybackHeld(false)
    }

    private func noteDiagnostic(_ kind: String) {
        diagnostics.note(
            kind: kind,
            at: timeSource.now(),
            inputLevel: inputLevel,
            outputActive: phase == .speaking || outputLevel > 0,
            turnHash: turnHash()
        )
    }

    private func turnHash() -> Int {
        var hasher = Hasher()
        hasher.combine(captionBook.openID(role: "user") ?? "")
        hasher.combine(captionBook.openID(role: "assistant") ?? "")
        return hasher.finalize()
    }

    private func beginStop(requestedAt: ContinuousClock.Instant, sendClose: Bool) async {
        if stopID != 0, let existing = stopTask {
            noteLifecycle(CarLiveLifecycleKind.closeJoin, errorCode: "none", deadline: requestedAt)
            await existing.value
            return
        }
        stopID &+= 1
        let id = stopID
        let task = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            await self.performShutdown(requestedAt: requestedAt, sendClose: sendClose)
        }
        stopTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if stopID == id {
            stopTask = nil
        }
    }

    private func performShutdown(requestedAt: ContinuousClock.Instant, sendClose: Bool) async {
        guard phase != .idle || link != nil else { return }
        let token = runToken
        let deadline = requestedAt.advanced(by: .seconds(closeGrace))
        if sendClose == false {
            draining = true
        }
        stopping = true
        closing = true
        phase = .closing
        noteLifecycle(CarLiveLifecycleKind.closeBegin, errorCode: "none", deadline: deadline)
        cutPlaybackOnce()
        resumeWaiter(false)
        audioPump?.cancel()
        clock?.cancel()
        let ownedReader = reader
        let ownedLink = link
        if CarLiveCloseBudget.exceeded(now: .now, deadline: deadline) || Task.isCancelled {
            if token == runToken, !closeSeen {
                usageUnconfirmed = true
            }
            noteLifecycle(CarLiveLifecycleKind.budgetExceeded, errorCode: "budget_exceeded", deadline: deadline)
            await stopOwnedCapture(token: token)
            await releaseOwned(token: token, link: ownedLink, reader: ownedReader, deadline: .now)
            return
        }
        await stopOwnedCapture(token: token)
        if Task.isCancelled || CarLiveCloseBudget.exceeded(now: .now, deadline: deadline) {
            await finishEarly(token: token, link: ownedLink, reader: ownedReader, deadline: deadline)
            return
        }
        if sendClose, let ownedLink {
            let outcome = CarLiveSendOutcome()
            let finished = await CarLiveDeadlineHandle.run(until: deadline) {
                do {
                    try await ownedLink.send(.close)
                    outcome.mark(true)
                } catch {
                    outcome.mark(false)
                }
            }
            if token == runToken, (!finished || outcome.succeeded == false), !closeSeen {
                usageUnconfirmed = true
                noteLifecycle(CarLiveLifecycleKind.sendDeadline, errorCode: "send_timeout", deadline: deadline)
            }
        }
        if token == runToken {
            await waitForClose(token: token, deadline: deadline, exitOnCloseSeen: sendClose)
        }
        if token == runToken, !closeSeen {
            usageUnconfirmed = true
        }
        await releaseOwned(token: token, link: ownedLink, reader: ownedReader, deadline: deadline)
    }

    private func finishEarly(
        token: UInt64,
        link ownedLink: (any CarLiveLink)?,
        reader ownedReader: Task<Void, Never>?,
        deadline: ContinuousClock.Instant
    ) async {
        if token == runToken, !closeSeen {
            usageUnconfirmed = true
        }
        let code = Task.isCancelled ? "cancelled" : "budget_exceeded"
        noteLifecycle(code == "cancelled" ? CarLiveLifecycleKind.failClosed : CarLiveLifecycleKind.budgetExceeded, errorCode: code, deadline: deadline)
        await releaseOwned(token: token, link: ownedLink, reader: ownedReader, deadline: deadline)
    }

    private func waitForClose(token: UInt64, deadline: ContinuousClock.Instant, exitOnCloseSeen: Bool) async {
        while token == runToken {
            if exitOnCloseSeen, closeSeen { return }
            if Task.isCancelled {
                noteLifecycle(CarLiveLifecycleKind.failClosed, errorCode: "cancelled", deadline: deadline)
                return
            }
            if CarLiveCloseBudget.exceeded(now: .now, deadline: deadline) {
                noteLifecycle(CarLiveLifecycleKind.budgetExceeded, errorCode: "budget_exceeded", deadline: deadline)
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(20), clock: .continuous)
            } catch {
                noteLifecycle(CarLiveLifecycleKind.failClosed, errorCode: "cancelled", deadline: deadline)
                return
            }
        }
    }

    private func releaseOwned(
        token: UInt64,
        link ownedLink: (any CarLiveLink)?,
        reader ownedReader: Task<Void, Never>?,
        deadline: ContinuousClock.Instant
    ) async {
        ownedReader?.cancel()
        await abandonClose(ownedLink, deadline: deadline)
        guard token == runToken else { return }
        link = nil
        reader = nil
        audioPump = nil
        closing = false
        draining = false
        stopping = false
        closeSeen = false
        inputLevel = 0
        outputLevel = 0
        releasePlaybackHold()
        noteDiagnostic("stop")
        phase = .idle
        runToken &+= 1
        calls.bind(runToken)
        flight = CarLiveFlightBook()
        noteLifecycle(CarLiveLifecycleKind.closeEnd, errorCode: usageUnconfirmed ? "usage_unconfirmed" : "none", deadline: deadline)
    }

    private func abandonClose(_ ownedLink: (any CarLiveLink)?, deadline: ContinuousClock.Instant) async {
        guard let ownedLink else { return }
        let finished = await CarLiveDeadlineHandle.run(until: deadline) {
            await ownedLink.close()
        }
        if !finished {
            Task { await ownedLink.close() }
        }
    }

    private func noteLifecycle(_ event: String, errorCode: String, deadline: ContinuousClock.Instant) {
        lifecycle.note(CarLiveLifecycleRecord(
            runHash: CarLiveLifecycleLog.runHash(runToken),
            phase: phase.rawValue,
            event: event,
            errorCode: errorCode,
            taskCancelled: Task.isCancelled,
            closeBegan: event == CarLiveLifecycleKind.closeBegin || event == CarLiveLifecycleKind.appClose,
            closeEnded: event == CarLiveLifecycleKind.closeEnd,
            deadlineRemainingMS: CarLiveCloseBudget.remainingMS(now: .now, deadline: deadline),
            stopping: stopping,
            closeSeen: closeSeen
        ))
    }
}

private final class CarLiveSendOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var succeeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func mark(_ succeeded: Bool) {
        lock.lock()
        value = succeeded
        lock.unlock()
    }
}
