import Foundation

struct HostRequestSnapshot: Equatable, Sendable {
    var hostProfileID: UUID
    var generation: UInt64
}

struct HostCredentialAccess {
    var save: (String, String) throws -> Void
    var load: (String) throws -> String?
    var delete: (String) throws -> Void

    static let keychain = HostCredentialAccess(
        save: { value, key in try KeychainHelper.save(value, forKey: key) },
        load: { key in try KeychainHelper.load(forKey: key) },
        delete: { key in try KeychainHelper.delete(key) }
    )

    static let noExternal = HostCredentialAccess(
        save: { _, _ in },
        load: { _ in nil },
        delete: { _ in }
    )
}

extension AppState {
    func captureHostRequestSnapshot() -> HostRequestSnapshot {
        HostRequestSnapshot(hostProfileID: currentHostProfileID, generation: hostRequestGeneration)
    }

    func isCurrentHostRequest(_ snapshot: HostRequestSnapshot) -> Bool {
        snapshot.hostProfileID == currentHostProfileID && snapshot.generation == hostRequestGeneration
    }

    func loadHostProfilesFromStorageOrLegacy(allowLegacyPersist: Bool = true) {
        guard let data = defaults.data(forKey: Self.hostProfilesKey) else {
            installLegacyHostProfile(persist: allowLegacyPersist)
            return
        }
        if let decoded = try? JSONDecoder().decode([HostProfile].self, from: data) {
            if decoded.isEmpty {
                installLegacyHostProfile(persist: allowLegacyPersist)
            } else {
                applyDecodedHostProfiles(decoded)
            }
            return
        }
        hostProfileBlobUnreadable = true
        hostProfileLoadError = L10n.t(.hostConnectionErrorGeneric)
        installLegacyHostProfile(persist: false)
    }

    func applyDecodedHostProfiles(_ decoded: [HostProfile]) {
        hostProfileBlobUnreadable = false
        hostProfileLoadError = nil
        hostProfiles = decoded
        if let idString = defaults.string(forKey: Self.currentHostProfileIDKey),
           let id = UUID(uuidString: idString),
           decoded.contains(where: { $0.id == id }) {
            currentHostProfileID = id
        } else {
            currentHostProfileID = decoded[0].id
        }
    }

    func installLegacyHostProfile(persist: Bool) {
        var profile = HostProfile.defaultProfile(serverURL: _serverURL)
        var canPersist = persist
        if !_username.isEmpty || !_password.isEmpty {
            let passwordID = Self.passwordKeychainID(for: profile.id)
            if !_password.isEmpty {
                do {
                    try hostCredentialAccess.save(_password, passwordID)
                    profile.basicAuth = BasicAuthConfig(username: _username, keychainPasswordID: passwordID)
                } catch {
                    hostCredentialError = error.localizedDescription
                    canPersist = false
                }
            } else if canPersist {
                profile.basicAuth = BasicAuthConfig(username: _username, keychainPasswordID: passwordID)
            }
        }

        #if !os(visionOS)
        if sshTunnelManager.config.isEnabled {
            profile.name = L10n.t(.hostDefaultSSHName)
            profile.transport = .sshTunnel
            profile.serverURL = APIClient.defaultServer
            profile.ssh = sshTunnelManager.config
        }
        #endif

        if !canPersist {
            hostProfileBlobUnreadable = true
        }
        hostProfiles = [profile]
        currentHostProfileID = profile.id
        if canPersist {
            saveHostProfiles()
        }
    }

    func saveHostProfiles() {
        guard !hostProfileBlobUnreadable else { return }
        guard !hostProfiles.isEmpty,
              let data = try? JSONEncoder().encode(hostProfiles) else { return }
        defaults.set(data, forKey: Self.hostProfilesKey)
    }

    func trustPendingSSHHostKeyAndReconnect() async {
        #if !os(visionOS)
        sshTunnelManager.trustPendingHostKey()
        pendingSSHHostKeyMismatch = nil
        sshTunnelManager.disconnect()
        await testConnection()
        #endif
    }

    func dismissPendingSSHHostKeyMismatch() {
        pendingSSHHostKeyMismatch = nil
    }

