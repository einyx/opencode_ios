import Foundation
import Network
import Security
import SwiftUI
import Testing
@testable import OpenCodeClient

@Suite(.serialized)
struct HostLifecycleTests {
    @Test @MainActor func hostSwitchKeepsDraftAndModelByHost() async throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.setDraftText("keep-a", for: "s-a")
        state.selectedModelIDBySessionID["s-a"] = "openai/m-a"
        let hostA = state.currentHostProfileID
        let hostB = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(hostB, makeCurrent: false)

        await state.switchHostProfile(to: hostB.id)
        #expect(state.draftText(for: "s-a") == "")
        #expect(state.selectedModelIDBySessionID["s-a"] == nil)
        state.setDraftText("keep-b", for: "s-b")
        state.selectedModelIDBySessionID["s-b"] = "anthropic/m-b"

        await state.switchHostProfile(to: hostA)
        #expect(state.currentHostProfileID == hostA)
        #expect(state.draftText(for: "s-a") == "keep-a")
        #expect(state.selectedModelIDBySessionID["s-a"] == "openai/m-a")
        #expect(state.draftText(for: "s-b") == "")

        await state.switchHostProfile(to: hostB.id)
        #expect(state.draftText(for: "s-b") == "keep-b")
        #expect(state.selectedModelIDBySessionID["s-b"] == "anthropic/m-b")
    }

    @Test @MainActor func runtimeResetDoesNotPersistEmptyPreferences() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.setDraftText("stay", for: "s1")
        state.selectedModelIDBySessionID["s1"] = "openai/m-a"
        state.persistSelectedModelMap()

        state.resetConnectionRuntimeForHostSwitch()

        let drafts = try decodeHostMap(harness.defaults, AppState.draftInputsByHostKey)
        let models = try decodeHostMap(harness.defaults, AppState.selectedModelByHostKey)
        let host = state.currentHostProfileID.uuidString
        #expect(drafts[host]?["s1"] == "stay")
        #expect(models[host]?["s1"] == "openai/m-a")
        #expect(state.draftText(for: "s1") == "stay")
    }

    @Test @MainActor func flatPreferenceKeysMigrateIntoCurrentHost() throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let suite = "opencode.w04.migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(["s1": "old-draft"]), forKey: AppState.draftInputsBySessionKey)
        defaults.set(try JSONEncoder().encode(["s1": "openai/old"]), forKey: AppState.selectedModelBySessionKey)
        let state = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            clientCapabilityStore: ClientCapabilityCallbackStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(state.draftText(for: "s1") == "old-draft")
        #expect(state.selectedModelIDBySessionID["s1"] == "openai/old")
        #expect(defaults.data(forKey: AppState.draftInputsBySessionKey) == nil)
        #expect(defaults.data(forKey: AppState.selectedModelBySessionKey) == nil)
        let drafts = try decodeHostMap(defaults, AppState.draftInputsByHostKey)
        #expect(drafts[state.currentHostProfileID.uuidString]?["s1"] == "old-draft")
    }

    @Test @MainActor func activatingEditingAndDeletingCurrentHostShareTransportTransition() async throws {
        let api = MockAPIClient()
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        let original = state.currentHostProfileID
        state.sessions = [makeHostSession(id: "keep")]
        state.currentSessionID = "keep"
        state.isConnected = true
        state.serverVersion = "old"
        state.connectSSE()
        let generation = state.hostRequestGeneration
        #expect(state.sseTask != nil)

        let other = directProfile(name: "Other", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        await state.finishHostTransportConfiguration()
        #expect(state.currentHostProfileID == other.id)
        #expect(state.hostRequestGeneration == generation + 1)
        #expect(state.sessions.isEmpty)
        #expect(state.currentSessionID == nil)
        #expect(state.sseTask == nil)
        #expect(state.isConnected == false)
        #expect(await api.configuredBaseURL == "http://127.0.0.1:4020")

        state.sessions = [makeHostSession(id: "edited")]
        state.connectSSE()
        let edited = state.currentHostProfile!
        var changed = edited
        changed.serverURL = "http://127.0.0.1:4030"
        let editedGeneration = state.hostRequestGeneration
        try state.saveHostProfile(changed, makeCurrent: true)
        await state.finishHostTransportConfiguration()
        #expect(state.hostRequestGeneration == editedGeneration + 1)
        #expect(state.sessions.isEmpty)
        #expect(state.sseTask == nil)
        #expect(state.serverURL == "http://127.0.0.1:4030")
        #expect(await api.configuredBaseURL == "http://127.0.0.1:4030")

        state.sessions = [makeHostSession(id: "before-delete")]
        state.connectSSE()
        let beforeDelete = state.hostRequestGeneration
        let current = state.currentHostProfile!
        let restored = directProfile(id: original, name: "Restored", url: "http://127.0.0.1:4010")
        try state.saveHostProfile(restored, makeCurrent: false)
        try state.deleteHostProfile(current)
        await state.finishHostTransportConfiguration()
        #expect(state.currentHostProfileID == original)
        #expect(state.hostRequestGeneration == beforeDelete + 1)
        #expect(state.sessions.isEmpty)
        #expect(state.sseTask == nil)
        #expect(await api.configuredBaseURL == "http://127.0.0.1:4010")
    }

    @Test @MainActor func savingNonCurrentOrNameOnlyDoesNotResetTransport() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.sessions = [makeHostSession(id: "stay")]
        state.currentSessionID = "stay"
        state.connectSSE()
        let generation = state.hostRequestGeneration
        let other = directProfile(name: "Stored", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: false)
        #expect(state.hostRequestGeneration == generation)
        #expect(state.sessions.map(\.id) == ["stay"])
        #expect(state.sseTask != nil)

        var renamed = state.currentHostProfile!
        renamed.name = "Renamed"
        try state.saveHostProfile(renamed, password: state.password, makeCurrent: true)
        #expect(state.hostRequestGeneration == generation)
        #expect(state.sessions.map(\.id) == ["stay"])
        #expect(state.currentHostProfile?.name == "Renamed")
        #expect(state.sseTask != nil)
    }

    @Test @MainActor func lateHostResultsDoNotPolluteTheNewHost() async throws {
        let api = HostRaceAPI()
        await api.arm(["health", "sessions", "projects", "providers", "agents", "create", "fork"])
        await api.setHealth(HealthResponse(healthy: true, version: "from-a"))
        await api.setSessions([makeHostSession(id: "from-a")])
        await api.setProjects([Project(id: "p-a", worktree: "/a", vcs: nil, icon: nil, time: nil, sandboxes: nil)])
        await api.setAgents([AgentInfo(name: "from-a", description: nil, mode: "primary", hidden: nil, native: nil)])
        await api.setCreated(makeHostSession(id: "created-a"))
        await api.setForked(makeHostSession(id: "forked-a"))
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.isConnected = true
        state.currentSessionID = "s-a"
        state.connectSSE()

        let health = Task { await state.testConnection() }
        let sessions = Task { await state.loadSessions() }
        let projects = Task { await state.loadProjects() }
        let providers = Task { await state.loadProvidersConfig() }
        let agents = Task { await state.loadAgents() }
        let created = Task { await state.createSession() }
        let forked = Task { await state.forkSession(messageID: nil) }
        for name in ["health", "sessions", "projects", "providers", "agents", "create", "fork"] {
            await api.waitUntilPaused(name)
        }

        let other = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        state.providerConfigError = "keep"
        state.agents = [AgentInfo(name: "from-b", description: nil, mode: "primary", hidden: nil, native: nil)]
        state.projects = [Project(id: "p-b", worktree: "/b", vcs: nil, icon: nil, time: nil, sandboxes: nil)]
        await api.releaseAll()
        _ = await (health.value, sessions.value, projects.value, providers.value, agents.value, created.value, forked.value)

        #expect(state.currentHostProfileID == other.id)
        #expect(state.isConnected == false)
        #expect(state.serverVersion == nil)
        #expect(state.sseTask == nil)
        #expect(state.sessions.isEmpty)
        #expect(state.currentSessionID == nil)
        #expect(state.projects.map(\.id) == ["p-b"])
        #expect(state.providerConfigError == "keep")
        #expect(state.agents.map(\.name) == ["from-b"])
    }

    @Test @MainActor func lateHostErrorsDoNotPolluteTheNewHost() async throws {
        let api = HostRaceAPI()
        await api.arm(["health", "sessions", "projects", "providers"])
        await api.fail(["health", "sessions", "projects", "providers"], APIError.invalidURL)
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.isConnected = true

        let health = Task { await state.testConnection() }
        let sessions = Task { await state.loadSessions() }
        let projects = Task { await state.loadProjects() }
        let providers = Task { await state.loadProvidersConfig() }
        for name in ["health", "sessions", "projects", "providers"] {
            await api.waitUntilPaused(name)
        }
        let other = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        state.connectionError = nil
        state.projects = [Project(id: "p-b", worktree: "/b", vcs: nil, icon: nil, time: nil, sandboxes: nil)]
        state.providerConfigError = "keep"
        await api.releaseAll()
        _ = await (health.value, sessions.value, projects.value, providers.value)

        #expect(state.connectionError == nil)
        #expect(state.projects.map(\.id) == ["p-b"])
        #expect(state.providerConfigError == "keep")
        #expect(state.isConnected == false)
    }

    @Test @MainActor func malformedProfileBlobIsKeptAndMissingDataStillMigrates() throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let badSuite = "opencode.w04.blob.\(UUID().uuidString)"
        let badDefaults = UserDefaults(suiteName: badSuite)!
        defer { badDefaults.removePersistentDomain(forName: badSuite) }
        let blob = Data("{".utf8)
        badDefaults.set(blob, forKey: AppState.hostProfilesKey)
        let bad = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: badDefaults),
            clientCapabilityStore: tempStore(badSuite),
            userDefaults: badDefaults,
            hostCredentialAccess: .noExternal
        )
        #expect(bad.hostProfileBlobUnreadable)
        #expect(bad.hostProfileLoadError == L10n.t(.hostConnectionErrorGeneric))
        #expect(badDefaults.data(forKey: AppState.hostProfilesKey) == blob)
        #expect(!bad.hostProfiles.isEmpty)

        let missingSuite = "opencode.w04.missing.\(UUID().uuidString)"
        let missingDefaults = UserDefaults(suiteName: missingSuite)!
        defer { missingDefaults.removePersistentDomain(forName: missingSuite) }
        missingDefaults.set("http://127.0.0.1:4010", forKey: AppState.serverURLKey)
        let migrated = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: missingDefaults),
            clientCapabilityStore: tempStore(missingSuite),
            userDefaults: missingDefaults,
            hostCredentialAccess: .noExternal
        )
        #expect(!migrated.hostProfileBlobUnreadable)
        #expect(migrated.hostProfileLoadError == nil)
        #expect(migrated.currentHostProfile?.serverURL == "http://127.0.0.1:4010")
        #expect(missingDefaults.data(forKey: AppState.hostProfilesKey) != nil)
    }

    @Test @MainActor func keychainSaveFailureDoesNotCommitReference() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        let fake = CredentialFake()
        fake.saveError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        state.hostCredentialAccess = fake.access()
        var profile = state.currentHostProfile!
        profile.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: "")

        do {
            try state.saveHostProfile(profile, password: "new-secret", makeCurrent: true)
            Issue.record("expected keychain save to throw")
        } catch {
            #expect(error.localizedDescription == L10n.t(.keychainErrorUnhandledStatus, Int32(errSecInteractionNotAllowed)))
        }
        #expect(state.currentHostProfile?.basicAuth == nil)
        #expect(fake.saved.isEmpty)
    }

    @Test @MainActor func unreadableKeychainPasswordIsNotTreatedAsAbsent() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        let fake = CredentialFake()
        let passwordID = AppState.passwordKeychainID(for: state.currentHostProfileID)
        fake.saved[passwordID] = "stored"
        state.hostCredentialAccess = fake.access()
        var profile = state.currentHostProfile!
        profile.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: passwordID)
        try state.saveHostProfile(profile, password: nil, makeCurrent: true)
        #expect(state.currentHostProfile?.basicAuth?.keychainPasswordID == passwordID)

        fake.loadError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        state.applyCurrentHostProfileToRuntime(persistLegacy: false)
        #expect(state.hostPasswordUnreadable)
        #expect(state.hostCredentialError == L10n.t(.keychainErrorUnhandledStatus, Int32(errSecInteractionNotAllowed)))
        #expect(state.password.isEmpty)

        state.persistRuntimeToCurrentHostProfile()
        #expect(fake.deleted.isEmpty)
        #expect(state.currentHostProfile?.basicAuth?.keychainPasswordID == passwordID)
        #expect(fake.saved[passwordID] == "stored")
    }

    @Test @MainActor func savingOtherHostPasswordDoesNotDeleteUnreadableCurrentPassword() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        let fake = CredentialFake()
        let hostA = state.currentHostProfileID
        let passwordIDA = AppState.passwordKeychainID(for: hostA)
        fake.saved[passwordIDA] = "a-secret"
        state.hostCredentialAccess = fake.access()
        var profileA = state.currentHostProfile!
        profileA.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: passwordIDA)
        try state.saveHostProfile(profileA, password: nil, makeCurrent: true)

        fake.loadError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        state.applyCurrentHostProfileToRuntime(persistLegacy: false)
        #expect(state.hostPasswordUnreadable)
        #expect(state.username == "admin")
        #expect(state.password.isEmpty)
        fake.loadError = nil

        let hostB = directProfile(name: "B", url: "http://127.0.0.1:4020")
        let passwordIDB = AppState.passwordKeychainID(for: hostB.id)
        try state.saveHostProfile(hostB, password: "b-secret", makeCurrent: true)

        #expect(fake.deleted.contains(passwordIDA) == false)
        #expect(fake.saved[passwordIDA] == "a-secret")
        #expect(fake.saved[passwordIDB] == "b-secret")
        #expect(state.currentHostProfileID == hostB.id)
        #expect(state.password == "b-secret")
    }

    @Test @MainActor func activatingHostClosesInFlightSSHConnect() async throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let harness = LifecycleHarness()
        let ssh = harness.state.sshTunnelManager
        let probe = SSHConnectProbe()
        ssh.tunnelConnector = { config in
            await probe.open(config)
        }
        defer { harness.cleanup() }
        ssh.config = SSHTunnelConfig(isEnabled: true, host: "a.example", port: 22, username: "opencode", remotePort: 19001)
        let connecting = Task { await ssh.connect() }
        await probe.waitUntilOpened(1)

        let profile = HostProfile(
            name: "SSH B",
            transport: .sshTunnel,
            serverURL: APIClient.defaultServer,
            basicAuth: nil,
            ssh: SSHTunnelConfig(isEnabled: true, host: "b.example", port: 22, username: "opencode", remotePort: 19002),
            lastUsedAt: nil
        )
        try harness.state.saveHostProfile(profile, makeCurrent: true)
        probe.releaseOldest()
        await connecting.value

        #expect(probe.closedPorts == [19001])
        #expect(ssh.status == .disconnected)
        #expect(ssh.config.host == "b.example")
        #expect(ssh.config.remotePort == 19002)
        #expect(harness.state.sseTask == nil)
    }

    @Test @MainActor func lateSSHConnectCannotRevivePreviousTunnel() async {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let manager = SSHTunnelManager()
        let probe = SSHConnectProbe()
        manager.tunnelConnector = { config in
            await probe.open(config)
        }
        manager.config = SSHTunnelConfig(isEnabled: true, host: "a.example", port: 22, username: "opencode", remotePort: 19001)

        let first = Task { await manager.connect() }
        await probe.waitUntilOpened(1)
        manager.disconnect()
        manager.config.remotePort = 19002
        let second = Task { await manager.connect() }
        await probe.waitUntilOpened(2)
        probe.releaseOldest()
        probe.releaseOldest()
        await first.value
        await second.value

        #expect(probe.snapshots.map(\.remotePort) == [19001, 19002])
        #expect(probe.closedPorts == [19001])
        #expect(manager.status == .connected)
        #expect(manager.connectedRemotePortForTesting == 19002)
    }

    @Test @MainActor func disconnectEndsListenerReadyWait() async throws {
        let manager = SSHTunnelManager()
        let holder = ListenerTaskHolder()
        await withCheckedContinuation { (installed: CheckedContinuation<Void, Never>) in
            holder.task = Task {
                try await manager.suspendListenerWaitForTesting {
                    installed.resume()
                }
            }
        }
        manager.disconnect()
        do {
            try await holder.task?.value
            Issue.record("listener wait should end by cancellation")
        } catch is CancellationError {
        }
        #expect(manager.status == .disconnected)
    }

    @Test func cancelledListenerStateResumesWait() {
        #expect(SSHTunnelManager.listenerWaitShouldResume(.cancelled))
        #expect(SSHTunnelManager.listenerWaitShouldResume(.ready))
        #expect(SSHTunnelManager.listenerWaitShouldResume(.failed(.posix(.ECONNRESET))))
        #expect(!SSHTunnelManager.listenerWaitShouldResume(.setup))
    }

    @Test @MainActor func sameSessionIDStaysIsolatedAcrossHostsAndRestart() async throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        let sessionID = "shared-session"
        state.setDraftText("draft-a", for: sessionID)
        state.selectedModelIDBySessionID[sessionID] = "openai/a"
        state.persistSelectedModelMap()
        let hostA = state.currentHostProfileID
        let hostB = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(hostB, makeCurrent: false)

        await state.switchHostProfile(to: hostB.id)
        state.setDraftText("draft-b", for: sessionID)
        state.selectedModelIDBySessionID[sessionID] = "anthropic/b"
        state.persistSelectedModelMap()
        await state.switchHostProfile(to: hostA)
        #expect(state.draftText(for: sessionID) == "draft-a")
        #expect(state.selectedModelIDBySessionID[sessionID] == "openai/a")

        let restarted = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: harness.defaults),
            clientCapabilityStore: tempStore("\(harness.suite).restart"),
            userDefaults: harness.defaults,
            hostCredentialAccess: .noExternal
        )
        defer {
            restarted.disconnectSSE()
            restarted.sshTunnelManager.disconnect()
            restarted.hostTransportConfigureTask?.cancel()
        }
        #expect(restarted.currentHostProfileID == hostA)
        #expect(restarted.draftText(for: sessionID) == "draft-a")
        #expect(restarted.selectedModelIDBySessionID[sessionID] == "openai/a")
        await restarted.switchHostProfile(to: hostB.id)
        #expect(restarted.draftText(for: sessionID) == "draft-b")
        #expect(restarted.selectedModelIDBySessionID[sessionID] == "anthropic/b")
    }

    @Test @MainActor func lateCreateDoesNotNavigateAfterHostSwitch() async throws {
        let api = HostRaceAPI()
        await api.arm(["create"])
        await api.setCreated(makeHostSession(id: "created-a"))
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.isConnected = true
        state.sessions = [makeHostSession(id: "s-a")]
        state.currentSessionID = "s-a"
        let created = Task { await state.createSession() }
        await api.waitUntilPaused("create")
        let other = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        state.sessions = [makeHostSession(id: "from-b")]
        state.currentSessionID = "from-b"
        state.connectionError = nil
        await api.releaseAll()
        await created.value
        #expect(state.currentSessionID == "from-b")
        #expect(state.sessions.map(\.id) == ["from-b"])
        #expect(state.connectionError == nil)
    }

    @Test @MainActor func lateForkDoesNotNavigateAfterHostSwitch() async throws {
        let api = HostRaceAPI()
        await api.arm(["fork"])
        await api.setForked(makeHostSession(id: "forked-a"))
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.isConnected = true
        state.sessions = [makeHostSession(id: "s-a")]
        state.currentSessionID = "s-a"
        let forked = Task { await state.forkSession(messageID: nil) }
        await api.waitUntilPaused("fork")
        let other = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        state.sessions = [makeHostSession(id: "from-b")]
        state.currentSessionID = "from-b"
        state.connectionError = nil
        await api.releaseAll()
        await forked.value
        #expect(state.currentSessionID == "from-b")
        #expect(state.sessions.map(\.id) == ["from-b"])
        #expect(state.connectionError == nil)
    }

    @Test @MainActor func stalePaginationDoesNotBlockOrClearTheNewHost() async throws {
        let api = HostRaceAPI()
        await api.armRepeated(["sessions"])
        await api.setSessions([makeHostSession(id: "from-a")])
        let harness = LifecycleHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.sshTunnelManager.config.isEnabled = false
        state.isConnected = true
        state.hasMoreSessions = true
        let pageSize = state.loadedSessionLimit
        let moreA = Task { await state.loadMoreSessions() }
        await api.waitUntilPauseCount("sessions", 1)
        #expect(state.isLoadingMoreSessions)

        let other = directProfile(name: "B", url: "http://127.0.0.1:4020")
        try state.saveHostProfile(other, makeCurrent: true)
        #expect(state.isLoadingMoreSessions == false)
        #expect(state.loadedSessionLimit == pageSize)
        #expect(state.hasMoreSessions)
        state.isConnected = true
        state.sessions = [makeHostSession(id: "from-b")]
        let moreB = Task { await state.loadMoreSessions() }
        await api.waitUntilPauseCount("sessions", 2)
        #expect(state.isLoadingMoreSessions)

        await api.releaseNext("sessions")
        await moreA.value
        #expect(state.isLoadingMoreSessions)
        #expect(state.sessions.map(\.id) == ["from-b"])
        #expect(state.currentHostProfileID == other.id)

        await api.releaseNext("sessions")
        await moreB.value
        #expect(state.isLoadingMoreSessions == false)
    }

    @Test @MainActor func editorLoadFailurePreservesPasswordOnNameOnlySave() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        let fake = CredentialFake()
        let passwordID = AppState.passwordKeychainID(for: state.currentHostProfileID)
        fake.saved[passwordID] = "stored"
        state.hostCredentialAccess = fake.access()
        var profile = state.currentHostProfile!
        profile.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: passwordID)
        try state.saveHostProfile(profile, password: nil, makeCurrent: true)
        fake.loadError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)

        var renamed = state.currentHostProfile!
        renamed.name = "Renamed"
        let editor = HostProfileEditorView(state: state, mode: .edit(renamed))
        let expected = L10n.t(.keychainErrorUnhandledStatus, Int32(errSecInteractionNotAllowed))
        #expect(editor.errorMessage == expected)
        #expect(state.hostCredentialError == expected)
        #expect(editor.passwordLoadFailed)
        #expect(editor.passwordDirty == false)
        #expect(editor.save(makeCurrent: true))
        #expect(fake.deleted.isEmpty)
        #expect(fake.saved[passwordID] == "stored")
        #expect(state.currentHostProfile?.name == "Renamed")
        #expect(state.currentHostProfile?.basicAuth?.keychainPasswordID == passwordID)
        #expect(state.hostCredentialError == expected)
    }

    @Test @MainActor func editorExplicitPasswordEditWritesOrDeletes() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        let fake = CredentialFake()
        let passwordID = AppState.passwordKeychainID(for: state.currentHostProfileID)
        fake.saved[passwordID] = "stored"
        state.hostCredentialAccess = fake.access()
        var profile = state.currentHostProfile!
        profile.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: passwordID)
        try state.saveHostProfile(profile, password: nil, makeCurrent: true)
        state.hostCredentialError = "stale"

        let editor = HostProfileEditorView(state: state, mode: .edit(state.currentHostProfile!))
        editor.editPassword("rotated")
        #expect(editor.save(makeCurrent: true))
        #expect(fake.saved[passwordID] == "rotated")
        #expect(state.hostCredentialError == nil)
        #expect(state.hostPasswordUnreadable == false)

        let clearing = HostProfileEditorView(state: state, mode: .edit(state.currentHostProfile!))
        clearing.editPassword("")
        #expect(clearing.save(makeCurrent: true))
        #expect(fake.deleted.contains(passwordID))
        #expect(fake.saved[passwordID] == nil)
    }

    @Test @MainActor func storageErrorStaysVisibleAndClearsWhenCredentialLoadSucceeds() throws {
        let harness = LifecycleHarness()
        defer { harness.cleanup() }
        let state = harness.state
        let profile = state.currentHostProfile!
        state.hostCredentialError = "keychain-unread"
        state.updateConnectionDiagnostic(phase: .health, message: "checking")
        let hidden = hostCardStatus(
            profileID: profile.id,
            diagnostic: state.connectionDiagnostic,
            loadError: state.hostProfileLoadError,
            credentialError: state.hostCredentialError,
            connectionError: state.connectionError
        )
        #expect(hidden.diagnostic?.phase == .health)
        #expect(hidden.storageError == "keychain-unread")

        let fake = CredentialFake()
        let passwordID = AppState.passwordKeychainID(for: profile.id)
        fake.saved[passwordID] = "stored"
        state.hostCredentialAccess = fake.access()
        var saved = profile
        saved.basicAuth = BasicAuthConfig(username: "admin", keychainPasswordID: passwordID)
        try state.saveHostProfile(saved, password: nil, makeCurrent: true)
        state.hostCredentialError = "keychain-unread"
        state.applyCurrentHostProfileToRuntime(persistLegacy: false)
        #expect(state.hostCredentialError == nil)
        #expect(state.password == "stored")
    }

    @Test @MainActor func deferredListenerFailureDoesNotCancelTheReplacementTunnel() async {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let manager = SSHTunnelManager()
        let stale = manager.beginListenerAttempt(remotePort: 19001)
        let replacement = manager.beginListenerAttempt(remotePort: 19002)
        manager.deliverDeferredListenerFailure(generation: stale.generation, attemptID: stale.id, message: "replaced")
        #expect(manager.status == .disconnected)
        #expect(manager.isCurrentListenerAttempt(generation: replacement.generation, attemptID: replacement.id))

        manager.disconnect()
        let attemptA = manager.beginListenerAttempt(remotePort: 19001)
        let gate = PauseGate()
        let failure = Task { @MainActor in
            await gate.wait()
            manager.deliverDeferredListenerFailure(generation: attemptA.generation, attemptID: attemptA.id, message: "stale-listener")
        }
        await gate.enteredWait()
        manager.disconnect()
        let probe = SSHConnectProbe()
        manager.tunnelConnector = { config in
            await probe.open(config)
        }
        manager.config = SSHTunnelConfig(isEnabled: true, host: "b.example", port: 22, username: "opencode", remotePort: 19002)
        let connecting = Task { await manager.connect() }
        await probe.waitUntilOpened(1)
        #expect(manager.status == .connecting)
        gate.release()
        await failure.value
        #expect(manager.status == .connecting)
        probe.releaseOldest()
        await connecting.value
        #expect(manager.status == .connected)
        #expect(manager.connectedRemotePortForTesting == 19002)
        manager.disconnect()
    }

    @Test @MainActor func staleAcceptedConnectionDoesNotRewriteTheNewTunnel() async {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let manager = SSHTunnelManager()
        manager.config.remotePort = 19002
        let attemptA = manager.beginListenerAttempt(remotePort: 19001)
        var seenPort: Int?
        var cancelled = false
        let gate = PauseGate()
        let forwarded = Task { @MainActor in
            await manager.acceptLocalForward(
                generation: attemptA.generation,
                attemptID: attemptA.id,
                remotePort: attemptA.remotePort,
                openChannel: { port in
                    seenPort = port
                    await gate.wait()
                    throw CancellationError()
                },
                cancelConnection: { cancelled = true },
                startForward: { (_: Int) in },
                abandonForward: { (_: Int) in }
            )
        }
        await gate.enteredWait()
        #expect(seenPort == 19001)
        manager.disconnect()
        let probe = SSHConnectProbe()
        manager.tunnelConnector = { config in
            await probe.open(config)
        }
        manager.config = SSHTunnelConfig(isEnabled: true, host: "b.example", port: 22, username: "opencode", remotePort: 19002)
        let connecting = Task { await manager.connect() }
        await probe.waitUntilOpened(1)
        probe.releaseOldest()
        await connecting.value
        #expect(manager.status == .connected)
        #expect(manager.connectedRemotePortForTesting == 19002)
        gate.release()
        await forwarded.value
        #expect(cancelled)
        #expect(manager.status == .connected)
        #expect(manager.connectedRemotePortForTesting == 19002)
        manager.disconnect()
    }

    @Test @MainActor func unreadableBlobKeepsBytesAndSelectedID() throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let selected = UUID()
        assertUnreadableBlobPreserved(Data(), selectedID: selected)
        assertUnreadableBlobPreserved(Data("{".utf8), selectedID: selected)

        let emptySuite = "opencode.w04.empty-array.\(UUID().uuidString)"
        let emptyDefaults = UserDefaults(suiteName: emptySuite)!
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        emptyDefaults.set(try JSONEncoder().encode([HostProfile]()), forKey: AppState.hostProfilesKey)
        emptyDefaults.set("http://127.0.0.1:4010", forKey: AppState.serverURLKey)
        let migrated = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: emptyDefaults),
            clientCapabilityStore: tempStore(emptySuite),
            userDefaults: emptyDefaults,
            hostCredentialAccess: .noExternal
        )
        defer {
            migrated.disconnectSSE()
            migrated.sshTunnelManager.disconnect()
        }
        #expect(migrated.hostProfileBlobUnreadable == false)
        #expect(migrated.currentHostProfile?.serverURL == "http://127.0.0.1:4010")
        #expect(emptyDefaults.data(forKey: AppState.hostProfilesKey) != nil)
    }

    @Test @MainActor func legacyCredentialFailureDoesNotCommitMigration() throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }
        let expected = L10n.t(.keychainErrorUnhandledStatus, Int32(errSecInteractionNotAllowed))

        let saveSuite = "opencode.w04.legacy-save.\(UUID().uuidString)"
        let saveDefaults = UserDefaults(suiteName: saveSuite)!
        defer { saveDefaults.removePersistentDomain(forName: saveSuite) }
        saveDefaults.set("admin", forKey: AppState.usernameKey)
        let saveFake = CredentialFake()
        saveFake.saved[AppState.passwordKeychainKey] = "legacy-secret"
        saveFake.saveError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        let saveFailed = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: saveDefaults),
            clientCapabilityStore: tempStore(saveSuite),
            userDefaults: saveDefaults,
            hostCredentialAccess: saveFake.access()
        )
        saveFailed.disconnectSSE()
        saveFailed.sshTunnelManager.disconnect()
        #expect(saveDefaults.data(forKey: AppState.hostProfilesKey) == nil)
        #expect(saveDefaults.string(forKey: AppState.currentHostProfileIDKey) == nil)
        #expect(saveFailed.hostCredentialError == expected)
        #expect(saveFailed.hostProfileBlobUnreadable)
        #expect(saveFake.saved[AppState.passwordKeychainKey] == "legacy-secret")
        saveFake.saveError = nil
        let saveRetried = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: saveDefaults),
            clientCapabilityStore: tempStore("\(saveSuite).retry"),
            userDefaults: saveDefaults,
            hostCredentialAccess: saveFake.access()
        )
        defer {
            saveRetried.disconnectSSE()
            saveRetried.sshTunnelManager.disconnect()
        }
        #expect(saveRetried.hostProfileBlobUnreadable == false)
        #expect(saveRetried.hostCredentialError == nil)
        #expect(saveRetried.currentHostProfile?.basicAuth?.username == "admin")
        let savedID = try #require(saveRetried.currentHostProfile?.basicAuth?.keychainPasswordID)
        #expect(saveFake.saved[savedID] == "legacy-secret")
        #expect(saveFake.saved[AppState.passwordKeychainKey] == "legacy-secret")
        #expect(saveDefaults.data(forKey: AppState.hostProfilesKey) != nil)

        let loadSuite = "opencode.w04.legacy-load.\(UUID().uuidString)"
        let loadDefaults = UserDefaults(suiteName: loadSuite)!
        defer { loadDefaults.removePersistentDomain(forName: loadSuite) }
        loadDefaults.set("admin", forKey: AppState.usernameKey)
        let loadFake = CredentialFake()
        loadFake.saved[AppState.passwordKeychainKey] = "legacy-secret"
        loadFake.loadError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        let loadFailed = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: loadDefaults),
            clientCapabilityStore: tempStore(loadSuite),
            userDefaults: loadDefaults,
            hostCredentialAccess: loadFake.access()
        )
        loadFailed.disconnectSSE()
        loadFailed.sshTunnelManager.disconnect()
        #expect(loadDefaults.data(forKey: AppState.hostProfilesKey) == nil)
        #expect(loadFailed.hostCredentialError == expected)
        #expect(loadFake.saved[AppState.passwordKeychainKey] == "legacy-secret")
        #expect(loadFake.deleted.isEmpty)
        loadFake.loadError = nil
        let loadRetried = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: loadDefaults),
            clientCapabilityStore: tempStore("\(loadSuite).retry"),
            userDefaults: loadDefaults,
            hostCredentialAccess: loadFake.access()
        )
        defer {
            loadRetried.disconnectSSE()
            loadRetried.sshTunnelManager.disconnect()
        }
        #expect(loadRetried.hostProfileBlobUnreadable == false)
        #expect(loadRetried.currentHostProfile?.basicAuth != nil)
        let loadedID = try #require(loadRetried.currentHostProfile?.basicAuth?.keychainPasswordID)
        #expect(loadFake.saved[loadedID] == "legacy-secret")
        #expect(loadDefaults.data(forKey: AppState.hostProfilesKey) != nil)
    }

    @Test @MainActor func failedHostStartupDoesNotConsumeFlatPreferences() throws {
        let previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        defer { restoreSSHConfig(previousSSHConfig) }

        let blobSuite = "opencode.w04.flat-blob.\(UUID().uuidString)"
        let blobDefaults = UserDefaults(suiteName: blobSuite)!
        defer { blobDefaults.removePersistentDomain(forName: blobSuite) }
        let blob = Data("{".utf8)
        let blobDraft = try JSONEncoder().encode(["s-blob": "blob-draft"])
        let blobModel = try JSONEncoder().encode(["s-blob": "openai/blob"])
        blobDefaults.set(blob, forKey: AppState.hostProfilesKey)
        blobDefaults.set(blobDraft, forKey: AppState.draftInputsBySessionKey)
        blobDefaults.set(blobModel, forKey: AppState.selectedModelBySessionKey)
        let blobFailed = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: blobDefaults),
            clientCapabilityStore: tempStore(blobSuite),
            userDefaults: blobDefaults,
            hostCredentialAccess: .noExternal
        )
        defer {
            blobFailed.disconnectSSE()
            blobFailed.sshTunnelManager.disconnect()
        }
        let blobTempID = blobFailed.currentHostProfileID
        #expect(blobFailed.hostProfileBlobUnreadable)
        #expect(blobFailed.draftText(for: "s-blob") == "")
        #expect(blobFailed.selectedModelIDBySessionID["s-blob"] == nil)
        #expect(blobDefaults.data(forKey: AppState.hostProfilesKey) == blob)
        #expect(blobDefaults.data(forKey: AppState.draftInputsBySessionKey) == blobDraft)
        #expect(blobDefaults.data(forKey: AppState.selectedModelBySessionKey) == blobModel)
        #expect(blobDefaults.data(forKey: AppState.draftInputsByHostKey) == nil)
        #expect(blobDefaults.data(forKey: AppState.selectedModelByHostKey) == nil)

        let formal = directProfile(name: "Formal", url: "http://127.0.0.1:4010")
        blobDefaults.set(try JSONEncoder().encode([formal]), forKey: AppState.hostProfilesKey)
        blobDefaults.set(formal.id.uuidString, forKey: AppState.currentHostProfileIDKey)
        let blobRecovered = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: blobDefaults),
            clientCapabilityStore: tempStore("\(blobSuite).retry"),
            userDefaults: blobDefaults,
            hostCredentialAccess: .noExternal
        )
        defer {
            blobRecovered.disconnectSSE()
            blobRecovered.sshTunnelManager.disconnect()
        }
        #expect(blobRecovered.hostProfileBlobUnreadable == false)
        #expect(blobRecovered.currentHostProfileID == formal.id)
        #expect(blobRecovered.currentHostProfileID != blobTempID)
        #expect(blobRecovered.draftText(for: "s-blob") == "blob-draft")
        #expect(blobRecovered.selectedModelIDBySessionID["s-blob"] == "openai/blob")
        #expect(blobDefaults.data(forKey: AppState.draftInputsBySessionKey) == nil)
        #expect(blobDefaults.data(forKey: AppState.selectedModelBySessionKey) == nil)
        let blobDrafts = try decodeHostMap(blobDefaults, AppState.draftInputsByHostKey)
        let blobModels = try decodeHostMap(blobDefaults, AppState.selectedModelByHostKey)
        #expect(blobDrafts[formal.id.uuidString]?["s-blob"] == "blob-draft")
        #expect(blobModels[formal.id.uuidString]?["s-blob"] == "openai/blob")
        #expect(blobDrafts[blobTempID.uuidString] == nil)
        #expect(blobModels[blobTempID.uuidString] == nil)

        let legacySuite = "opencode.w04.flat-legacy.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        let legacyDraft = try JSONEncoder().encode(["s-legacy": "legacy-draft"])
        let legacyModel = try JSONEncoder().encode(["s-legacy": "openai/legacy"])
        legacyDefaults.set("admin", forKey: AppState.usernameKey)
        legacyDefaults.set(legacyDraft, forKey: AppState.draftInputsBySessionKey)
        legacyDefaults.set(legacyModel, forKey: AppState.selectedModelBySessionKey)
        let legacyFake = CredentialFake()
        legacyFake.saved[AppState.passwordKeychainKey] = "legacy-secret"
        legacyFake.saveError = KeychainError.unhandledStatus(errSecInteractionNotAllowed)
        let legacyFailed = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: legacyDefaults),
            clientCapabilityStore: tempStore(legacySuite),
            userDefaults: legacyDefaults,
            hostCredentialAccess: legacyFake.access()
        )
        defer {
            legacyFailed.disconnectSSE()
            legacyFailed.sshTunnelManager.disconnect()
        }
        let legacyTempID = legacyFailed.currentHostProfileID
        #expect(legacyFailed.hostProfileBlobUnreadable)
        #expect(legacyFailed.draftText(for: "s-legacy") == "")
        #expect(legacyFailed.selectedModelIDBySessionID["s-legacy"] == nil)
        #expect(legacyDefaults.data(forKey: AppState.hostProfilesKey) == nil)
        #expect(legacyDefaults.data(forKey: AppState.draftInputsBySessionKey) == legacyDraft)
        #expect(legacyDefaults.data(forKey: AppState.selectedModelBySessionKey) == legacyModel)
        #expect(legacyDefaults.data(forKey: AppState.draftInputsByHostKey) == nil)
        #expect(legacyDefaults.data(forKey: AppState.selectedModelByHostKey) == nil)
        #expect(legacyFake.saved[AppState.passwordKeychainKey] == "legacy-secret")

        legacyFake.saveError = nil
        let legacyRecovered = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: legacyDefaults),
            clientCapabilityStore: tempStore("\(legacySuite).retry"),
            userDefaults: legacyDefaults,
            hostCredentialAccess: legacyFake.access()
        )
        defer {
            legacyRecovered.disconnectSSE()
            legacyRecovered.sshTunnelManager.disconnect()
        }
        #expect(legacyRecovered.hostProfileBlobUnreadable == false)
        #expect(legacyRecovered.currentHostProfileID != legacyTempID)
        #expect(legacyRecovered.draftText(for: "s-legacy") == "legacy-draft")
        #expect(legacyRecovered.selectedModelIDBySessionID["s-legacy"] == "openai/legacy")
        #expect(legacyDefaults.data(forKey: AppState.draftInputsBySessionKey) == nil)
        #expect(legacyDefaults.data(forKey: AppState.selectedModelBySessionKey) == nil)
        #expect(legacyDefaults.data(forKey: AppState.hostProfilesKey) != nil)
        let legacyDrafts = try decodeHostMap(legacyDefaults, AppState.draftInputsByHostKey)
        let legacyModels = try decodeHostMap(legacyDefaults, AppState.selectedModelByHostKey)
        let formalLegacyID = legacyRecovered.currentHostProfileID.uuidString
        #expect(legacyDrafts[formalLegacyID]?["s-legacy"] == "legacy-draft")
        #expect(legacyModels[formalLegacyID]?["s-legacy"] == "openai/legacy")
        #expect(legacyDrafts[legacyTempID.uuidString] == nil)
        #expect(legacyModels[legacyTempID.uuidString] == nil)
    }
}

