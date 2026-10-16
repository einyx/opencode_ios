import Foundation
import SwiftUI
import WebKit

@MainActor
@Observable
final class FileContentProbe {
    var contentDirectories: [String] = []
    var contentRequestCount = 0
    var lateDelivered = false
    var linkClick = ""

    var summary: String {
        "count:\(contentRequestCount) dirs:\(contentDirectories.joined(separator: "|")) late:\(lateDelivered ? 1 : 0)"
    }
}

enum FileContentReuseFixture {
    static let argument = "UITEST_FILE_CONTENT_REUSE_FIXTURE"
    static let modeKey = "FILE_CONTENT_FIXTURE_MODE"
    static let workspaceA = "/tmp/w06-ws-a"
    static let workspaceB = "/tmp/w06-ws-b"
    static let contentA = "CONTENT_A"
    static let contentB = "CONTENT_B"
    static let sessionRebindBody = "SESSION_REBIND_BODY"
    static let sessionRebindLink = "Open other"
    static let sessionRebindMarkdown = "[\(sessionRebindLink)](other.md)\n\n\(sessionRebindBody)"
    @MainActor static let probe = FileContentProbe()
    static var script: FileContentScript?

    enum Mode: String {
        case latePath = "late-path"
        case lateError = "late-error"
        case lateWorkspace = "late-workspace"
        case refresh
        case sessionRebind = "session-rebind"

        var initialPath: String {
            switch self {
            case .latePath, .lateError: return "a.txt"
            case .lateWorkspace, .refresh: return "notes.txt"
            case .sessionRebind: return "notes.md"
            }
        }

        var initialWorkspace: String {
            switch self {
            case .latePath, .lateError: return "/ws"
            case .lateWorkspace, .sessionRebind: return FileContentReuseFixture.workspaceA
            case .refresh: return FileContentReuseFixture.workspaceB
            }
        }
    }

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var mode: Mode {
        let raw = ProcessInfo.processInfo.environment[modeKey] ?? Mode.latePath.rawValue
        return Mode(rawValue: raw) ?? .latePath
    }

    @MainActor
    static func makeAppState() -> AppState {
        let script: FileContentScript
        if let existing = self.script {
            script = existing
        } else {
            probe.contentDirectories = []
            probe.contentRequestCount = 0
            probe.lateDelivered = false
            probe.linkClick = ""
            script = FileContentScript()
            self.script = script
        }
        let defaults = UITestFixtures.isolatedDefaults(label: "file-content")
        return AppState(
            apiClient: script,
            sseClient: SSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: HostCredentialAccess(
                save: { _, _ in },
                load: { _ in nil },
                delete: { _ in }
            )
        )
    }
}

struct FileContentReuseHost: View {
    @Bindable var state: AppState
    @State private var path = FileContentReuseFixture.mode.initialPath
    @State private var workspace = FileContentReuseFixture.mode.initialWorkspace
    @State private var boundSessionID: String? = nil

    var body: some View {
        NavigationStack {
            FileContentView(
                state: state,
                filePath: path,
                workspaceDirectory: workspace,
                boundSessionID: boundSessionID
            )
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(probeLabel)
                    .font(.system(size: 1))
                    .accessibilityIdentifier("file-content-probe")
                    .accessibilityLabel(probeLabel)
                HStack {
                    Button("switch-path") { path = "b.txt" }
                        .accessibilityIdentifier("file-content-switch-path")
                    Button("switch-workspace") { workspace = FileContentReuseFixture.workspaceB }
                        .accessibilityIdentifier("file-content-switch-workspace")
                    Button("release-late") {
                        Task { await FileContentReuseFixture.script?.releaseLate() }
                    }
                    .accessibilityIdentifier("file-content-release-late")
                    if FileContentReuseFixture.mode == .sessionRebind {
                        Button("bind-session") {
                            boundSessionID = "session-b"
                            state.currentSessionID = "session-b"
                        }
                        .accessibilityIdentifier("file-content-bind-session")
                        Button("activate-link") { WebPreviewLinkClick.postRenderedAnchor() }
                            .accessibilityIdentifier("file-content-activate-link")
                    }
                }
            }
        }
    }

    private var probeLabel: String {
        guard FileContentReuseFixture.mode == .sessionRebind else {
            return FileContentReuseFixture.probe.summary
        }
        let pending = state.pendingFileOpenOwner?.sessionID ?? "-"
        let opened = state.fileToOpenInFilesTab ?? "-"
        let click = FileContentReuseFixture.probe.linkClick
        return "\(FileContentReuseFixture.probe.summary) pending:\(pending) open:\(opened) click:\(click)"
    }
}