    func applyCurrentHostProfileToRuntime(persistLegacy: Bool = true) {
        readStateStore.selectHost(currentHostProfileID)
        guard let profile = currentHostProfile else { return }

        _serverURL = profile.serverURL
        _username = profile.basicAuth?.username ?? ""
        if let passwordID = profile.basicAuth?.keychainPasswordID {
            do {
                _password = try hostCredentialAccess.load(passwordID) ?? ""
                hostPasswordUnreadable = false
                hostCredentialError = nil
            } catch {
                _password = ""
                hostPasswordUnreadable = true
                hostCredentialError = error.localizedDescription
            }
        } else {
            _password = ""
            hostPasswordUnreadable = false
            if !hostProfileBlobUnreadable {
                hostCredentialError = nil
            }
        }

        if persistLegacy {
            defaults.set(_serverURL, forKey: Self.serverURLKey)
            defaults.set(_username, forKey: Self.usernameKey)
            if !hostPasswordUnreadable {
                do {
                    if _password.isEmpty {
                        try hostCredentialAccess.delete(Self.passwordKeychainKey)
                    } else {
                        try hostCredentialAccess.save(_password, Self.passwordKeychainKey)
                    }
                } catch {
                    hostCredentialError = error.localizedDescription
                }
            }
        }

        #if !os(visionOS)
        switch profile.transport {
        case .direct:
            var disabled = sshTunnelManager.config
            disabled.isEnabled = false
            sshTunnelManager.config = disabled
            sshTunnelManager.disconnect()
        case .sshTunnel:
            var config = profile.ssh ?? .default
            config.isEnabled = true
            sshTunnelManager.config = config
        }
        #endif
    }

    func persistRuntimeToCurrentHostProfile() {
        guard let index = hostProfiles.firstIndex(where: { $0.id == currentHostProfileID }) else { return }
        var profile = hostProfiles[index]
        profile.serverURL = serverURL
        profile.lastUsedAt = Date()

        if !hostPasswordUnreadable {
            do {
                try writeRuntimeCredentials(into: &profile)
                hostCredentialError = nil
            } catch {
                hostCredentialError = error.localizedDescription
            }
        }

        #if !os(visionOS)
        if profile.transport == .sshTunnel {
            profile.ssh = sshTunnelManager.config
        }
        #endif

        hostProfiles[index] = profile
        saveHostProfiles()
    }

    func writeRuntimeCredentials(into profile: inout HostProfile) throws {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.isEmpty {
            if let oldID = profile.basicAuth?.keychainPasswordID {
                try hostCredentialAccess.delete(oldID)
            }
            profile.basicAuth = nil
            return
        }
        let passwordID = profile.basicAuth?.keychainPasswordID ?? Self.passwordKeychainID(for: profile.id)
        if password.isEmpty {
            try hostCredentialAccess.delete(passwordID)
        } else {
            try hostCredentialAccess.save(password, passwordID)
        }
        profile.basicAuth = BasicAuthConfig(username: username, keychainPasswordID: passwordID)
    }

    func saveHostProfile(_ profile: HostProfile, password: String? = nil, makeCurrent: Bool = true) throws {
        var saved = profile
        if saved.transport == .sshTunnel {
            var ssh = saved.ssh ?? .default
            ssh.isEnabled = true
            saved.ssh = ssh
            saved.serverURL = APIClient.defaultServer
        }
        if let password {
            try commitHostPassword(password, username: profile.basicAuth?.username ?? "", to: &saved)
            hostCredentialError = nil
            if saved.id == currentHostProfileID {
                hostPasswordUnreadable = false
            }
        }
        if makeCurrent && saved.id != currentHostProfileID {
            persistRuntimeToCurrentHostProfile()
        }

        let switching = makeCurrent && saved.id != currentHostProfileID
        let connectionChanged = connectionIdentityChanged(saved, password: password)
        let editingCurrent = saved.id == currentHostProfileID
        hostProfileBlobUnreadable = false
        hostProfileLoadError = nil
        if let index = hostProfiles.firstIndex(where: { $0.id == saved.id }) {
            hostProfiles[index] = saved
        } else {
            hostProfiles.append(saved)
        }
        saveHostProfiles()

        if switching || (editingCurrent && connectionChanged) || (makeCurrent && connectionChanged) {
            beginHostTransportTransition(to: saved.id)
        } else if makeCurrent {
            currentHostProfileID = saved.id
            applyCurrentHostProfileToRuntime()
        }
    }