@MainActor
private func assertUnreadableBlobPreserved(_ blob: Data, selectedID: UUID) {
    let suite = "opencode.w04.blob.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(blob, forKey: AppState.hostProfilesKey)
    defaults.set(selectedID.uuidString, forKey: AppState.currentHostProfileIDKey)
    let state = AppState(
        apiClient: MockAPIClient(),
        sseClient: MockSSEClient(),
        sshTunnelManager: SSHTunnelManager(defaults: defaults),
        clientCapabilityStore: tempStore(suite),
        userDefaults: defaults
    ,
            hostCredentialAccess: .noExternal)
    defer {
        state.disconnectSSE()
        state.sshTunnelManager.disconnect()
    }
    #expect(state.hostProfileBlobUnreadable)
    #expect(state.hostProfileLoadError == L10n.t(.hostConnectionErrorGeneric))
    #expect(defaults.data(forKey: AppState.hostProfilesKey) == blob)
    #expect(defaults.string(forKey: AppState.currentHostProfileIDKey) == selectedID.uuidString)
    let fallbackID = state.currentHostProfileID
    #expect(state.hostProfiles.contains(where: { $0.id == fallbackID }))
    state.serverURL = "http://127.0.0.1:4019"
    state.persistRuntimeToCurrentHostProfile()
    #expect(state.currentHostProfile?.id == fallbackID)
    #expect(state.currentHostProfile?.serverURL == "http://127.0.0.1:4019")
    #expect(defaults.data(forKey: AppState.hostProfilesKey) == blob)
    #expect(defaults.string(forKey: AppState.currentHostProfileIDKey) == selectedID.uuidString)
    state.currentHostProfileID = UUID()
    #expect(defaults.string(forKey: AppState.currentHostProfileIDKey) == selectedID.uuidString)
}

