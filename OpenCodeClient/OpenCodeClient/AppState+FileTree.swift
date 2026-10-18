import Foundation

/// File tree browsing + status + search + content loading. State
/// (`fileTreeRoot`, `fileStatusMap`, `fileChildrenCache`, `expandedPaths`,
/// `fileSearchResults`) lives on the `FileStore` and is exposed through
/// computed accessors on `AppState`. This extension hosts the user-facing
/// load actions.
enum FileSearchListState: Equatable {
    case tree
    case loading
    case empty
    case failed(String?)
    case results([String])
}

enum PreviewWorkspacePin {
    /// A provided value wins, including `""` (server default).
    /// `nil` snapshots `sessionDirectory`, or `""` when that is also missing.
    static func freeze(explicit: String?, sessionDirectory: String?) -> String {
        if let explicit {
            return explicit
        }
        if let sessionDirectory, !sessionDirectory.isEmpty {
            return sessionDirectory
        }
        return ""
    }

    /// Preview loads must not follow the live session.
    /// `nil` means the caller did not provide a workspace; `""` is the pinned server default.
    /// Both stay off the live session. `loadFileContent`'s own `nil` argument still follows it.
    static func previewDirectory(stored: String?) -> String {
        stored ?? ""
    }
}

struct FileContentLoadKey: Equatable, Sendable {
    var host: HostRequestSnapshot
    var workspaceDirectory: String?
    var path: String
    var revision: UInt64

    @MainActor
    static func current(state: AppState, path: String, workspaceDirectory: String?, revision: UInt64) -> FileContentLoadKey {
        FileContentLoadKey(
            host: state.captureHostRequestSnapshot(),
            workspaceDirectory: workspaceDirectory,
            path: path,
            revision: revision
        )
    }
}

struct ExternalFileOpenOwner: Equatable, Sendable {
    var host: HostRequestSnapshot
    var sessionID: String?
}

extension ExternalFileOpenOwner {
    init(load: FileContentLoadKey, sessionID: String?) {
        self.init(host: load.host, sessionID: sessionID)
    }
}

extension AppState {
    var fileSearchListState: FileSearchListState {
        guard !fileSearchQuery.isEmpty else { return .tree }
        guard fileSearchScopeMatches else { return .tree }
        if fileStore.fileSearchInFlight && fileSearchResults.isEmpty {
            return .loading
        }
        if fileSearchResults.isEmpty {
            return fileStore.fileSearchFailed ? .failed(fileStore.fileSearchError) : .empty
        }
        return .results(fileSearchResults)
    }

    var fileSearchScopeMatches: Bool {
        fileStore.fileSearchOwner == captureHostRequestSnapshot()
            && fileStore.fileSearchDirectory == effectiveProjectDirectory
    }

    var visibleFileTreeRoot: [FileNode] {
        let scope = FileChildrenScope(host: captureHostRequestSnapshot(), directory: effectiveProjectDirectory)
        guard fileStore.fileChildrenScope == scope else { return [] }
        return fileTreeRoot
    }

    func ensureFileRootMatchesCurrentScope() async {
        let scope = FileChildrenScope(host: captureHostRequestSnapshot(), directory: effectiveProjectDirectory)
        let changed = fileStore.fileChildrenScope != scope
        if changed {
            fileTreeRoot = []
            fileChildrenCache = [:]
            expandedPaths = []
            fileStore.fileChildrenScope = scope
        }
        if changed || fileTreeRoot.isEmpty {
            await loadFileTree()
        }
    }

    func loadFileTree() async {
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory
        do {
            let root = try await apiClient.fileList(path: "", directory: directory)
            guard isCurrentHostRequest(host), effectiveProjectDirectory == directory else { return }
            fileTreeRoot = root
            let scope = FileChildrenScope(host: host, directory: directory)
            if fileStore.fileChildrenScope == nil || fileStore.fileChildrenScope == scope {
                let expanded = expandedPaths
                fileChildrenCache = fileChildrenCache.filter { expanded.contains($0.key) }
            } else {
                fileChildrenCache = [:]
                expandedPaths = []
            }
            fileStore.fileChildrenScope = scope
        } catch {
            guard isCurrentHostRequest(host), effectiveProjectDirectory == directory else { return }
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        let host = captureHostRequestSnapshot()
        do {
            let entries = try await apiClient.fileStatus()
            guard isCurrentHostRequest(host) else { return }
            var nextStatusMap: [String: String] = [:]
            for entry in entries {
                guard let path = entry.path else { continue }
                nextStatusMap[path] = entry.status ?? ""
            }
            fileStatusMap = nextStatusMap
        } catch {
            guard isCurrentHostRequest(host) else { return }
            fileStatusMap = [:]
        }
    }

    func loadFileChildren(path: String) async -> [FileNode] {
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory
        fileStore.fileChildrenLoadGeneration[path, default: 0] &+= 1
        let generation = fileStore.fileChildrenLoadGeneration[path] ?? 0
        do {
            let children = try await apiClient.fileList(path: path, directory: directory)
            guard isCurrentFileChildrenLoad(path: path, host: host, directory: directory, generation: generation) else {
                return []
            }
            storeFileChildren(children, path: path, host: host, directory: directory)
            return children
        } catch {
            guard isCurrentFileChildrenLoad(path: path, host: host, directory: directory, generation: generation) else {
                return []
            }
            fileChildrenCache.removeValue(forKey: path)
            return []
        }
    }

    func cachedChildren(for path: String) -> [FileNode]? {
        let scope = FileChildrenScope(host: captureHostRequestSnapshot(), directory: effectiveProjectDirectory)
        guard fileStore.fileChildrenScope == scope else { return nil }
        return fileChildrenCache[path]
    }

    func fileSearchQueryChanged(_ query: String) {
        fileSearchGeneration &+= 1
        let generation = fileSearchGeneration
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory
        rememberFileSearchScope(host: host, directory: directory)
        if query.isEmpty {
            clearFileSearchResults()
            return
        }
        fileSearchResults = []
        fileStore.fileSearchFailed = false
        fileStore.fileSearchError = nil
        fileStore.fileSearchInFlight = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard fileSearchGeneration == generation, fileSearchQuery == query else { return }
            await searchFiles(query: query, generation: generation, host: host, directory: directory)
        }
    }

