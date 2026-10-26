import Foundation
import Testing
@testable import OpenCodeClient

@Suite(.serialized)
struct FileFlowTests {
    @Test @MainActor func failedCreationReportsFailureWithoutReplacingExistingSelection() async {
        let harness = FileFlowHarness(api: FileFlowAPI())
        defer { harness.cleanup() }
        harness.state.isConnected = true
        harness.state.currentSessionID = "existing"
        let created = await harness.state.createSession()
        #expect(!created)
        #expect(harness.state.currentSessionID == "existing")
        #expect(harness.state.connectionError != nil)
    }

    @Test @MainActor func failedRootRefreshPreservesPreviouslyLoadedFiles() async {
        let api = FileFlowAPI()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        await api.succeedList("", [fileNode("README.md")])
        await harness.state.loadFileTree()
        await api.failList("")
        await harness.state.loadFileTree()
        #expect(harness.state.fileTreeRoot.map(\.path) == ["README.md"])
        #expect(harness.state.fileStore.fileTreeError != nil)
        #expect(!harness.state.fileStore.isLoadingFileTree)
        await api.succeedList("", [])
        await harness.state.loadFileTree()
        #expect(harness.state.fileTreeRoot.isEmpty)
        #expect(harness.state.fileStore.fileTreeError == nil)
    }

    @Test @MainActor func lateRootFailureDoesNotOverwriteNewerSuccess() async {
        let api = FileFlowAPI()
        await api.pauseLists()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let first = Task { await harness.state.loadFileTree() }
        await api.waitUntilListStarted(1)
        let second = Task { await harness.state.loadFileTree() }
        await api.waitUntilListStarted(2)
        await api.releaseLastList(.success([fileNode("new.swift")]))
        await second.value
        await api.releaseFirstList(.failure(FileFlowError()))
        await first.value
        #expect(harness.state.fileTreeRoot.map(\.path) == ["new.swift"])
        #expect(harness.state.fileStore.fileTreeError == nil)
        #expect(!harness.state.fileStore.isLoadingFileTree)
    }

    @Test @MainActor func failedChildRefreshPreservesCacheAndCancellationIsNotAnError() async {
        let api = FileFlowAPI()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        await api.succeedList("src", [fileNode("src/kept.swift")])
        _ = await harness.state.loadFileChildren(path: "src")
        await api.failList("src")
        _ = await harness.state.loadFileChildren(path: "src")
        #expect(harness.state.cachedChildren(for: "src")?.map(\.path) == ["src/kept.swift"])
        #expect(harness.state.fileStore.fileChildrenErrors["src"] != nil)
        await api.pauseLists()
        let cancelled = Task { await harness.state.loadFileChildren(path: "src") }
        await api.waitUntilListStarted(1)
        await api.releaseFirstList(.failure(CancellationError()))
        _ = await cancelled.value
        #expect(harness.state.cachedChildren(for: "src")?.map(\.path) == ["src/kept.swift"])
        #expect(harness.state.fileStore.fileChildrenErrors["src"] == nil)
    }

    @Test @MainActor func hostOrRevisionChangeChangesLoadKey() async throws {
        let api = FileFlowAPI()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        let before = FileContentLoadKey.current(state: state, path: "README.md", workspaceDirectory: "/ws", revision: 0)
        var other = HostProfile.defaultProfile(serverURL: "http://127.0.0.1:4020")
        other.name = "Other"
        state.hostProfiles.append(other)
        state.beginHostTransportTransition(to: other.id)
        let afterHost = FileContentLoadKey.current(state: state, path: "README.md", workspaceDirectory: "/ws", revision: 0)
        #expect(before.host != afterHost.host)
        #expect(before != afterHost)
        let refreshed = FileContentLoadKey.current(state: state, path: "README.md", workspaceDirectory: "/ws", revision: 1)
        #expect(refreshed != afterHost)
        #expect(refreshed.path == afterHost.path)
        #expect(refreshed.workspaceDirectory == afterHost.workspaceDirectory)
    }

