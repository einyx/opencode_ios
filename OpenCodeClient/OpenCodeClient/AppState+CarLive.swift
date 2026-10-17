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
        await carLive?.start(configuration: configuration)
        finishCarLiveStart(connectRun: connectRun, lease: lease)
    }

    func stopCarLive() async {
        cancelCarLiveConnect()
        let transportToken = carLiveLease?.transportToken ?? 0
        let controller = carLive
        releaseCarLiveLease()
        await closeLiveTransportThenStop(token: transportToken, controller: controller)
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
        cancelCarLiveConnect()
        let transportToken = carLiveLease?.transportToken ?? 0
        let controller = carLive
        let client = apiClient
        releaseCarLiveLease()
        Task {
            if transportToken != 0 {
                await client.retireLiveTransport(token: transportToken)
            }
            await controller?.stop()
        }
    }

    private func closeLiveTransportThenStop(token: UInt64, controller: CarLiveController?) async {
        if token != 0 {
            await apiClient.retireLiveTransport(token: token)
        }
        await controller?.stop()
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

    private func cancelCarLiveConnect() {
        carLiveConnectTask?.cancel()
        carLiveConnectTask = nil
        carLiveConnectRun = nil
    }

    private func releaseCarLiveLease() {
        carLiveEpoch &+= 1
        carLiveLease = nil
        carLivePoll?.cancel()
        carLivePoll = nil
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
        let context = CarLiveToolContext(
            trackedSessionID: binding?.sessionID,
            directory: effectiveProjectDirectory,
            startAgent: selectedAgentName,
            allows: { [weak self] in
                guard let self else { return false }
                return self.carLiveAllows(lease)
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
            startCarLivePoll(sessionID: sessionID, messageID: effect.messageID ?? "")
        }
    }

    private func startCarLivePoll(sessionID: String, messageID: String) {
        guard !messageID.isEmpty, let lease = carLiveLease else { return }
        carLivePoll?.cancel()
        carLivePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if await self.refreshCarLiveJob(sessionID: sessionID, messageID: messageID, lease: lease) {
                    return
                }
            }
        }
    }

    private func refreshCarLiveJob(sessionID: String, messageID: String, lease: CarLiveLease) async -> Bool {
        guard carLiveAllows(lease) else { return true }
        if carLiveAnnouncedMessageIDs.contains(messageID) { return true }
        let box = CarLiveAPIBox(apiClient)
        await box.bindOwner { [weak self] in
            guard let self else { return false }
            return self.carLiveAllows(lease)
        }
        await box.bindTransport(lease.transportToken)
        do {
            guard carLiveAllows(lease) else { return true }
            let snapshot = try await box.round(sessionID: sessionID, messageID: messageID)
            guard carLiveAllows(lease) else { return true }
            guard let text = CarLiveRound.commentary(snapshot) else { return false }
            guard carLiveAllows(lease) else { return true }
            carLiveAnnouncedMessageIDs.insert(messageID)
            await carLive?.appendCommentary(text)
            return true
        } catch {
            return false
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
