import Foundation

private struct CarTurnTarget {
    var turnID: UUID
    var host: HostRequestSnapshot
    var contextKey: String
}

enum CarModeError: LocalizedError {
    case notConnected
    case selectedProjectUnsupported
    case invalidResponse
    case unsupportedAction
    case mapsUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected: return L10n.t(.carNotConnected)
        case .selectedProjectUnsupported: return L10n.t(.carServerDefaultRequired)
        case .invalidResponse: return L10n.t(.carInvalidResponse)
        case .unsupportedAction: return L10n.t(.carUnsupportedAction)
        case .mapsUnavailable: return L10n.t(.carMapsUnavailable)
        }
    }
}

extension AppState {
    var carContextKey: String {
        let directory = effectiveProjectDirectory ?? serverCurrentProjectWorktree ?? carLastKnownServerWorktree ?? "__server_default__"
        return "\(currentHostProfileID.uuidString)|\(directory)"
    }

    var currentCarSessionRecord: CarSessionRecord? {
        carSessionsByContext[carContextKey]
    }

    var currentCarSessionID: String? {
        currentCarSessionRecord?.sessionID
    }

    /// Runs one turn and returns the text of the answer.
    ///
    /// `speaks` decides who says it out loud: the phone speaks the answer
    /// locally, while the watch asks the phone for the text and speaks it on
    /// the wrist.
    @discardableResult
    func submitCarTurn(_ rawText: String, speaks: Bool = true) async -> String? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let turnID = UUID()
        let target = CarTurnTarget(
            turnID: turnID,
            host: captureHostRequestSnapshot(),
            contextKey: carContextKey
        )
        carActiveTurnID = turnID
        carLastTranscript = text
        carError = nil
        carPhase = .waitingReply

