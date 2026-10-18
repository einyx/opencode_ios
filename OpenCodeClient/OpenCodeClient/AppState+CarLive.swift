import Foundation

struct CarLiveConnectRun: Equatable {
    var id: UUID
    var epoch: UInt64
}

extension AppState {
    func prepareCarLive() {
        if carLive == nil {
            carLive = CarLiveController()
        }
        carLive?.toolExecutor = { [weak self] call in
            guard let self else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "closed", message: "语音已关闭"))
            }
            return await self.executeCarLiveTool(call)
        }
        carLive?.onCommentaryAppended = { [weak self] eventID in
            self?.carLiveReplies.noteAppended(eventID)
        }
    }

    func beginCarLiveConnect() {
        cancelCarLiveConnect()
        carLiveEpoch &+= 1
        let run = CarLiveConnectRun(id: UUID(), epoch: carLiveEpoch)
        carLiveConnectRun = run
        carLiveConnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.ownsCarLiveConnect(run), !Task.isCancelled else { return }
            self.prepareCarLive()
            guard self.ownsCarLiveConnect(run), !Task.isCancelled else { return }
            await self.startCarLive(connectRun: run)
        }
    }

    func noteCarLivePageHidden() {}

    func noteCarLivePageShown() {}

    func startCarLive() async {
        await startCarLive(connectRun: nil)
    }

    private func startCarLive(connectRun: CarLiveConnectRun?) async {
        prepareCarLive()
        if let connectRun, !ownsCarLiveConnect(connectRun) { return }
        guard !Task.isCancelled else { return }
        guard isConnected else {
            rejectCarLiveStart(L10n.t(.carNotConnected))
            return
        }
        guard let portal = carLivePortalURL() else {
            rejectCarLiveStart(L10n.t(.errorInvalidBaseURL))
            return
        }
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            rejectCarLiveStart(L10n.t(.errorAiBuilderTokenEmpty))
            return
        }
        let host = captureHostRequestSnapshot()
        let contextKey = carContextKey
        guard isConnected, isCurrentHostRequest(host) else {
            rejectCarLiveStart(L10n.t(.carNotConnected))
            return
        }
        let transportToken = await apiClient.armLiveTransport()
        if let connectRun, !ownsCarLiveConnect(connectRun) || Task.isCancelled {
            await apiClient.retireLiveTransport(token: transportToken)
            return
        }
        guard !Task.isCancelled else {
            await apiClient.retireLiveTransport(token: transportToken)
            return
        }
        guard isConnected, isCurrentHostRequest(host), carLiveContextMatches(contextKey) else {
            await apiClient.retireLiveTransport(token: transportToken)
            rejectCarLiveStart(L10n.t(.carNotConnected))
            return
        }
        if let pause = carLiveBeforeLease {
            await pause()
        }
        if let connectRun, !ownsCarLiveConnect(connectRun) || Task.isCancelled {
            await apiClient.retireLiveTransport(token: transportToken)
            return
        }
        carLive?.errorMessage = nil
        let epoch: UInt64
        if let connectRun {
            epoch = connectRun.epoch
        } else {
            carLiveEpoch &+= 1
            epoch = carLiveEpoch
        }
        let ownerToken = UUID().uuidString
        let lease = CarLiveLease(
            hostID: currentHostProfileID,
            generation: hostRequestGeneration,
            contextKey: contextKey,
            epoch: epoch,
            ownerToken: ownerToken,
            transportToken: transportToken
        )
        carLiveLease = lease
        let configuration = carLiveConfiguration(portal: portal, token: token, ownerToken: ownerToken)
        bindBackgroundVoiceHold(epoch: backgroundVoiceEpoch)
        let ended = carLive?.onLiveEnded
        let endedOwner = ownerToken
        let endedEpoch = epoch
        let endedTransport = transportToken
        carLive?.onLiveEnded = { [weak self] token in
            ended?(token)
            self?.noteNaturalLiveEnded(ownerToken: endedOwner, epoch: endedEpoch, transportToken: endedTransport, endedToken: token)
        }
        await carLive?.start(configuration: configuration)
        finishCarLiveStart(connectRun: connectRun, lease: lease)
    }

    func stopCarLive() async {
        let epoch = backgroundVoiceEpoch
        let requestedAt = ContinuousClock.now
        cancelCarLiveConnect()
        let transportToken = carLiveLease?.transportToken ?? 0
        let controller = carLive
        releaseCarLiveLease()
        await closeLiveTransportThenStop(token: transportToken, controller: controller, requestedAt: requestedAt)
        releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: epoch)
    }

    func resetCarLiveSession() async {
        let owned = carLiveLease
        let contextKey = owned?.contextKey ?? carContextKey
        closeCarLiveNow()
        guard carLiveLease == nil else { return }
        carLiveBindingsByContext.removeValue(forKey: contextKey)
        persistCarLiveBindings()
        guard carLiveLease == nil else { return }
        await carLive?.resetConversation()
    }

    func closeCarLiveNow() {
        let epoch = backgroundVoiceEpoch
        let requestedAt = ContinuousClock.now
        noteCarLiveCloseRequested(requestedAt)
        cancelCarLiveConnect()
        let transportToken = carLiveLease?.transportToken ?? 0
        let controller = carLive
        let client = apiClient
        releaseCarLiveLease()
        Task {
            if transportToken != 0 {
                await client.retireLiveTransport(token: transportToken)
            }
            await controller?.stop(requestedAt: requestedAt)
        }
        releaseBackgroundNetworkAfterLiveEnd(expectedEpoch: epoch)
    }

    private func closeLiveTransportThenStop(token: UInt64, controller: CarLiveController?, requestedAt: ContinuousClock.Instant) async {
        if token != 0 {
            await apiClient.retireLiveTransport(token: token)
        }
        await controller?.stop(requestedAt: requestedAt)
    }

    private func noteCarLiveCloseRequested(_ requestedAt: ContinuousClock.Instant) {
        CarLiveLifecycleLog.shared.note(CarLiveLifecycleRecord(
            phase: carLive?.phase.rawValue ?? "idle",
            event: CarLiveLifecycleKind.appClose,
            errorCode: "none",
            closeBegan: true,
            deadlineRemainingMS: CarLiveCloseBudget.remainingMS(
                now: .now,
                deadline: requestedAt.advanced(by: .seconds(CarLiveProtocol.closeGrace))
            )
        ))
    }

    private func ownsCarLiveConnect(_ run: CarLiveConnectRun) -> Bool {
        carLiveConnectRun == run && carLiveEpoch == run.epoch
    }

    private func finishCarLiveStart(connectRun: CarLiveConnectRun?, lease: CarLiveLease) {
        if let connectRun, !ownsCarLiveConnect(connectRun) {
            return
        }
        guard let current = carLiveLease else { return }
        if current.hostID == lease.hostID, current.contextKey == lease.contextKey, current != lease {
            return
        }
        guard CarLiveRunOwner.shouldClose(current: current, owned: lease) else { return }
        guard carLiveAllows(lease) else {
            closeCarLiveNow()
            return
        }
    }

    func cancelCarLiveConnect() {
        carLiveConnectTask?.cancel()
        carLiveConnectTask = nil
        carLiveConnectRun = nil
    }

    private func releaseCarLiveLease() {
        carLiveEpoch &+= 1
        carLiveLease = nil
        carLiveReplies.invalidate()
    }

    private func noteNaturalLiveEnded(ownerToken: String, epoch: UInt64, transportToken: UInt64, endedToken: UInt64) {
        guard let lease = carLiveLease, lease.ownerToken == ownerToken, lease.epoch == epoch, lease.transportToken == transportToken else { return }
        guard let live = carLive, live.sessionOwnerForPolicy == ownerToken else { return }
        let current = live.runTokenForPolicy
        guard current == endedToken || current == endedToken &+ 1 else { return }
        let token = lease.transportToken
        carLiveEpoch &+= 1
        carLiveLease = nil
        carLiveReplies.invalidate()
        guard token != 0 else { return }
        let client = apiClient
        Task { await client.retireLiveTransport(token: token) }
    }

    private func rejectCarLiveStart(_ message: String) {
        prepareCarLive()
        carLive?.errorMessage = message
    }

    func executeCarLiveTool(_ call: CarLiveFunctionCall) async -> CarLiveToolResult {
        guard let lease = carLiveLease, call.ownerToken == lease.ownerToken, carLiveAllows(lease) else {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
        }
        let binding = carLiveBindingsByContext[lease.contextKey]
        if call.name == CarLiveToolName.answerPending {
            return await answerCarLivePending(call, lease: lease, sessionID: binding?.sessionID)
        }
        attachCarLiveReplyHooks()
        let context = CarLiveToolContext(
            trackedSessionID: binding?.sessionID,
            directory: effectiveProjectDirectory,
            startAgent: selectedAgentName,
            allows: { [weak self] in
                guard let self else { return false }
                return self.carLiveAllows(lease)
            },
            reserveReply: { [weak self] reservation in
                guard let self else { return }
                await self.carLiveReplies.reserve(reservation, lease: lease)
            },
            rollbackReply: { [weak self] token in
                self?.carLiveReplies.rollback(token)
            }
        )
        let box = CarLiveAPIBox(apiClient)
        await box.bindOwner { [weak self] in
            guard let self else { return false }
            return self.carLiveAllows(lease)
        }
        await box.bindTransport(lease.transportToken)
        let effect = await CarLiveToolHandler.run(call.name, arguments: call.arguments, client: box, context: context)
        guard carLiveAllows(lease) else {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
        }
        applyCarLiveEffect(effect, contextKey: lease.contextKey)
        return CarLiveToolResult(output: effect.output, acceptedSessionID: effect.poll ? effect.sessionID : nil)
    }

    func carLiveConfiguration(portal: URL, token: String, ownerToken: String) -> CarLiveConfiguration {
        CarLiveConfiguration(
            portalBaseURL: portal,
            builderToken: token,
            history: nil,
            instructions: CarLiveProtocol.instructions,
            backendInstructions: CarLiveProtocol.backendInstructions,
            voice: CarLiveProtocol.defaultVoice,
            tools: CarLiveProtocol.tools,
            toolsJSON: nil,
            ownerToken: ownerToken
        )
    }

    func carLiveAllows(_ lease: CarLiveLease) -> Bool {
        CarLiveLeaseCheck.allows(
            lease: lease,
            hostID: currentHostProfileID,
            generation: hostRequestGeneration,
            contextMatches: carLiveContextMatches(lease.contextKey),
            connected: isConnected,
            epoch: carLiveEpoch
        )
    }

    private func applyCarLiveEffect(_ effect: CarLiveToolEffect, contextKey: String) {
        if let clear = effect.clearSessionID, carLiveBindingsByContext[contextKey]?.sessionID == clear {
            carLiveBindingsByContext.removeValue(forKey: contextKey)
            persistCarLiveBindings()
        }
        if let sessionID = effect.sessionID, effect.poll {
            carLiveBindingsByContext[contextKey] = CarLiveBinding(
                sessionID: sessionID,
                messageID: effect.messageID,
                directory: effect.directory ?? "",
                model: effect.model ?? ""
            )
            persistCarLiveBindings()
            if let token = effect.prepareToken {
                carLiveReplies.accept(token)
            }
        }
    }

    private func attachCarLiveReplyHooks() {
        carLiveReplies.allows = { [weak self] lease in
            self?.carLiveAllows(lease) ?? false
        }
        carLiveReplies.page = { [weak self] sessionID, before, directory, token in
            guard let self else { throw CancellationError() }
            return try await self.apiClient.messagePageForLive(sessionID: sessionID, limit: 100, before: before, directory: directory, transportToken: token)
        }
        carLiveReplies.status = { [weak self] directory, token in
            guard let self else { throw CancellationError() }
            return try await self.apiClient.sessionStatusForLive(directory: directory, transportToken: token)
        }
        carLiveReplies.submit = { [weak self] text, eventID, owner in
            guard let self, let live = self.carLive else { return false }
            return await live.appendCommentary(text, eventID: eventID, expectedOwner: owner)
        }
        carLiveReplies.revision = { [weak self] in
            self?.statusRevision ?? 0
        }
    }

    private func answerCarLivePending(_ call: CarLiveFunctionCall, lease: CarLiveLease, sessionID: String?) async -> CarLiveToolResult {
        guard carLiveAllows(lease) else {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
        }
        guard let sessionID, !sessionID.isEmpty else {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "needs_input", message: "没有待确认项"))
        }
        guard let data = call.arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        let reply = object["permissionReply"] as? String
        if let reply, reply != "once", reply != "reject" {
            return CarLiveToolResult(output: CarLiveToolJSON.error(code: "bad_arguments", message: "参数无法解析"))
        }
        let answers = (object["answers"] as? [Any])?.compactMap { row in
            (row as? [Any])?.compactMap { $0 as? String }
        } ?? []
        let host = captureHostRequestSnapshot()
        if let permission = pendingPermissions.first(where: { $0.sessionID == sessionID }) {
            let revision = permissionRevision
            guard carLiveAllows(lease) else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
            }
            await respondPermission(permission, response: reply == "reject" ? .reject : .once)
            guard carLiveAllows(lease), isCurrentHostRequest(host) else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
            }
            guard permissionRevision != revision else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "not_confirmed", message: "答复没有确认，待确认项仍保留"))
            }
            return CarLiveToolResult(output: CarLiveToolJSON.accepted(sessionID: sessionID, messageID: "", model: ""))
        }
        if let question = pendingQuestions.first(where: { $0.sessionID == sessionID }) {
            let revision = questionRevision
            guard carLiveAllows(lease), !answers.isEmpty else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: answers.isEmpty ? "needs_input" : "stale_context", message: answers.isEmpty ? "没有可提交的回答" : "语音上下文已关闭"))
            }
            let sent = await respondQuestion(question, answers: answers)
            guard carLiveAllows(lease), isCurrentHostRequest(host) else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "stale_context", message: "语音上下文已关闭"))
            }
            guard sent, questionRevision != revision else {
                return CarLiveToolResult(output: CarLiveToolJSON.error(code: "not_confirmed", message: "答复没有确认，待确认项仍保留"))
            }
            return CarLiveToolResult(output: CarLiveToolJSON.accepted(sessionID: sessionID, messageID: "", model: ""))
        }
        return CarLiveToolResult(output: CarLiveToolJSON.error(code: "needs_input", message: "没有待确认项"))
    }

    private func carLiveContextMatches(_ captured: String) -> Bool {
        if carContextKey == captured { return true }
        guard effectiveProjectDirectory == nil,
              let known = serverCurrentProjectWorktree ?? carLastKnownServerWorktree, !known.isEmpty else { return false }
        return captured == "\(currentHostProfileID.uuidString)|__server_default__"
    }

    private func carLivePortalURL() -> URL? {
        let raw = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private func persistCarLiveBindings() {
        if carLiveBindingsByContext.isEmpty {
            defaults.removeObject(forKey: Self.carLiveBindingsByContextKey)
        } else if let data = try? JSONEncoder().encode(carLiveBindingsByContext) {
            defaults.set(data, forKey: Self.carLiveBindingsByContextKey)
        }
    }
}