private func directProfile(id: UUID = UUID(), name: String, url: String) -> HostProfile {
    HostProfile(id: id, name: name, transport: .direct, serverURL: url, basicAuth: nil, ssh: nil, lastUsedAt: nil)
}

private func makeHostSession(id: String) -> Session {
    Session(
        id: id,
        slug: id,
        projectID: "p",
        directory: "/tmp",
        parentID: nil,
        title: id,
        version: "1",
        time: .init(created: 1, updated: 1, archived: nil),
        share: nil,
        summary: nil
    )
}

private func decodeHostMap(_ defaults: UserDefaults, _ key: String) throws -> [String: [String: String]] {
    let data = try #require(defaults.data(forKey: key))
    return try JSONDecoder().decode([String: [String: String]].self, from: data)
}

private func restoreSSHConfig(_ previous: Any?) {
    if let previous {
        UserDefaults.standard.set(previous, forKey: "sshTunnelConfig")
    } else {
        UserDefaults.standard.removeObject(forKey: "sshTunnelConfig")
    }
}

private func tempStore(_ name: String) -> ClientCapabilityCallbackStore {
    ClientCapabilityCallbackStore(rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true))
}

@MainActor
private struct LifecycleHarness {
    let state: AppState
    let defaults: UserDefaults
    let suite: String
    let storeRoot: URL
    let previousSSHConfig: Any?