    @Test @MainActor func oldSearchResultDoesNotOverwriteNewQuery() async {
        let api = FileFlowAPI()
        await api.gateFind("a")
        await api.gateFind("b")
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.fileSearchQuery = "a"
        state.fileStore.fileSearchGeneration = 1
        let host = state.captureHostRequestSnapshot()
        let old = Task {
            await state.searchFiles(query: "a", generation: 1, host: host, directory: state.effectiveProjectDirectory)
        }
        await api.waitUntilFindStarted("a")
        state.fileSearchQuery = "b"
        state.fileStore.fileSearchGeneration = 2
        state.fileStore.fileSearchOwner = host
        state.fileStore.fileSearchDirectory = state.effectiveProjectDirectory
        state.fileSearchResults = []
        state.fileStore.fileSearchInFlight = true
        await api.releaseFind("a", .success(["a.md"]))
        await old.value
        #expect(state.fileSearchResults.isEmpty)
        #expect(state.fileSearchListState == .loading)
        let newer = Task {
            await state.searchFiles(query: "b", generation: 2, host: host, directory: state.effectiveProjectDirectory)
        }
        await api.waitUntilFindStarted("b")
        await api.releaseFind("b", .success(["b.md"]))
        await newer.value
        #expect(state.fileSearchResults == ["b.md"])
        #expect(state.fileSearchListState == .results(["b.md"]))
    }

    @Test @MainActor func clearingQueryDropsInFlightSearchAndReturnsTree() async {
        let api = FileFlowAPI()
        await api.gateFind("notes")
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.fileSearchQuery = "notes"
        state.fileStore.fileSearchGeneration = 1
        state.fileStore.fileSearchOwner = state.captureHostRequestSnapshot()
        state.fileStore.fileSearchDirectory = state.effectiveProjectDirectory
        let host = state.captureHostRequestSnapshot()
        let task = Task {
            await state.searchFiles(query: "notes", generation: 1, host: host, directory: state.effectiveProjectDirectory)
        }
        await api.waitUntilFindStarted("notes")
        let generation = state.fileStore.fileSearchGeneration
        state.fileSearchQuery = ""
        state.fileSearchQueryChanged("")
        #expect(state.fileStore.fileSearchGeneration == generation + 1)
        await api.releaseFind("notes", .success(["notes.txt"]))
        await task.value
        #expect(state.fileSearchResults.isEmpty)
        #expect(state.fileSearchQuery.isEmpty)
        #expect(state.fileSearchListState == .tree)
    }

    @Test @MainActor func searchRequestUsesFilesDirectoryNotSession() async {
        let api = FileFlowAPI()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.selectedProjectWorktree = "/ws-b"
        state.sessions = [
            Session(
                id: "s-a",
                slug: "s-a",
                projectID: "p1",
                directory: "/ws-a",
                parentID: nil,
                title: "A",
                version: "1",
                time: .init(created: 1, updated: 2, archived: nil),
                share: nil,
                summary: nil
            )
        ]
        state.currentSessionID = "s-a"
        let host = state.captureHostRequestSnapshot()
        state.fileSearchQuery = "notes"
        state.fileStore.fileSearchGeneration = 1
        state.fileStore.fileSearchOwner = host
        state.fileStore.fileSearchDirectory = "/ws-b"
        await state.searchFiles(query: "notes", generation: 1, host: host, directory: state.effectiveProjectDirectory)
        #expect(await api.findDirectories(for: "notes") == ["/ws-b"])
        #expect(state.effectiveProjectDirectory == "/ws-b")
        #expect(state.currentSession?.directory == "/ws-a")
    }

    @Test @MainActor func searchListStatesStayDistinct() {
        let harness = FileFlowHarness(api: FileFlowAPI())
        defer { harness.cleanup() }
        let state = harness.state
        state.fileStore.fileSearchOwner = state.captureHostRequestSnapshot()
        state.fileStore.fileSearchDirectory = state.effectiveProjectDirectory
        state.fileSearchQuery = "q"
        state.fileStore.fileSearchInFlight = true
        #expect(state.fileSearchListState == .loading)
        state.fileStore.fileSearchInFlight = false
        #expect(state.fileSearchListState == .empty)
        state.fileStore.fileSearchFailed = true
        state.fileStore.fileSearchError = "boom"
        #expect(state.fileSearchListState == .failed("boom"))
        state.fileSearchResults = ["hit.txt"]
        state.fileStore.fileSearchFailed = false
        #expect(state.fileSearchListState == .results(["hit.txt"]))
        state.fileSearchQuery = ""
        #expect(state.fileSearchListState == .tree)
    }