    func submitFileSearch() async {
        fileSearchGeneration &+= 1
        let generation = fileSearchGeneration
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory
        rememberFileSearchScope(host: host, directory: directory)
        await searchFiles(query: fileSearchQuery, generation: generation, host: host, directory: directory)
    }

    func discardUnownedFileSearch() {
        let host = captureHostRequestSnapshot()
        let directory = effectiveProjectDirectory
        guard fileStore.fileSearchOwner != host || fileStore.fileSearchDirectory != directory else { return }
        fileSearchGeneration &+= 1
        fileSearchQuery = ""
        clearFileSearchResults()
        rememberFileSearchScope(host: host, directory: directory)
    }

    func searchFiles(query: String, generation: UInt64, host: HostRequestSnapshot, directory: String?) async {
        guard !query.isEmpty else {
            guard fileSearchGeneration == generation else { return }
            clearFileSearchResults()
            return
        }
        guard isCurrentFileSearch(query: query, generation: generation, host: host, directory: directory) else { return }
        fileStore.fileSearchInFlight = true
        do {
            let results = try await findFiles(query: query, directory: directory)
            guard isCurrentFileSearch(query: query, generation: generation, host: host, directory: directory) else { return }
            fileSearchResults = results
            fileStore.fileSearchFailed = false
            fileStore.fileSearchError = nil
            fileStore.fileSearchInFlight = false
        } catch {
            guard isCurrentFileSearch(query: query, generation: generation, host: host, directory: directory) else { return }
            fileSearchResults = []
            fileStore.fileSearchFailed = true
            fileStore.fileSearchError = error.localizedDescription
            fileStore.fileSearchInFlight = false
        }
    }

    private var fileSearchGeneration: UInt64 {
        get { fileStore.fileSearchGeneration }
        set { fileStore.fileSearchGeneration = newValue }
    }

    private func rememberFileSearchScope(host: HostRequestSnapshot, directory: String?) {
        fileStore.fileSearchOwner = host
        fileStore.fileSearchDirectory = directory
    }

    private func clearFileSearchResults() {
        fileSearchResults = []
        fileStore.fileSearchInFlight = false
        fileStore.fileSearchFailed = false
        fileStore.fileSearchError = nil
    }

    private func findFiles(query: String, directory: String?) async throws -> [String] {
        if let searching = apiClient as? any FileDirectorySearching {
            return try await searching.findFile(query: query, limit: 50, directory: directory)
        }
        return try await apiClient.findFile(query: query, limit: 50)
    }

    private func isCurrentFileSearch(query: String, generation: UInt64, host: HostRequestSnapshot, directory: String?) -> Bool {
        isCurrentHostRequest(host)
            && fileSearchGeneration == generation
            && fileSearchQuery == query
            && effectiveProjectDirectory == directory
    }

    private func isCurrentFileChildrenLoad(path: String, host: HostRequestSnapshot, directory: String?, generation: UInt64) -> Bool {
        isCurrentHostRequest(host)
            && effectiveProjectDirectory == directory
            && fileStore.fileChildrenLoadGeneration[path] == generation
    }

    private func storeFileChildren(_ children: [FileNode], path: String, host: HostRequestSnapshot, directory: String?) {
        let scope = FileChildrenScope(host: host, directory: directory)
        if fileStore.fileChildrenScope != scope {
            fileChildrenCache = [:]
            fileStore.fileChildrenScope = scope
        }
        fileChildrenCache[path] = children
    }

    func loadFileContent(path: String, workspaceDirectory: String? = nil) async throws -> FileContent {
        // `nil` follows the live session. `""` is a pinned server default and must not.
        let directory = workspaceDirectory ?? currentSession?.directory
        let resolved = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: directory)
        if resolved.hasPrefix("/") {
            let url = URL(fileURLWithPath: resolved)
            return try await apiClient.fileContent(path: url.lastPathComponent, directory: url.deletingLastPathComponent().path)
        }
        return try await apiClient.fileContent(path: resolved, directory: directory)
    }

    func loadFileContent(pathBytes: [UInt8], workspaceDirectory: String? = nil) async throws -> FileContent {
        let path = String(decoding: pathBytes, as: UTF8.self)
        return try await loadFileContent(path: path, workspaceDirectory: workspaceDirectory)
    }

    func toggleFileExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isFileExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }
}