private enum WebPreviewLinkClick {
    @MainActor
    static func postRenderedAnchor() {
        let webViews = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .flatMap(webViews(in:))
        guard let webView = webViews.first(where: { $0.accessibilityIdentifier == "markdown-web-preview-webview" }) ?? webViews.first else {
            FileContentReuseFixture.probe.linkClick = "no-webview"
            return
        }
        webView.evaluateJavaScript(
            "(function(){var a=document.querySelector('#content a')||document.querySelector('a');if(!a)return 'no-anchor';var href=a.getAttribute('href')||'';if(!(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.previewBridge))return 'no-bridge';window.webkit.messageHandlers.previewBridge.postMessage({type:'link',href:href});return 'bridge:'+href;})()"
        ) { result, error in
            let detail = (result as? String) ?? error?.localizedDescription ?? "nil"
            Task { @MainActor in
                FileContentReuseFixture.probe.linkClick = detail
            }
        }
    }

    private static func webViews(in view: UIView) -> [WKWebView] {
        let found = (view as? WKWebView).map { [$0] } ?? []
        return found + view.subviews.flatMap(webViews(in:))
    }
}

private struct FileContentScriptError: Error {}

actor FileContentScript: APIClientProtocol, FileDirectorySearching {
    private var parked: CheckedContinuation<Result<FileContent, Error>, Never>?
    private var requests = 0

    func releaseLate() {
        let result: Result<FileContent, Error>
        if FileContentReuseFixture.mode == .lateError {
            result = .failure(FileContentScriptError())
        } else {
            result = .success(FileContent(type: "text", content: FileContentReuseFixture.contentA))
        }
        parked?.resume(returning: result)
        parked = nil
    }

    func configure(baseURL: String, username: String?, password: String?) {}
    func health() async throws -> HealthResponse { HealthResponse(healthy: true, version: "fixture") }
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
    func fileList(path: String, directory: String?) async throws -> [FileNode] { [] }
    func fileContent(path: String, directory: String?) async throws -> FileContent {
        requests += 1
        let index = requests
        let recorded = directory ?? ""
        await MainActor.run {
            FileContentReuseFixture.probe.contentDirectories.append(recorded)
            FileContentReuseFixture.probe.contentRequestCount = index
        }
        if FileContentReuseFixture.mode != .refresh, FileContentReuseFixture.mode != .sessionRebind, index == 1 {
            let result = await withCheckedContinuation { (cont: CheckedContinuation<Result<FileContent, Error>, Never>) in
                parked = cont
            }
            await MainActor.run { FileContentReuseFixture.probe.lateDelivered = true }
            return try result.get()
        }
        if FileContentReuseFixture.mode == .refresh {
            return FileContent(type: "text", content: "BODY-\(index)")
        }
        if FileContentReuseFixture.mode == .sessionRebind {
            return FileContent(type: "text", content: FileContentReuseFixture.sessionRebindMarkdown)
        }
        if path == "b.txt" || directory == FileContentReuseFixture.workspaceB {
            return FileContent(type: "text", content: FileContentReuseFixture.contentB)
        }
        return FileContent(type: "text", content: FileContentReuseFixture.contentA)
    }
    func findFile(query: String, limit: Int) async throws -> [String] { [] }
    func findFile(query: String, limit: Int, directory: String?) async throws -> [String] { [] }
    func fileStatus() async throws -> [FileStatusEntry] { [] }
    func forkSession(sessionID: String, messageID: String?) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Session {
        throw APIError.httpError(statusCode: 501, data: Data())
    }
}