    @Test @MainActor func failedDirectoryDoesNotCacheEmptyAndLaterExpandRetries() async {
        let api = FileFlowAPI()
        await api.failList("src")
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        let failed = await state.loadFileChildren(path: "src")
        #expect(failed.isEmpty)
        #expect(state.cachedChildren(for: "src") == nil)
        #expect(state.fileStore.fileChildrenErrors["src"] != nil)
        #expect(await api.listCount(for: "src") == 1)

        await api.succeedList("src", [fileNode("src/main.swift")])
        let loaded = await state.loadFileChildren(path: "src")
        #expect(loaded.map(\.path) == ["src/main.swift"])
        #expect(state.cachedChildren(for: "src")?.map(\.path) == ["src/main.swift"])
        #expect(state.fileStore.fileChildrenErrors["src"] == nil)
        #expect(await api.listCount(for: "src") == 2)
    }

    @Test @MainActor func successfulEmptyDirectoryIsCachedAndDistinctFromFailure() async {
        let api = FileFlowAPI()
        await api.succeedList("empty", [])
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        let loaded = await state.loadFileChildren(path: "empty")
        #expect(loaded.isEmpty)
        #expect(state.cachedChildren(for: "empty")?.isEmpty == true)
        #expect(state.cachedChildren(for: "missing") == nil)
    }

    @Test @MainActor func lateDirectoryFailureDoesNotEraseNewerSuccess() async {
        let api = FileFlowAPI()
        await api.pauseLists()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        let first = Task { await state.loadFileChildren(path: "src") }
        await api.waitUntilListStarted(1)
        let second = Task { await state.loadFileChildren(path: "src") }
        await api.waitUntilListStarted(2)
        await api.releaseLastList(.success([fileNode("src/main.swift")]))
        let secondResult = await second.value
        #expect(secondResult.map(\.path) == ["src/main.swift"])
        await api.releaseFirstList(.failure(FileFlowError()))
        let firstResult = await first.value
        #expect(firstResult.isEmpty)
        #expect(state.cachedChildren(for: "src")?.map(\.path) == ["src/main.swift"])
    }

    @Test @MainActor func samePathChildrenFromOtherWorkspaceOrHostDoNotApply() async {
        let api = FileFlowAPI()
        await api.pauseLists()
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.selectedProjectWorktree = "/ws-a"
        let workspaceTask = Task { await state.loadFileChildren(path: "README.md") }
        await api.waitUntilListStarted(1)
        state.selectedProjectWorktree = "/ws-b"
        await api.releaseFirstList(.success([fileNode("README.md")]))
        _ = await workspaceTask.value
        #expect(state.cachedChildren(for: "README.md") == nil)

        await api.pauseLists()
        state.selectedProjectWorktree = "/ws-b"
        let hostTask = Task { await state.loadFileChildren(path: "README.md") }
        await api.waitUntilListStarted(2)
        var other = HostProfile.defaultProfile(serverURL: "http://127.0.0.1:4030")
        other.name = "Other"
        state.hostProfiles.append(other)
        state.beginHostTransportTransition(to: other.id)
        await api.releaseFirstList(.success([fileNode("README.md")]))
        _ = await hostTask.value
        #expect(state.cachedChildren(for: "README.md") == nil)
    }

