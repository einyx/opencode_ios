//
//  CarModeTests.swift
//  OpenCodeClientTests
//

import Foundation
import Testing
@testable import OpenCodeClient

@Suite(.serialized)
struct CarModeFlowTests {
    @Test @MainActor func submitCarTurnReusesScopedSessionAndSpeaksOnce() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(
            apiClient: api,
            carSpeechOutput: speech
        )
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = Session(
            id: "car-session",
            slug: "car-session",
            projectID: "p1",
            directory: "/tmp/car-workspace",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: try Message(
                id: "assistant-1",
                sessionID: session.id,
                role: "assistant",
                parentID: "user-1",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 2, completed: 3),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: "The garage door is closed.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Is the garage closed?")
        await api.setSessionResult(Session(
            id: session.id,
            slug: session.slug,
            projectID: session.projectID,
            directory: session.directory,
            parentID: nil,
            title: session.title,
            version: session.version,
            time: .init(created: 1, updated: 2, archived: 2),
            share: nil,
            summary: nil
        ))
        await state.submitCarTurn("Is the garage still closed?")

        #expect(state.currentCarSessionID == session.id)
        #expect(state.carPhase == .idle)
        #expect(speech.spokenTexts == ["The garage door is closed."])
        #expect(await api.promptStructuredCalls.count == 2)
        #expect(await api.promptStructuredCalls.first?.modelID == "gpt-5.6-sol-fast")
        #expect(await api.promptStructuredCalls.allSatisfy { $0.sessionID == session.id })
        #expect(await api.updateSessionArchivedCalls.map(\.1) == [-1])
    }

    @Test @MainActor func selectedProjectCanRestoreExistingCarSession() async throws {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/server-default"
        state.selectedProjectWorktree = "/workspace/selected"
        let session = Session(
            id: "selected-car-session",
            slug: "selected-car-session",
            projectID: "p1",
            directory: "/workspace/selected",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 2, archived: 3),
            share: nil,
            summary: nil
        )
        state.carSessionsByContext[state.carContextKey] = CarSessionRecord(
            sessionID: session.id,
            lastHandledAssistantMessageID: nil,
            pendingConfirmationID: nil,
            lastUsedAt: Date()
        )
        await api.setSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: try Message(
                id: "selected-assistant",
                sessionID: session.id,
                role: "assistant",
                parentID: "selected-user",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 4, completed: 5),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .completed,
                    speech: "Restored.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Continue")

        #expect(state.carPhase == .idle)
        #expect(await api.updateSessionArchivedCalls.map(\.0) == [session.id])
        #expect(await api.promptStructuredCalls.map(\.sessionID) == [session.id])
    }

    @Test @MainActor func carSessionContextSeparatesHostsAndWorkspaces() {
        let state = makeIsolatedAppState()
        state.serverCurrentProjectWorktree = "/workspace/a"
        let first = state.carContextKey
        state.serverCurrentProjectWorktree = "/workspace/b"
        let second = state.carContextKey
        state.currentHostProfileID = UUID()
        let third = state.carContextKey

        #expect(first != second)
        #expect(second != third)
    }

    @Test @MainActor func selectedProjectCannotReuseServerDefaultCarSession() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/server-default"
        state.selectedProjectWorktree = "/workspace/selected"

        await state.submitCarTurn("Hello")

        #expect(state.carPhase == .failed)
        #expect(state.carError == CarModeError.selectedProjectUnsupported.localizedDescription)
        #expect(await api.promptStructuredCalls.isEmpty)
    }

    @Test @MainActor func failedStructuredResponseKeepsCarModeFailed() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(
            apiClient: api,
            carSpeechOutput: speech
        )
        state.isConnected = true
        state.selectedProjectWorktree = nil
        let session = Session(
            id: "car-failed",
            slug: "car-failed",
            projectID: "p1",
            directory: "/tmp",
            parentID: nil,
            title: "Car Mode",
            version: "1",
            time: .init(created: 1, updated: 1, archived: nil),
            share: nil,
            summary: nil
        )
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(MessageWithParts(
            info: try Message(
                id: "assistant-failed",
                sessionID: session.id,
                role: "assistant",
                parentID: "user-1",
                providerID: "openai",
                modelID: "gpt-5.6-sol-fast",
                model: nil,
                error: nil,
                time: .init(created: 2, completed: 3),
                finish: "tool-calls",
                tokens: nil,
                cost: nil,
                structured: CarResponseEnvelope(
                    version: 1,
                    status: .failed,
                    speech: "I could not complete that request.",
                    confirmation: nil,
                    clientActions: []
                )
            ),
            parts: []
        ))

        await state.submitCarTurn("Try it")

        #expect(state.carPhase == .failed)
        #expect(speech.spokenTexts == ["I could not complete that request."])
    }

    @Test @MainActor func cancellingWithoutActiveTurnDoesNotAbortSession() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)

        await state.cancelCarInteraction()

        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func confirmationTurnKeepsPendingIDAndSpeaks() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = carSession(id: "car-confirm")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-confirm",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .needsConfirmation,
                speech: "Send the garage command?",
                confirmation: CarConfirmation(id: "confirm-1", prompt: "Send it?"),
                clientActions: []
            )
        ))

        await state.submitCarTurn("Close the garage")

        let record = state.carSessionsByContext[state.carContextKey]
        #expect(state.carPhase == .awaitingConfirmation)
        #expect(record?.sessionID == session.id)
        #expect(record?.pendingConfirmationID == "confirm-1")
        #expect(record?.lastHandledAssistantMessageID == "assistant-confirm")
        #expect(speech.spokenTexts == ["Send the garage command?"])
        #expect(await api.createSessionCalls.count == 1)
        #expect(await api.promptStructuredCalls.count == 1)
    }

    @Test @MainActor func unknownCarActionDoesNotFailTheTurn() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = carSession(id: "car-unknown")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-unknown",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "I cannot run that widget.",
                confirmation: nil,
                clientActions: [.unknown(id: "widget-1", type: "future_widget")]
            )
        ))

        await state.submitCarTurn("Run the widget")

        #expect(state.carPhase == .idle)
        #expect(state.carError == nil)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(speech.spokenTexts == ["I cannot run that widget."])
    }

    @Test @MainActor func cancelDuringCreateDoesNotPromptOrMap() async {
        let api = MockAPIClient()
        let state = makeIsolatedAppState(apiClient: api)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        await api.setCreateSessionResult(carSession(id: "created-after-cancel"))
        await api.setSuspendCreateSession(true)

        let turn = Task { await state.submitCarTurn("Hello") }
        await api.waitUntilCreateSessionPending(1)
        await state.cancelCarInteraction()
        await api.releaseCreateSession()
        await turn.value

        #expect(await api.promptStructuredCalls.isEmpty)
        #expect(state.carSessionsByContext.isEmpty)
        #expect(state.carPhase == .idle)
        #expect(state.carActiveTurnID == nil)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func hostChangeDuringCreateDoesNotMapOrPrompt() async {
        let harness = CarHostHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        await harness.api.setCreateSessionResult(carSession(id: "created-on-old-host"))
        await harness.api.setSuspendCreateSession(true)

        let turn = Task { await state.submitCarTurn("Hello") }
        await harness.api.waitUntilCreateSessionPending(1)
        let oldKey = state.carContextKey
        harness.switchToOtherHost()
        let newKey = state.carContextKey
        await harness.api.releaseCreateSession()
        await turn.value

        #expect(oldKey != newKey)
        #expect(await harness.api.promptStructuredCalls.isEmpty)
        #expect(await harness.api.abortSessionIDs.isEmpty)
        #expect(state.carSessionsByContext[newKey] == nil)
        #expect(state.carSessionsByContext[oldKey] == nil)
        #expect(harness.speech.stopCount >= 1)
        #expect(harness.speech.spokenTexts.isEmpty)
    }

    @Test @MainActor func projectChangeDropsStaleConfirmationAndSpeech() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = carSession(id: "car-project")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-project",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .needsConfirmation,
                speech: "Confirm on the old project.",
                confirmation: CarConfirmation(id: "confirm-old", prompt: "Proceed?"),
                clientActions: []
            )
        ))
        await api.setSuspendPromptStructured(true)

        let turn = Task { await state.submitCarTurn("Do it") }
        await api.waitUntilPromptStructuredPending(1)
        let oldKey = state.carContextKey
        state.serverCurrentProjectWorktree = "/tmp/other-project"
        let newKey = state.carContextKey
        await api.releasePromptStructured()
        await turn.value

        #expect(oldKey != newKey)
        #expect(speech.spokenTexts.isEmpty)
        #expect(state.carSessionsByContext[newKey] == nil)
        #expect(state.carSessionsByContext[oldKey]?.pendingConfirmationID == nil)
        #expect(state.carSessionsByContext[oldKey]?.lastHandledAssistantMessageID == nil)
        #expect(state.carPhase == .idle)
        #expect(state.pendingClientCapabilityRequest == nil)
    }

    @Test @MainActor func hostChangeDropsStaleActionAndSpeech() async throws {
        let harness = CarHostHarness()
        defer { harness.cleanup() }
        let state = harness.state
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/tmp/car-workspace"
        let session = carSession(id: "car-host-action")
        await harness.api.setCreateSessionResult(session)
        await harness.api.setPromptStructuredResult(try carResponse(
            id: "assistant-host-action",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Exporting health data.",
                confirmation: nil,
                clientActions: [.healthExportAll(id: "export-1", reason: "check")]
            )
        ))
        await harness.api.setSuspendPromptStructured(true)

        let turn = Task { await state.submitCarTurn("Export health") }
        await harness.api.waitUntilPromptStructuredPending(1)
        let oldKey = state.carContextKey
        harness.switchToOtherHost()
        let newKey = state.carContextKey
        await harness.api.releasePromptStructured()
        await turn.value

        #expect(oldKey != newKey)
        #expect(harness.speech.spokenTexts.isEmpty)
        #expect(harness.speech.stopCount >= 1)
        #expect(await harness.api.abortSessionIDs.isEmpty)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(state.carSessionsByContext[newKey] == nil)
        #expect(state.carSessionsByContext[oldKey]?.lastHandledAssistantMessageID == nil)
        #expect(state.carPhase == .idle)
    }

    @Test @MainActor func delayedProjectMetadataDuringCreateSucceedsAndReusesMapping() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        let session = carSession(id: "car-meta", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setSessionResult(session)
        await api.setProjectCurrentResult(Project(id: "p-a", worktree: "/workspace/a", vcs: nil, icon: nil, time: nil, sandboxes: nil))
        await api.setSuspendProjectCurrent(true)
        await api.setSuspendCreateSession(true)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-meta",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Ready.",
                confirmation: nil,
                clientActions: []
            )
        ))

        let loading = Task { await state.loadProjects() }
        await api.waitUntilProjectCurrentPending(1)
        let turn = Task { await state.submitCarTurn("Hello") }
        await api.waitUntilCreateSessionPending(1)
        let placeholder = "\(state.currentHostProfileID.uuidString)|__server_default__"
        #expect(state.carContextKey == placeholder)
        #expect(state.carActiveTurnID != nil)

        await api.releaseProjectCurrent()
        await loading.value
        #expect(state.serverCurrentProjectWorktree == "/workspace/a")
        #expect(state.carActiveTurnID != nil)

        await api.releaseCreateSession()
        await turn.value

        let resolved = state.carContextKey
        #expect(resolved.hasSuffix("|/workspace/a"))
        #expect(state.carSessionsByContext[placeholder] == nil)
        #expect(state.carSessionsByContext[resolved]?.sessionID == session.id)
        #expect(state.carPhase == .idle)
        #expect(speech.spokenTexts == ["Ready."])
        #expect(await api.promptStructuredCalls.count == 1)
        #expect(await api.abortSessionIDs.isEmpty)

        await state.submitCarTurn("Again")
        #expect(await api.createSessionCalls.count == 1)
        #expect(await api.sessionRequests == [session.id])
        #expect(state.carSessionsByContext[resolved]?.sessionID == session.id)
    }

    @Test @MainActor func projectRoundTripDropsStalePromptWithoutWriteSpeechOrAction() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/a"
        let session = carSession(id: "car-round-trip", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-round-trip",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Still on the old project.",
                confirmation: nil,
                clientActions: [.healthExportAll(id: "export-old", reason: "check")]
            )
        ))
        await api.setSuspendPromptStructured(true)

        let turn = Task { await state.submitCarTurn("Do it") }
        await api.waitUntilPromptStructuredPending(1)
        let oldKey = state.carContextKey
        var record = try #require(state.carSessionsByContext[oldKey])
        record.pendingConfirmationID = "keep-me"
        state.carSessionsByContext[oldKey] = record
        state.serverCurrentProjectWorktree = "/workspace/b"
        state.serverCurrentProjectWorktree = "/workspace/a"
        #expect(state.carActiveTurnID == nil)
        await api.releasePromptStructured()
        await turn.value

        #expect(state.carContextKey == oldKey)
        #expect(speech.spokenTexts.isEmpty)
        #expect(state.carSessionsByContext[oldKey]?.sessionID == session.id)
        #expect(state.carSessionsByContext[oldKey]?.pendingConfirmationID == "keep-me")
        #expect(state.carSessionsByContext[oldKey]?.lastHandledAssistantMessageID == nil)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(state.carPhase == .idle)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func projectChangeDuringSpeechStopsImmediatelyAndDoesNotOverwriteNewTurn() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/a"
        let session = carSession(id: "car-speech-stop", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-speech-stop",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Opening the old route.",
                confirmation: nil,
                clientActions: [.healthExportAll(id: "export-old", reason: "check")]
            )
        ))
        speech.setSuspendSpeak(true)

        let turn = Task { await state.submitCarTurn("Navigate") }
        await speech.waitUntilSpeakPending(1)
        #expect(speech.stopCount == 0)
        #expect(state.carPhase == .speaking)

        state.serverCurrentProjectWorktree = "/workspace/b"
        #expect(speech.stopCount >= 1)
        #expect(state.carActiveTurnID == nil)
        let newTurnID = UUID()
        state.carActiveTurnID = newTurnID
        state.carPhase = .waitingReply
        await turn.value

        #expect(state.carActiveTurnID == newTurnID)
        #expect(state.carPhase == .waitingReply)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func lookupRecoveryRoundTripDropsStalePromptWithoutWriteSpeechOrAction() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/a"
        let session = carSession(id: "car-lookup-round-trip", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-lookup-round-trip",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Still on the old project.",
                confirmation: nil,
                clientActions: [.healthExportAll(id: "export-old", reason: "check")]
            )
        ))
        await api.setSuspendPromptStructured(true)

        let turn = Task { await state.submitCarTurn("Do it") }
        await api.waitUntilPromptStructuredPending(1)
        let oldKey = state.carContextKey
        var record = try #require(state.carSessionsByContext[oldKey])
        record.pendingConfirmationID = "keep-me"
        state.carSessionsByContext[oldKey] = record

        await api.setProjectCurrentError(APIError.httpError(statusCode: 503, data: Data()))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == nil)
        #expect(state.carActiveTurnID != nil)

        await api.setProjectCurrentError(nil)
        await api.setProjectCurrentResult(Project(id: "p-b", worktree: "/workspace/b", vcs: nil, icon: nil, time: nil, sandboxes: nil))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == "/workspace/b")
        #expect(state.carActiveTurnID == nil)

        await api.setProjectCurrentError(APIError.httpError(statusCode: 503, data: Data()))
        await state.loadProjects()
        await api.setProjectCurrentError(nil)
        await api.setProjectCurrentResult(Project(id: "p-a", worktree: "/workspace/a", vcs: nil, icon: nil, time: nil, sandboxes: nil))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == "/workspace/a")
        #expect(state.carContextKey == oldKey)

        await api.releasePromptStructured()
        await turn.value

        #expect(speech.spokenTexts.isEmpty)
        #expect(state.carSessionsByContext[oldKey]?.sessionID == session.id)
        #expect(state.carSessionsByContext[oldKey]?.pendingConfirmationID == "keep-me")
        #expect(state.carSessionsByContext[oldKey]?.lastHandledAssistantMessageID == nil)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(state.carPhase == .idle)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func lookupFailureThenDifferentProjectStopsSpeechImmediately() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        state.serverCurrentProjectWorktree = "/workspace/a"
        let session = carSession(id: "car-lookup-speech-stop", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-lookup-speech-stop",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Opening the old route.",
                confirmation: nil,
                clientActions: [.healthExportAll(id: "export-old", reason: "check")]
            )
        ))
        speech.setSuspendSpeak(true)

        let turn = Task { await state.submitCarTurn("Navigate") }
        await speech.waitUntilSpeakPending(1)
        #expect(speech.stopCount == 0)
        #expect(state.carPhase == .speaking)

        await api.setProjectCurrentError(APIError.httpError(statusCode: 503, data: Data()))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == nil)
        #expect(speech.stopCount == 0)
        #expect(state.carActiveTurnID != nil)

        await api.setProjectCurrentError(nil)
        await api.setProjectCurrentResult(Project(id: "p-b", worktree: "/workspace/b", vcs: nil, icon: nil, time: nil, sandboxes: nil))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == "/workspace/b")
        #expect(speech.stopCount >= 1)
        #expect(state.carActiveTurnID == nil)
        let newTurnID = UUID()
        state.carActiveTurnID = newTurnID
        state.carPhase = .waitingReply
        await turn.value

        #expect(state.carActiveTurnID == newTurnID)
        #expect(state.carPhase == .waitingReply)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(await api.abortSessionIDs.isEmpty)
    }

    @Test @MainActor func lookupNilAfterMetadataAcceptsLegalResponseAndReusesMapping() async throws {
        let api = MockAPIClient()
        let speech = MockCarSpeechOutput()
        let state = makeIsolatedAppState(apiClient: api, carSpeechOutput: speech)
        state.isConnected = true
        let session = carSession(id: "car-lookup-nil-reuse", directory: "/workspace/a")
        await api.setCreateSessionResult(session)
        await api.setSessionResult(session)
        await api.setProjectCurrentResult(Project(id: "p-a", worktree: "/workspace/a", vcs: nil, icon: nil, time: nil, sandboxes: nil))
        await api.setSuspendProjectCurrent(true)
        await api.setSuspendPromptStructured(true)
        await api.setPromptStructuredResult(try carResponse(
            id: "assistant-lookup-nil",
            sessionID: session.id,
            envelope: CarResponseEnvelope(
                version: 1,
                status: .completed,
                speech: "Ready.",
                confirmation: nil,
                clientActions: []
            )
        ))

        let loading = Task { await state.loadProjects() }
        await api.waitUntilProjectCurrentPending(1)
        let turn = Task { await state.submitCarTurn("Hello") }
        await api.waitUntilPromptStructuredPending(1)
        let placeholder = "\(state.currentHostProfileID.uuidString)|__server_default__"
        #expect(state.serverCurrentProjectWorktree == nil)
        #expect(state.carContextKey == placeholder)
        #expect(state.carSessionsByContext[placeholder]?.sessionID == session.id)
        #expect(state.carActiveTurnID != nil)
        #expect(await api.createSessionCalls.count == 1)

        await api.releaseProjectCurrent()
        await loading.value
        let resolved = "\(state.currentHostProfileID.uuidString)|/workspace/a"
        #expect(state.serverCurrentProjectWorktree == "/workspace/a")
        #expect(state.carLastKnownServerWorktree == "/workspace/a")
        #expect(state.carContextKey == resolved)
        #expect(state.carSessionsByContext[placeholder] == nil)
        #expect(state.carSessionsByContext[resolved]?.sessionID == session.id)
        #expect(state.carActiveTurnID != nil)

        await api.setProjectCurrentError(APIError.httpError(statusCode: 503, data: Data()))
        await state.loadProjects()
        #expect(state.serverCurrentProjectWorktree == nil)
        #expect(state.carLastKnownServerWorktree == "/workspace/a")
        #expect(state.carContextKey == resolved)
        #expect(state.carActiveTurnID != nil)
        #expect(speech.spokenTexts.isEmpty)
        #expect(speech.stopCount == 0)

        await api.releasePromptStructured()
        await turn.value

        #expect(speech.spokenTexts == ["Ready."])
        #expect(speech.stopCount == 0)
        #expect(state.carSessionsByContext[placeholder] == nil)
        #expect(state.carSessionsByContext[resolved]?.sessionID == session.id)
        #expect(state.carSessionsByContext[resolved]?.lastHandledAssistantMessageID == "assistant-lookup-nil")
        #expect(state.carSessionsByContext.count == 1)
        #expect(state.carPhase == .idle)
        #expect(state.pendingClientCapabilityRequest == nil)
        #expect(await api.createSessionCalls.count == 1)
        #expect(await api.abortSessionIDs.isEmpty)

        await state.submitCarTurn("Again")
        #expect(speech.spokenTexts == ["Ready."])
        #expect(await api.createSessionCalls.count == 1)
        #expect(await api.promptStructuredCalls.count == 2)
        #expect(await api.promptStructuredCalls.map(\.sessionID) == [session.id, session.id])
        #expect(await api.sessionRequests == [session.id])
        #expect(state.carSessionsByContext[placeholder] == nil)
        #expect(state.carSessionsByContext[resolved]?.sessionID == session.id)
        #expect(state.carSessionsByContext.count == 1)
    }
}