    init(api: APIClientProtocol = MockAPIClient(), ssh: SSHTunnelManager? = nil) {
        suite = "opencode.w04.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        storeRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        seedHostProfile(in: defaults)
        let tunnel = ssh ?? SSHTunnelManager(defaults: defaults)
        state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: tunnel,
            clientCapabilityStore: ClientCapabilityCallbackStore(rootDirectory: storeRoot),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
    }

    func cleanup() {
        state.disconnectSSE()
        state.sshTunnelManager.disconnect()
        state.hostTransportConfigureTask?.cancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: storeRoot)
        restoreSSHConfig(previousSSHConfig)
    }
}

@MainActor
private final class CredentialFake {
    var saveError: Error?
    var loadError: Error?
    var saved: [String: String] = [:]
    var deleted: [String] = []

    func access() -> HostCredentialAccess {
        HostCredentialAccess(
            save: { [weak self] value, key in
                if let saveError = self?.saveError { throw saveError }
                self?.saved[key] = value
            },
            load: { [weak self] key in
                if let loadError = self?.loadError { throw loadError }
                return self?.saved[key]
            },
            delete: { [weak self] key in
                self?.deleted.append(key)
                self?.saved.removeValue(forKey: key)
            }
        )
    }
}

@MainActor
private final class SSHConnectProbe {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    private(set) var snapshots: [SSHTunnelConfig] = []
    private(set) var closedPorts: [Int] = []