    @Test @MainActor func rootRefreshKeepsChildSuccessIncludingEmpty() async {
        let api = FileFlowAPI()
        await api.pauseList("")
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.selectedProjectWorktree = "/ws-b"
        let scope = FileChildrenScope(host: state.captureHostRequestSnapshot(), directory: "/ws-b")
        state.fileStore.fileChildrenScope = scope
        state.fileTreeRoot = [directoryNode("src")]
        state.expandedPaths = ["src"]
        state.fileChildrenCache = [:]

        let root = Task { await state.loadFileTree() }
        await api.waitUntilListStarted(1)
        await api.succeedList("src", [fileNode("src/main.swift")])
        let loaded = await state.loadFileChildren(path: "src")
        #expect(loaded.map(\.path) == ["src/main.swift"])
        await api.releaseFirstList(.success([directoryNode("src")]))
        await root.value
        #expect(state.expandedPaths.contains("src"))
        #expect(state.cachedChildren(for: "src")?.map(\.path) == ["src/main.swift"])

        await api.pauseList("")
        let second = Task { await state.loadFileTree() }
        await api.waitUntilListStarted(2)
        await api.succeedList("src", [])
        let emptied = await state.loadFileChildren(path: "src")
        #expect(emptied.isEmpty)
        #expect(state.cachedChildren(for: "src")?.isEmpty == true)
        await api.releaseFirstList(.success([directoryNode("src")]))
        await second.value
        #expect(state.expandedPaths.contains("src"))
        #expect(state.cachedChildren(for: "src")?.isEmpty == true)
    }

    @Test @MainActor func switchingRootScopeHidesOldRowsAndOpensSameNameInNewScope() async throws {
        let api = FileFlowAPI()
        await api.succeedList("", [fileNode("notes.txt")])
        await api.succeedList("src", [fileNode("src/a.swift")])
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.selectedProjectWorktree = "/ws-a"
        await state.loadFileTree()
        state.expandedPaths = ["src"]
        _ = await state.loadFileChildren(path: "src")
        #expect(state.visibleFileTreeRoot.map(\.path) == ["notes.txt"])

        await api.pauseList("")
        state.selectedProjectWorktree = "/ws-b"
        let switched = Task { await state.ensureFileRootMatchesCurrentScope() }
        await api.waitUntilListStarted(1)
        #expect(state.visibleFileTreeRoot.isEmpty)
        #expect(state.fileTreeRoot.isEmpty)
        #expect(state.cachedChildren(for: "src") == nil)
        #expect(await api.listedDirectories(for: "") == ["/ws-a" as String?, "/ws-b" as String?])

        await api.succeedList("src", [fileNode("src/b.swift")])
        state.expandedPaths = ["src"]
        let current = await state.loadFileChildren(path: "src")
        #expect(current.map(\.path) == ["src/b.swift"])
        await api.releaseFirstList(.success([fileNode("notes.txt")]))
        await switched.value
        #expect(state.visibleFileTreeRoot.map(\.path) == ["notes.txt"])
        #expect(state.expandedPaths.contains("src"))
        #expect(state.cachedChildren(for: "src")?.map(\.path) == ["src/b.swift"])
        let opened = state.effectiveProjectDirectory ?? ""
        _ = try await state.loadFileContent(path: "notes.txt", workspaceDirectory: opened)
        #expect(opened == "/ws-b")
        #expect(await api.recordedContentDirectories() == ["/ws-b" as String?])
    }

    @Test @MainActor func failedNewRootLoadDoesNotRestorePreviousRoot() async {
        let api = FileFlowAPI()
        await api.succeedList("", [fileNode("notes.txt")])
        let harness = FileFlowHarness(api: api)
        defer { harness.cleanup() }
        let state = harness.state
        state.selectedProjectWorktree = "/ws-a"
        await state.loadFileTree()
        #expect(state.visibleFileTreeRoot.map(\.path) == ["notes.txt"])

        await api.pauseList("")
        state.selectedProjectWorktree = "/ws-b"
        let switched = Task { await state.ensureFileRootMatchesCurrentScope() }
        await api.waitUntilListStarted(1)
        #expect(state.visibleFileTreeRoot.isEmpty)
        await api.releaseFirstList(.failure(FileFlowError()))
        await switched.value
        #expect(state.fileTreeRoot.isEmpty)
        #expect(state.visibleFileTreeRoot.isEmpty)
        #expect(state.fileStore.fileChildrenScope?.directory == "/ws-b")
        #expect(await api.listedDirectories(for: "") == ["/ws-a" as String?, "/ws-b" as String?])
    }