private func carSession(id: String, directory: String = "/tmp/car-workspace", archived: Int? = nil) -> Session {
    Session(
        id: id,
        slug: id,
        projectID: "p1",
        directory: directory,
        parentID: nil,
        title: "Car Mode",
        version: "1",
        time: .init(created: 1, updated: 1, archived: archived),
        share: nil,
        summary: nil
    )
}

private func carResponse(id: String, sessionID: String, envelope: CarResponseEnvelope) throws -> MessageWithParts {
    MessageWithParts(
        info: try Message(
            id: id,
            sessionID: sessionID,
            role: "assistant",
            parentID: "user-1",
            providerID: "openai",
            modelID: "gpt-5.6-sol-fast",
            model: nil,
            error: nil,
            time: .init(created: 2, completed: 3),
            finish: "tool-calls",
            tokens: nil,
            cost: nil,
            structured: envelope
        ),
        parts: []
    )
}

@MainActor
private final class CarCredentialFake {
    var saved: [String: String] = [:]

    func access() -> HostCredentialAccess {
        HostCredentialAccess(
            save: { [weak self] value, key in self?.saved[key] = value },
            load: { [weak self] key in self?.saved[key] },
            delete: { [weak self] key in self?.saved.removeValue(forKey: key) }
        )
    }
}