    func open(_ config: SSHTunnelConfig) async -> SSHOpenedTunnel {
        snapshots.append(config)
        let port = config.remotePort
        let tunnel = SSHOpenedTunnel(remotePort: port) { [weak self] in
            self?.closedPorts.append(port)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
            let pending = observers
            observers.removeAll()
            pending.forEach { $0.resume() }
        }
        return tunnel
    }

    func waitUntilOpened(_ count: Int) async {
        while snapshots.count < count {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                observers.append(cont)
            }
        }
    }

    func releaseOldest() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

@MainActor
private final class ListenerTaskHolder {
    var task: Task<Void, Error>?
}

@MainActor
private final class PauseGate {
    private var entered: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            releaseWaiter = cont
            entered?.resume()
            entered = nil
        }
    }

    func enteredWait() async {
        if releaseWaiter != nil || released { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if releaseWaiter != nil || released {
                cont.resume()
            } else {
                entered = cont
            }
        }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
        entered?.resume()
        entered = nil
    }
}

private final class RaceGate {
    var consumed = false
    var paused = false
    var released = false
    var repeatable = false
    var pauseCount = 0
    var waiters: [CheckedContinuation<Void, Never>] = []
    var observers: [CheckedContinuation<Void, Never>] = []
}

private actor HostRaceAPI: APIClientProtocol {
    private let base = MockAPIClient()
    private var gates: [String: RaceGate] = [:]
    private var failures: [String: Error] = [:]
    private var healthResult = HealthResponse(healthy: true, version: "test")
    private var projectsResult: [Project] = []
    private var created = Session(
        id: "created-a",
        slug: "created-a",
        projectID: "p",
        directory: "/tmp",
        parentID: nil,
        title: "created-a",
        version: "1",
        time: .init(created: 1, updated: 1, archived: nil),
        share: nil,
        summary: nil
    )
    private var forked = Session(
        id: "forked-a",
        slug: "forked-a",
        projectID: "p",
        directory: "/tmp",
        parentID: "s-a",
        title: "forked-a",
        version: "1",
        time: .init(created: 2, updated: 2, archived: nil),
        share: nil,
        summary: nil
    )

    func arm(_ names: [String]) {
        for name in names {
            gates[name] = RaceGate()
        }
    }

    func armRepeated(_ names: [String]) {
        for name in names {
            let gate = RaceGate()
            gate.repeatable = true
            gates[name] = gate
        }
    }

    func waitUntilPauseCount(_ name: String, _ count: Int) async {
        while true {
            if (gates[name]?.pauseCount ?? 0) >= count { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if (gates[name]?.pauseCount ?? 0) >= count {
                    cont.resume()
                } else {
                    gates[name]?.observers.append(cont)
                }
            }
        }
    }

    func releaseNext(_ name: String) {
        guard let gate = gates[name], !gate.waiters.isEmpty else { return }
        gate.waiters.removeFirst().resume()
    }

    func fail(_ names: [String], _ error: Error) {
        for name in names {
            failures[name] = error
        }
    }

    func setHealth(_ response: HealthResponse) {
        healthResult = response
    }

    func setSessions(_ sessions: [Session]) async {
        await base.setSessionsResult(sessions)
    }

    func setAgents(_ agents: [AgentInfo]) async {
        await base.setAgentsResult(agents)
    }

    func setProjects(_ projects: [Project]) {
        projectsResult = projects
    }

    func setCreated(_ session: Session) {
        created = session
    }

    func setForked(_ session: Session) {
        forked = session
    }

    func waitUntilPaused(_ name: String) async {
        guard let gate = gates[name] else { return }
        if gate.paused { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if gate.paused {
                cont.resume()
            } else {
                gate.observers.append(cont)
            }
        }
    }

    func releaseAll() {
        for gate in gates.values {
            gate.released = true
            let waiters = gate.waiters
            gate.waiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    private func pause(_ name: String) async throws {
        if let gate = gates[name], gate.repeatable {
            gate.pauseCount += 1
            gate.paused = true
            let observers = gate.observers
            gate.observers.removeAll()
            observers.forEach { $0.resume() }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                gate.waiters.append(cont)
            }
            if let error = failures[name] {
                throw error
            }
            return
        }
        if let gate = gates[name], !gate.consumed {
            gate.consumed = true
            gate.paused = true
            let observers = gate.observers
            gate.observers.removeAll()
            observers.forEach { $0.resume() }
            if !gate.released {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    if gate.released {
                        cont.resume()
                    } else {
                        gate.waiters.append(cont)
                    }
                }
            }
        }
        if let error = failures[name] {
            throw error
        }
    }

    func configure(baseURL: String, username: String?, password: String?) {}

    func health() async throws -> HealthResponse {
        try await pause("health")
        return healthResult
    }

    func projects() async throws -> [Project] {
        try await pause("projects")
        return projectsResult
    }

    func projectCurrent() async throws -> Project? { nil }

    func sessions(directory: String?, limit: Int) async throws -> [Session] {
        try await pause("sessions")
        return try await base.sessions(directory: directory, limit: limit)
    }

    func session(sessionID: String) async throws -> Session {
        try await base.session(sessionID: sessionID)
    }

    func createSession(title: String?, directory: String?) async throws -> Session {
        try await pause("create")
        return created
    }

    func updateSession(sessionID: String, title: String) async throws -> Session {
        try await base.updateSession(sessionID: sessionID, title: title)
    }

    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        try await base.updateSessionArchived(sessionID: sessionID, archived: archived)
    }

    func deleteSession(sessionID: String) async throws {
        try await base.deleteSession(sessionID: sessionID)
    }

    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] {
        try await base.messages(sessionID: sessionID, limit: limit)
    }

    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {
        try await base.promptAsync(sessionID: sessionID, messageID: messageID, text: text, attachments: attachments, agent: agent, model: model, directory: directory)
    }

    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
        try await base.promptStructured(sessionID: sessionID, messageID: messageID, text: text, system: system, format: format, agent: agent, model: model)
    }

    func abort(sessionID: String) async throws {
        try await base.abort(sessionID: sessionID)
    }

    func sessionStatus() async throws -> [String: SessionStatus] { [:] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
    func pendingQuestions() async throws -> [QuestionRequest] { [] }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(requestID: String) async throws {}

    func providers() async throws -> ProvidersResponse {
        try await pause("providers")
        return try await base.providers()
    }

    func providerRegistry() async throws -> ProviderRegistryResponse {
        try await base.providerRegistry()
    }

    func agents() async throws -> [AgentInfo] {
        try await pause("agents")
        return try await base.agents()
    }

    func sessionDiff(sessionID: String) async throws -> [FileDiff] { [] }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
    func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }
    func fileContent(path: String, directory: String?) async throws -> FileContent {
        FileContent(type: "text", content: "")
    }
    func findFile(query: String, limit: Int) async throws -> [String] { [] }
    func fileStatus() async throws -> [FileStatusEntry] { [] }

    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        try await pause("fork")
        return forked
    }

    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        try await base.revertSession(sessionID: sessionID, messageID: messageID, partID: partID)
    }
}
