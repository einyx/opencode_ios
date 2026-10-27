import Foundation
import Testing

@testable import OpenCodeClient

/// The model lives on the server session, which every client of that server
/// shares. The app may only write a model the user explicitly picked for the
/// session — a picker's default index is a UI position, not a decision.
struct SessionModelSelectionTests {
    @MainActor
    private func makeState() -> (AppState, MockAPIClient) {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.modelShortlist = [
            ModelShortlistItem(providerID: "zai-coding-plan", modelID: "glm-5.3", displayName: "GLM 5.3", shortName: "glm"),
            ModelShortlistItem(providerID: "anthropic", modelID: "claude-opus-5", displayName: "Claude Opus 5", shortName: "opus"),
            ModelShortlistItem(providerID: "openai", modelID: "gpt-5.6", displayName: "GPT 5.6", shortName: "gpt"),
        ]
        return (state, api)
    }

    @Test @MainActor func sendingWithoutAnExplicitPickLeavesTheSessionModelAlone() async throws {
        let (state, api) = makeState()
        state.sessions = [
            Session(id: "ses_model", slug: "ses-model", projectID: "p", directory: "/tmp", parentID: nil, title: "s", version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
        ]
        state.currentSessionID = "ses_model"

        // No explicit pick for this session.
        #expect(state.sessionModelPreset == nil)

        let sent = await state.sendMessage("hello")
        #expect(sent)
        #expect(await api.promptAsyncModels.count == 1)
        // nil: the server keeps whatever model it was already using, so other
        // clients on the same session are not switched behind their back.
        #expect(await api.promptAsyncModels[0] == nil)
    }

    @Test @MainActor func sendingWithAnExplicitPickAppliesThatModel() async throws {
        let (state, api) = makeState()
        state.sessions = [
            Session(id: "ses_model", slug: "ses-model", projectID: "p", directory: "/tmp", parentID: nil, title: "s", version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
        ]
        state.currentSessionID = "ses_model"

        // The user picks the second entry of the shortlist.
        state.setSelectedModelIndex(1)
        #expect(state.sessionModelPreset?.modelID == "claude-opus-5")

        let sent = await state.sendMessage("hello")
        #expect(sent)
        #expect(await api.promptAsyncModels.count == 1)
        #expect(await api.promptAsyncModels[0]?.modelID == "claude-opus-5")
        #expect(await api.promptAsyncModels[0]?.providerID == "anthropic")
    }

// MARK: agent omission

    @Test @MainActor func sendingWithoutAnExplicitAgentPickOmitsTheAgent() async throws {
        let (state, api) = makeState()
        state.sessions = [
            Session(id: "ses_agent", slug: "ses-agent", projectID: "p", directory: "/tmp", parentID: nil, title: "s", version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
        ]
        state.currentSessionID = "ses_agent"
        // No explicit agent pick: the flag stays off even though a default
        // agent name is populated for the UI.
        #expect(state.agentExplicitlyChosen == false)

        let sent = await state.sendMessage("hello")
        #expect(sent)
        #expect(await api.promptAsyncAgentsSent.last == "")
    }

    @Test @MainActor func sendingWithAnExplicitAgentPickSendsIt() async throws {
        let (state, api) = makeState()
        state.sessions = [
            Session(id: "ses_agent", slug: "ses-agent", projectID: "p", directory: "/tmp", parentID: nil, title: "s", version: "1", time: .init(created: 1, updated: 1, archived: nil), share: nil, summary: nil)
        ]
        state.currentSessionID = "ses_agent"
        state.hasServerAgentCatalog = true
        state.agents = [
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: nil),
            AgentInfo(name: "plan", description: nil, mode: "primary", hidden: false, native: nil),
        ]
        state.setSelectedAgentIndex(0)

        let sent = await state.sendMessage("hello")
        #expect(sent)
        #expect(await api.promptAsyncAgentsSent.last == "build")
    }

    @Test @MainActor func aStaleCapitalisedAgentPickResolvesToTheServerCasing() async throws {
        // The regression from the device report: a saved "Build" made every
        // prompt fail with Agent not found.
        let (state, _) = makeState()
        state.hasServerAgentCatalog = true
        state.agents = [
            AgentInfo(name: "build", description: nil, mode: "primary", hidden: false, native: nil),
        ]
        // The user explicitly picked an agent under an old, capitalised name.
        state.agentExplicitlyChosen = true
        state.reconcileSelectedAgent(preferredName: "Build")
        #expect(state.selectedAgentName == "build")
        #expect(state.agentForPrompt() == "build")
    }

        @Test @MainActor func theDefaultIndexNeverPointsAtAModelTheUserDidNotChoose() async throws {
        let (state, _) = makeState()
        // The picker starts at the top of the list, not at an arbitrary index
        // that could be a provider the user never picked.
        #expect(state.selectedModelIndex == 0)
        #expect(state.sessionModelPreset == nil)
    }
}