    @Test @MainActor func isolatedDefaultsDoNotShareFileSearchState() {
        let first = FileFlowHarness(api: FileFlowAPI())
        let second = FileFlowHarness(api: FileFlowAPI())
        defer {
            second.cleanup()
            first.cleanup()
        }
        first.defaults.set("w06", forKey: "w06-marker")
        first.state.fileSearchQuery = "secret"
        first.state.fileSearchResults = ["secret.txt"]
        #expect(first.suite != second.suite)
        #expect(second.defaults.string(forKey: "w06-marker") == nil)
        #expect(second.state.fileSearchQuery.isEmpty)
        #expect(second.state.fileSearchResults.isEmpty)
    }
}

private func fileNode(_ path: String) -> FileNode {
    FileNode(name: (path as NSString).lastPathComponent, path: path, absolute: nil, type: "file", ignored: false)
}

private func directoryNode(_ path: String) -> FileNode {
    FileNode(name: (path as NSString).lastPathComponent, path: path, absolute: nil, type: "directory", ignored: false)
}

private struct FileFlowError: Error {}

@MainActor
private struct FileFlowHarness {
    let state: AppState
    let defaults: UserDefaults
    let suite: String
    let previousSSHConfig: Any?

    init(api: FileFlowAPI) {
        suite = "opencode.w06.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        previousSSHConfig = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: HostCredentialAccess(
                save: { _, _ in },
                load: { _ in nil },
                delete: { _ in }
            )
        )
    }

    func cleanup() {
        state.disconnectSSE()
        state.sshTunnelManager.disconnect()
        state.hostTransportConfigureTask?.cancel()
        defaults.removePersistentDomain(forName: suite)
        if let previousSSHConfig {
            UserDefaults.standard.set(previousSSHConfig, forKey: "sshTunnelConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "sshTunnelConfig")
        }
    }
}