        do {
            guard let session = try await ensureCarSession(target) else {
                abandonCarTurnIfStillOwned(target)
                return nil
            }
            guard carTurnIsCurrent(target) else {
                abandonCarTurnIfStillOwned(target)
                return nil
            }
            let response = try await apiClient.promptStructured(
                sessionID: session.id,
                text: text,
                system: CarModeProtocol.systemPrompt,
                format: CarModeProtocol.outputFormat,
                agent: "build",
                model: CarModeProtocol.model
            )
            guard carTurnIsCurrent(target) else {
                abandonCarTurnIfStillOwned(target)
                return nil
            }
            return try await handleCarResponse(response, sessionID: session.id, target: target, speaks: speaks)
        } catch {
            guard carTurnIsCurrent(target) else {
                abandonCarTurnIfStillOwned(target)
                return nil
            }
            carError = error.localizedDescription
            carPhase = .failed
            carActiveTurnID = nil
            return nil
        }
    }

    func cancelCarInteraction() async {
        let sessionID = currentCarSessionID
        let shouldAbort = carActiveTurnID != nil
        if let callbackID = carActiveCapabilityCallbackID {
            try? clientCapabilityStore.removeOutbox(callbackID: callbackID)
        }
        carActiveTurnID = nil
        carActiveCapabilityCallbackID = nil
        carSpeechOutput.stop()
        carPhase = .idle
        if shouldAbort, let sessionID {
            try? await apiClient.abort(sessionID: sessionID)
        }
    }

    func startNewCarSession() async {
        closeCarLiveNow()
        await cancelCarInteraction()
        carSessionsByContext.removeValue(forKey: carContextKey)
        persistCarSessions()
        carLastTranscript = ""
        carLastResponse = nil
        carError = nil
    }

    func invalidateLocalCarTurn() {
        let hadTurn = carActiveTurnID != nil
        carActiveTurnID = nil
        carActiveCapabilityCallbackID = nil
        carSpeechOutput.stop()
        if hadTurn {
            carLastTranscript = ""
            carError = nil
        }
        switch carPhase {
        case .waitingReply, .speaking, .awaitingConfirmation:
            carPhase = .idle
        default:
            break
        }
    }

    private func ensureCarSession(_ target: CarTurnTarget) async throws -> Session? {
        guard carTurnIsCurrent(target) else { return nil }
        guard isConnected else { throw CarModeError.notConnected }

        let recordKey = carRecordKey(for: target)
        if let record = carSessionsByContext[recordKey] {
            do {
                let session = try await apiClient.session(sessionID: record.sessionID)
                guard carTurnIsCurrent(target) else { return nil }
                guard session.isArchived else { return session }
                let restored = try await apiClient.updateSessionArchived(sessionID: session.id, archived: -1)
                guard carTurnIsCurrent(target) else { return nil }
                upsertSession(restored)
                return restored
            } catch APIError.httpError(let statusCode, _) where statusCode == 404 {
                guard carTurnIsCurrent(target) else { return nil }
                carSessionsByContext.removeValue(forKey: carRecordKey(for: target))
                persistCarSessions()
            }
        }

        guard carTurnIsCurrent(target) else { return nil }
        guard canCreateSession else { throw CarModeError.selectedProjectUnsupported }
        let session = try await apiClient.createSession(title: "Ambient Mode", directory: nil)
        guard carTurnIsCurrent(target) else { return nil }
        carSessionsByContext[carRecordKey(for: target)] = CarSessionRecord(
            sessionID: session.id,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        persistCarSessions()
        upsertSession(session)
        return session
    }

    private func handleCarResponse(
        _ response: MessageWithParts,
        sessionID: String,
        target: CarTurnTarget,
        speaks: Bool
    ) async throws -> String? {
        guard carTurnIsCurrent(target) else {
            abandonCarTurnIfStillOwned(target)
            return nil
        }
        guard response.info.isAssistant,
              response.info.sessionID == sessionID,
              response.info.time.completed != nil else {
            throw CarModeError.invalidResponse
        }
        let envelope = try CarResponseEnvelope.accepted(from: response.info)
        let recordKey = carRecordKey(for: target)
        guard carSessionsByContext[recordKey]?.lastHandledAssistantMessageID != response.info.id else {
            carPhase = .idle
            carActiveTurnID = nil
            return nil
        }
        var record = carSessionsByContext[recordKey] ?? CarSessionRecord(
            sessionID: sessionID,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        record.lastHandledAssistantMessageID = response.info.id
        record.pendingConfirmationID = envelope.status == .needsConfirmation ? envelope.confirmation?.id : nil
        record.lastUsedAt = Date()
        carSessionsByContext[recordKey] = record
        persistCarSessions()

        carLastResponse = envelope
        if speaks {
            carPhase = .speaking
            await carSpeechOutput.speak(envelope.speech)
        }
        guard carTurnIsCurrent(target) else {
            abandonCarTurnIfStillOwned(target)
            return nil
        }

        if envelope.status == .completed, let action = envelope.clientActions.first {
            switch action {
            case .openNavigation:
                guard await CarClientActionDispatcher.dispatch(action) else {
                    throw CarModeError.mapsUnavailable
                }
            case .healthExportAll:
                await requestClientCapability(
                    action,
                    sessionID: sessionID,
                    carContextKey: carRecordKey(for: target),
                    assistantMessageID: response.info.id
                )
            case .unknown:
                break
            }
        }

        guard carTurnIsCurrent(target) else {
            abandonCarTurnIfStillOwned(target)
            return nil
        }
        switch envelope.status {
        case .completed:
            carPhase = .idle
        case .needsConfirmation:
            carPhase = .awaitingConfirmation
        case .failed:
            carPhase = .failed
        }
        carActiveTurnID = nil
        return envelope.speech
    }

    func noteServerCurrentProjectWorktree(_ newValue: String?) {
        let old = _serverCurrentProjectWorktree
        guard old != newValue else { return }
        let oldEffectiveCarServerDirectory = _serverCurrentProjectWorktree ?? carLastKnownServerWorktree
        if effectiveProjectDirectory == nil,
           let oldEffectiveCarServerDirectory, !oldEffectiveCarServerDirectory.isEmpty,
           let newValue, !newValue.isEmpty,
           oldEffectiveCarServerDirectory != newValue {
            invalidateCarTurnForRealProjectChange()
        }
        _serverCurrentProjectWorktree = newValue
        if let newValue, !newValue.isEmpty {
            carLastKnownServerWorktree = newValue
        }
        if effectiveProjectDirectory == nil,
           old == nil || old?.isEmpty == true,
           let newValue, !newValue.isEmpty {
            rehomeUnresolvedCarSession(to: newValue)
        }
    }

    func clearCarLastKnownServerWorktree() {
        carLastKnownServerWorktree = nil
    }

    func invalidateCarTurnForRealProjectChange() {
        invalidateBackgroundVoicePolicy()
        closeCarLiveNow()
        guard carActiveTurnID != nil
            || carPhase == .waitingReply
            || carPhase == .speaking
            || carPhase == .awaitingConfirmation else { return }
        invalidateLocalCarTurn()
    }

    private func rehomeUnresolvedCarSession(to worktree: String) {
        let placeholder = unresolvedCarContextKey()
        let resolved = "\(currentHostProfileID.uuidString)|\(worktree)"
        guard placeholder != resolved, let record = carSessionsByContext[placeholder] else { return }
        if carSessionsByContext[resolved] == nil {
            carSessionsByContext[resolved] = record
            carSessionsByContext.removeValue(forKey: placeholder)
            persistCarSessions()
        }
    }

    private func unresolvedCarContextKey() -> String {
        "\(currentHostProfileID.uuidString)|__server_default__"
    }

    private func carContextMatchesCaptured(_ captured: String) -> Bool {
        if carContextKey == captured { return true }
        guard effectiveProjectDirectory == nil,
              let known = serverCurrentProjectWorktree ?? carLastKnownServerWorktree, !known.isEmpty else { return false }
        return captured == unresolvedCarContextKey()
    }

    private func carRecordKey(for target: CarTurnTarget) -> String {
        guard effectiveProjectDirectory == nil,
              let known = serverCurrentProjectWorktree ?? carLastKnownServerWorktree, !known.isEmpty,
              target.contextKey == unresolvedCarContextKey() else {
            return target.contextKey
        }
        return "\(currentHostProfileID.uuidString)|\(known)"
    }

    private func carTurnIsCurrent(_ target: CarTurnTarget) -> Bool {
        !Task.isCancelled
            && carActiveTurnID == target.turnID
            && isCurrentHostRequest(target.host)
            && carContextMatchesCaptured(target.contextKey)
    }

    private func abandonCarTurnIfStillOwned(_ target: CarTurnTarget) {
        guard carActiveTurnID == target.turnID else { return }
        carActiveTurnID = nil
        carLastTranscript = ""
        carError = nil
        carSpeechOutput.stop()
        switch carPhase {
        case .waitingReply, .speaking:
            carPhase = .idle
        default:
            break
        }
    }

    func persistCarSessions() {
        if carSessionsByContext.isEmpty {
            defaults.removeObject(forKey: Self.carSessionsByContextKey)
        } else if let data = try? JSONEncoder().encode(carSessionsByContext) {
            defaults.set(data, forKey: Self.carSessionsByContextKey)
        }
    }
}