    func commitHostPassword(_ password: String, username: String, to profile: inout HostProfile) throws {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password.isEmpty {
            if let oldID = profile.basicAuth?.keychainPasswordID {
                try hostCredentialAccess.delete(oldID)
            }
            profile.basicAuth = nil
            return
        }
        let passwordID = profile.basicAuth?.keychainPasswordID ?? Self.passwordKeychainID(for: profile.id)
        if password.isEmpty {
            try hostCredentialAccess.delete(passwordID)
        } else {
            try hostCredentialAccess.save(password, passwordID)
        }
        profile.basicAuth = BasicAuthConfig(username: username, keychainPasswordID: passwordID)
    }

    func connectionIdentityChanged(_ saved: HostProfile, password: String?) -> Bool {
        guard saved.id == currentHostProfileID else { return false }
        if saved.transport != currentHostProfile?.transport { return true }
        if saved.serverURL != serverURL { return true }
        let savedUser = saved.basicAuth?.username ?? ""
        if savedUser != username { return true }
        if let password, password != self.password { return true }
        #if !os(visionOS)
        if saved.transport == .sshTunnel {
            let next = saved.ssh ?? .default
            let live = sshTunnelManager.config
            if next.host != live.host || next.port != live.port || next.username != live.username || next.remotePort != live.remotePort || !live.isEnabled {
                return true
            }
        }
        #endif
        return false
    }

    func beginHostTransportTransition(to id: UUID) {
        guard hostProfiles.contains(where: { $0.id == id }) else { return }
        invalidateBackgroundVoicePolicy()
        closeCarLiveNow()
        markCurrentSessionViewed()
        invalidateLocalCarTurn()
        clearCarLastKnownServerWorktree()
        invalidateDeepLinkRoute(keepPending: true)
        hostRequestGeneration &+= 1
        sessionLoadingID = UUID()
        disconnectSSE()
        #if !os(visionOS)
        sshTunnelManager.disconnect()
        #endif
        currentHostProfileID = id
        applyCurrentHostProfileToRuntime()
        resetConnectionRuntimeForHostSwitch()
        hostTransportConfigureTask = Task { [weak self] in
            await self?.configureAPIClientFromCurrentHost()
        }
    }

    func finishHostTransportConfiguration() async {
        await hostTransportConfigureTask?.value
    }

    func configureAPIClientFromCurrentHost() async {
        while true {
            let snapshot = captureHostRequestSnapshot()
            let info = Self.serverURLInfo(serverURL)
            guard info.isAllowed, let baseURL = info.normalized else { return }
            let user = username.isEmpty ? nil : username
            let pass = password.isEmpty ? nil : password
            await apiClient.configure(baseURL: baseURL, username: user, password: pass)
            if isCurrentHostRequest(snapshot) { return }
        }
    }

    func switchHostProfile(to id: UUID) async {
        guard id != currentHostProfileID,
              hostProfiles.contains(where: { $0.id == id }) else { return }
        persistRuntimeToCurrentHostProfile()
        beginHostTransportTransition(to: id)
        await finishHostTransportConfiguration()
        await refresh()
        await processPendingDeepLinkIfPossible()
        await retryClientCapabilityOutbox()
    }

    func deleteHostProfile(_ profile: HostProfile) throws {
        guard hostProfiles.count > 1 else { throw HostProfileError.cannotDeleteOnlyHost }
        let wasCurrent = profile.id == currentHostProfileID
        if let passwordID = profile.basicAuth?.keychainPasswordID {
            do {
                try hostCredentialAccess.delete(passwordID)
            } catch {
                hostCredentialError = error.localizedDescription
            }
        }
        hostProfiles.removeAll { $0.id == profile.id }
        messageStore.removeOutboundSends(hostProfileID: profile.id)
        if wasCurrent, let first = hostProfiles.first {
            beginHostTransportTransition(to: first.id)
        }
        saveHostProfiles()
    }

    func duplicateHostProfile(_ profile: HostProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = L10n.t(.hostDuplicateName, profile.displayName)
        copy.lastUsedAt = nil
        if let auth = profile.basicAuth {
            let newPasswordID = Self.passwordKeychainID(for: copy.id)
            do {
                if let password = try hostCredentialAccess.load(auth.keychainPasswordID) {
                    try hostCredentialAccess.save(password, newPasswordID)
                }
                copy.basicAuth = BasicAuthConfig(username: auth.username, keychainPasswordID: newPasswordID)
            } catch {
                hostCredentialError = error.localizedDescription
                copy.basicAuth = nil
            }
        }
        do {
            try saveHostProfile(copy, makeCurrent: false)
        } catch {
            hostCredentialError = error.localizedDescription
        }
    }