@MainActor
private final class CarHostHarness {
    let state: AppState
    let api: MockAPIClient
    let speech: MockCarSpeechOutput
    let suite: String
    let storeRoot: URL
    let previousSSH: Any?
    let otherHostID: UUID

    init() {
        suite = "opencode.car.w08.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        storeRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        previousSSH = UserDefaults.standard.object(forKey: "sshTunnelConfig")
        api = MockAPIClient()
        speech = MockCarSpeechOutput()
        let credentials = CarCredentialFake()
        state = AppState(
            apiClient: api,
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            carSpeechOutput: speech,
            clientCapabilityStore: ClientCapabilityCallbackStore(rootDirectory: storeRoot),
            userDefaults: defaults,
            hostCredentialAccess: credentials.access()
        )
        state.sshTunnelManager.config.isEnabled = false
        var other = HostProfile.defaultProfile(serverURL: "http://127.0.0.1:4010")
        other.name = "other-host"
        otherHostID = other.id
        state.hostProfiles.append(other)
    }

    func switchToOtherHost() {
        state.beginHostTransportTransition(to: otherHostID)
    }

    func cleanup() {
        state.disconnectSSE()
        state.hostTransportConfigureTask?.cancel()
        state.sshTunnelManager.disconnect()
        state.defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: storeRoot)
        if let previousSSH {
            UserDefaults.standard.set(previousSSH, forKey: "sshTunnelConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "sshTunnelConfig")
        }
    }
}
