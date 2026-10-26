#if DEBUG
import Foundation

/// Illustrative content for screenshots, using the production views without
/// contacting a real server or exposing personal workspace data.
enum AppStoreScreenshotFixture {
    static let argument = "UITEST_APP_STORE_SCREENSHOTS"
    static let reply = "The API client now uses typed responses and consistent error handling. All tests passed."

    @MainActor
    static func apply(to state: AppState) {
        guard ProcessInfo.processInfo.arguments.contains(argument),
              let original = state.currentSession else { return }
        state.sessions = [Session(
            id: original.id, slug: original.slug, projectID: original.projectID,
            directory: original.directory, parentID: nil,
            title: "Refactor the API client", version: original.version,
            time: original.time, share: nil, summary: original.summary
        )]
        var messages = state.messages
        for index in messages.indices where messages[index].info.isAssistant {
            messages[index].parts.removeAll {
                $0.stateDisplay?.lowercased() == "error"
                    || ($0.isTool && !ToolCardClassifier.isFileOperation($0) && $0.tool != "bash")
            }
            if let textIndex = messages[index].parts.firstIndex(where: { $0.type == "text" }) {
                messages[index].parts[textIndex].text = reply
            }
        }
        state.messages = messages
        state.providerDisplayNames = ["openai": "OpenAI", "anthropic": "Anthropic"]
        state.modelShortlist = [
            ModelShortlistItem(providerID: "openai", modelID: "gpt-4.1", displayName: "GPT-4.1", shortName: "GPT-4.1"),
            ModelShortlistItem(providerID: "anthropic", modelID: "claude-sonnet-4", displayName: "Claude Sonnet 4", shortName: "Sonnet 4")
        ]
        state.rebuildPickerModelItems(reason: "app-store-sample")
        state.setSelectedModelIndex(0)
        state.agents = [
            AgentInfo(name: "build", description: "Implement features and fix bugs", mode: "primary", hidden: false, native: true),
            AgentInfo(name: "plan", description: "Explore approaches before making changes", mode: "primary", hidden: false, native: true)
        ]
        state.hasServerAgentCatalog = true
        state.statusStreamConnected = true
        state.statusLastAttemptAt = .distantFuture
        state.statusConfirmedAt[original.id] = .distantFuture
        state.sessionStatuses[original.id] = SessionStatus(type: "idle", attempt: nil, message: nil, next: nil)
        state.fileTreeRoot = [
            FileNode(name: "src", path: "src", absolute: nil, type: "directory", ignored: false),
            FileNode(name: "README.md", path: "README.md", absolute: nil, type: "file", ignored: false)
        ]
        state.fileChildrenCache = [
            "src": [FileNode(name: "api", path: "src/api", absolute: nil, type: "directory", ignored: false)],
            "src/api": ["client.ts", "types.ts", "index.ts"].map {
                FileNode(name: $0, path: "src/api/\($0)", absolute: nil, type: "file", ignored: false)
            }
        ]
        state.expandedPaths = ["src", "src/api"]
        state.fileStatusMap = ["src/api/types.ts": "modified", "README.md": "modified"]
        state.fileStore.fileChildrenScope = FileChildrenScope(
            host: state.captureHostRequestSnapshot(), directory: state.effectiveProjectDirectory
        )
    }
}
#endif