private actor FileFlowAPI: APIClientProtocol, FileDirectorySearching {
    private var findGates: Set<String> = []
    private var findStarted: Set<String> = []
    private var findWaiters: [String: CheckedContinuation<Result<[String], Error>, Never>] = [:]
    private var findObservers: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var findResults: [String: [String]] = [:]
    private var findDirectories: [String: [String?]] = [:]
    private var listResults: [String: Result<[FileNode], Error>] = [:]
    private var pausedPaths: Set<String> = []
    private var listCounts: [String: Int] = [:]
    private var listDirectories: [String: [String?]] = [:]
    private var contentDirectories: [String?] = []
    private var listsPaused = false
    private var listStarted = 0
    private var listWaiters: [CheckedContinuation<Result<[FileNode], Error>, Never>] = []
    private var listObservers: [CheckedContinuation<Void, Never>] = []

    func gateFind(_ query: String) {
        findGates.insert(query)
    }

    func releaseFind(_ query: String, _ result: Result<[String], Error>) {
        findWaiters.removeValue(forKey: query)?.resume(returning: result)
    }

    func waitUntilFindStarted(_ query: String) async {
        if findStarted.contains(query) { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if findStarted.contains(query) {
                cont.resume()
            } else {
                findObservers[query, default: []].append(cont)
            }
        }
    }

    func findDirectories(for query: String) -> [String?] {
        findDirectories[query] ?? []
    }

    func pauseList(_ path: String) {
        pausedPaths.insert(path)
    }

    func failList(_ path: String) {
        listResults[path] = .failure(FileFlowError())
    }

    func succeedList(_ path: String, _ nodes: [FileNode]) {
        listResults[path] = .success(nodes)
    }

    func pauseLists() {
        listsPaused = true
    }

    func listCount(for path: String) -> Int {
        listCounts[path] ?? 0
    }

    func listedDirectories(for path: String) -> [String?] {
        listDirectories[path] ?? []
    }

    func recordedContentDirectories() -> [String?] {
        contentDirectories
    }

    func waitUntilListStarted(_ count: Int) async {
        if listStarted >= count { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if listStarted >= count {
                cont.resume()
            } else {
                listObservers.append(cont)
            }
        }
    }

    func releaseFirstList(_ result: Result<[FileNode], Error>) {
        guard !listWaiters.isEmpty else { return }
        listWaiters.removeFirst().resume(returning: result)
    }

    func releaseLastList(_ result: Result<[FileNode], Error>) {
        guard !listWaiters.isEmpty else { return }
        listWaiters.removeLast().resume(returning: result)
    }

    func configure(baseURL: String, username: String?, password: String?) {}
    func health() async throws -> HealthResponse { HealthResponse(healthy: true, version: "test") }
    func projects() async throws -> [Project] { [] }
    func projectCurrent() async throws -> Project? { nil }
    func sessions(directory: String?, limit: Int) async throws -> [Session] { [] }
    func session(sessionID: String) async throws -> Session {
        throw APIError.httpError(statusCode: 404, data: Data())
    }
    func createSession(title: String?, directory: String?) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func updateSession(sessionID: String, title: String) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func updateSessionArchived(sessionID: String, archived: Int) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func deleteSession(sessionID: String) async throws {}
    func messages(sessionID: String, limit: Int?) async throws -> [MessageWithParts] { [] }
    func promptAsync(sessionID: String, messageID: String, text: String, attachments: [ComposerImageAttachment], agent: String, model: Message.ModelInfo?, directory: String?) async throws {}
    func promptStructured(sessionID: String, messageID: String?, text: String, system: String, format: StructuredOutputFormat, agent: String, model: Message.ModelInfo) async throws -> MessageWithParts {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func abort(sessionID: String) async throws {}
    func sessionStatus() async throws -> [String: SessionStatus] { [:] }
    func pendingPermissions() async throws -> [APIClient.PermissionRequest] { [] }
    func respondPermission(sessionID: String, permissionID: String, response: APIClient.PermissionResponse) async throws {}
    func pendingQuestions() async throws -> [QuestionRequest] { [] }
    func replyQuestion(requestID: String, answers: [[String]]) async throws {}
    func rejectQuestion(requestID: String) async throws {}
    func providers() async throws -> ProvidersResponse {
        try JSONDecoder().decode(ProvidersResponse.self, from: Data("{\"providers\":[]}".utf8))
    }
    func providerRegistry() async throws -> ProviderRegistryResponse {
        ProviderRegistryResponse(providers: [], connectedProviderIDs: [])
    }
    func agents() async throws -> [AgentInfo] { [] }
    func sessionDiff(sessionID: String) async throws -> [FileDiff] { [] }
    func sessionTodos(sessionID: String) async throws -> [TodoItem] { [] }
    func fileList(path: String, directory: String?) async throws -> [FileNode] {
        listDirectories[path, default: []].append(directory)
        listCounts[path, default: 0] += 1
        if listsPaused || pausedPaths.contains(path) {
            listStarted += 1
            let observers = listObservers
            listObservers.removeAll()
            observers.forEach { $0.resume() }
            let result = await withCheckedContinuation { listWaiters.append($0) }
            return try result.get()
        }
        switch listResults[path] ?? .success([]) {
        case .success(let nodes):
            return nodes
        case .failure(let error):
            throw error
        }
    }
    func fileContent(path: String, directory: String?) async throws -> FileContent {
        contentDirectories.append(directory)
        return FileContent(type: "text", content: "")
    }
    func findFile(query: String, limit: Int) async throws -> [String] {
        try await findFile(query: query, limit: limit, directory: nil)
    }
    func findFile(query: String, limit: Int, directory: String?) async throws -> [String] {
        findDirectories[query, default: []].append(directory)
        if findGates.contains(query) {
            findStarted.insert(query)
            let observers = findObservers.removeValue(forKey: query) ?? []
            observers.forEach { $0.resume() }
            let result = await withCheckedContinuation { findWaiters[query] = $0 }
            return try result.get()
        }
        return findResults[query] ?? []
    }
    func fileStatus() async throws -> [FileStatusEntry] { [] }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
}