    func importHostProfile(from json: String) throws -> HostProfile {
        guard let data = json.data(using: .utf8) else {
            throw HostProfileError.invalidImport(L10n.t(.hostImportErrorInvalidUTF8))
        }
        do {
            let payload = try JSONDecoder().decode(HostProfileImportPayload.self, from: data)
            return try payload.makeProfile()
        } catch let error as HostProfileError {
            throw error
        } catch {
            throw HostProfileError.invalidImport(error.localizedDescription)
        }
    }

    func hostConfigJSON(for profile: HostProfile) throws -> String {
        let payload: HostProfileExportPayload
        switch profile.transport {
        case .direct:
            payload = HostProfileExportPayload(
                name: profile.displayName,
                transport: .direct,
                serverURL: profile.serverURL,
                ssh: nil
            )
        case .sshTunnel:
            let ssh = profile.ssh.map {
                HostProfileExportSSH(host: $0.host, port: $0.port, username: $0.username, remotePort: $0.remotePort)
            }
            payload = HostProfileExportPayload(
                name: profile.displayName,
                transport: .sshTunnel,
                serverURL: nil,
                ssh: ssh
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw HostProfileError.invalidImport(L10n.t(.hostExportErrorEncodeConfigJSON))
        }
        return json
    }

    func updateConnectionDiagnostic(phase: ConnectionPhase, message: String, recoveryHint: String? = nil) {
        connectionDiagnostic = ConnectionDiagnostic(
            hostProfileID: currentHostProfileID,
            phase: phase,
            message: message,
            recoveryHint: recoveryHint,
            timestamp: Date()
        )
    }

    func friendlyConnectionError(_ error: Error, phase: ConnectionPhase = .failed) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidURL:
                return L10n.t(.hostConnectionErrorInvalidURL)
            case .httpError(let statusCode, _):
                if statusCode == 401 { return L10n.t(.hostConnectionErrorBasicAuthRejected) }
                return L10n.t(.hostConnectionErrorHTTPStatus, Int32(statusCode))
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return L10n.t(.hostConnectionErrorCannotConnect)
            case NSURLErrorTimedOut:
                return L10n.t(.hostConnectionErrorTimedOut)
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return L10n.t(.hostConnectionErrorDNS)
            default:
                return L10n.t(.hostConnectionErrorNetwork, nsError.localizedDescription)
            }
        }

        let message = error.localizedDescription
        if message.contains("APIError error") {
            return phase == .health
                ? L10n.t(.hostConnectionErrorHealthCheckFailed)
                : L10n.t(.hostConnectionErrorGeneric)
        }
        return message
    }

    func resetConnectionRuntimeForHostSwitch() {
        isConnected = false
        connectionError = nil
        connectionDiagnostic = nil
        serverVersion = nil
        projects = []
        serverCurrentProjectWorktree = nil
        sessions = []
        currentSessionID = nil
        messages = []
        partsByMessage = [:]
        sessionDiffs = []
        fileTreeRoot = []
        sessionStatuses = [:]
        statusStreamConnected = false
        statusConfirmedAt = [:]
        statusDirectories = [:]
        statusRevisions = [:]
        statusRevision = 0
        statusKnowledgeRevision &+= 1
        statusPollID = nil
        statusLastAttemptAt = nil
        statusLastAttemptDirectory = nil
        permissionPollID = nil
        questionPollID = nil
        permissionRevision &+= 1
        questionRevision &+= 1
        pendingRequestEpoch &+= 1
        abortingSessionIDs = []
        pendingSessionErrorAt = [:]
        readStateStore.selectHost(currentHostProfileID)
        sessionTodos = [:]
        sessionScope.resetAll()
        agents = []
        hasServerAgentCatalog = false
        selectedAgentName = AgentInfo.fallbackAgentName
        selectedAgentIndex = 0
        isLoadingProjects = false
        isLoadingAgents = false
        resetSessionPagination()
        providersResponse = nil
        providerModelsIndex = [:]
        providerConfigError = nil
        catalogModelPresets = []
        providerDisplayNames = [:]
    }

    nonisolated static func passwordKeychainID(for profileID: UUID) -> String {
        "hostProfile.\(profileID.uuidString).password"
    }
}
