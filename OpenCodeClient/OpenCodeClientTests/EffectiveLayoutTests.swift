import Foundation
import Testing
import UIKit
@testable import OpenCodeClient

struct EffectiveLayoutTests {
    @Test func automaticFollowsRegularWidth() {
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .regular) == .regular)
    }

    @Test func automaticCompactAndUnspecifiedStayCompact() {
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .compact) == .compact)
        #expect(EffectiveLayoutResolver.resolve(preference: .automatic, width: .unspecified) == .compact)
    }

    @Test func focusIgnoresRegularWidth() {
        #expect(EffectiveLayoutResolver.resolve(preference: .focus, width: .regular) == .compact)
        #expect(EffectiveLayoutResolver.resolve(preference: .focus, width: .compact) == .compact)
    }

    @Test func missingOrUnknownLayoutPreferenceStaysAutomatic() {
        #expect(LayoutPreference.resolved(from: nil) == .automatic)
        #expect(LayoutPreference.resolved(from: "") == .automatic)
        #expect(LayoutPreference.resolved(from: "phone") == .automatic)
        #expect(LayoutPreference.resolved(from: "focus") == .focus)
    }

    @Test func previewMigratesColumnToInlineWhenEnteringFocus() {
        let migrated = LayoutPreviewMigration.migrate(
            from: .regular,
            to: .compact,
            slots: LayoutPreviewSlots(inlinePath: nil, inlineWorkspace: nil, columnPath: "notes.md", columnWorkspace: "/work")
        )
        #expect(migrated.inlinePath == "notes.md")
        #expect(migrated.inlineWorkspace == "/work")
        #expect(migrated.columnPath == nil)
    }

    @Test func previewMigratesInlineToColumnWhenLeavingFocus() {
        let migrated = LayoutPreviewMigration.migrate(
            from: .compact,
            to: .regular,
            slots: LayoutPreviewSlots(inlinePath: "notes.md", inlineWorkspace: "/work", columnPath: nil, columnWorkspace: nil)
        )
        #expect(migrated.columnPath == "notes.md")
        #expect(migrated.columnWorkspace == "/work")
        #expect(migrated.inlinePath == nil)
    }

    @Test func occupiedPreviewDestinationIsNotOverwritten() {
        let slots = LayoutPreviewSlots(
            inlinePath: "chat.md",
            inlineWorkspace: "/chat",
            columnPath: "files.md",
            columnWorkspace: "/files"
        )
        #expect(LayoutPreviewMigration.migrate(from: .regular, to: .compact, slots: slots) == slots)
        #expect(LayoutPreviewMigration.migrate(from: .compact, to: .regular, slots: slots) == slots)
    }

    @Test func layoutChangeDoesNotForceBottomScroll() {
        #expect(ChatViewportPolicy.forcesBottom(on: .layoutChange) == false)
        #expect(ChatViewportPolicy.forcesBottom(on: .sessionChange) == true)
    }

    @Test func pasteAppendsWithExplicitNewlineAndKeepsOrder() {
        #expect(ComposerDraftMerge.appending(draft: "", addition: "pasted") == "pasted")
        #expect(ComposerDraftMerge.appending(draft: "draft", addition: "pasted") == "draft\npasted")
        #expect(ComposerDraftMerge.joinedPaste(["a", "", "b"]) == "a\nb")
    }

    @Test func editPasteRespectsSelectionOutsideSpeechSpan() {
        let placement = ComposerPastePlanner.placement(
            isEditing: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 5, length: 0),
            speechOwnedUTF16End: 5
        )
        #expect(placement == .insert(NSRange(location: 5, length: 0)))
        let inserted = ComposerDraftMerge.inserting(draft: "hello", addition: "X", selectionUTF16: NSRange(location: 5, length: 0))
        #expect(inserted.text == "helloX")
        #expect(inserted.cursorUTF16 == 6)
    }

    @Test func pasteInsideLiveTranscriptAppendsInsteadOfReplacingSpan() {
        let placement = ComposerPastePlanner.placement(
            isEditing: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 2, length: 0),
            speechOwnedUTF16End: 8
        )
        #expect(placement == .append)
    }

    @Test func markedTextDefersPaste() {
        #expect(
            ComposerPastePlanner.placement(
                isEditing: true,
                hasMarkedText: true,
                selectionUTF16: NSRange(location: 1, length: 0),
                speechOwnedUTF16End: nil
            ) == .deferUntilMarkedTextEnds
        )
    }

    @Test func nonEditingPasteAppends() {
        #expect(
            ComposerPastePlanner.placement(
                isEditing: false,
                hasMarkedText: false,
                selectionUTF16: NSRange(location: 1, length: 0),
                speechOwnedUTF16End: nil
            ) == .append
        )
    }

    @Test func transcriptUpdateKeepsPasteTail() {
        var protector = SpeechDraftProtector()
        protector.begin(prefix: "draft", sessionID: "s1")
        let first = protector.render(prefix: "draft", transcript: "hello")
        #expect(first == "draft hello")
        protector.noteVisibleText(ComposerDraftMerge.appending(draft: first, addition: "pasted"))
        let second = protector.render(prefix: "draft", transcript: "hello there")
        #expect(second == "draft hello there\npasted")
        #expect(protector.preservedTail(for: "s1") == "pasted")
    }

    @Test func markedTextBlocksComposerBindingAssignment() {
        #expect(ComposerFocusPolicy.shouldAssignComposerText(hasMarkedText: true) == false)
        #expect(ComposerFocusPolicy.shouldAssignComposerText(hasMarkedText: false) == true)
    }

    @Test func voiceFirstStaysReadOnlyUntilExplicitEdit() {
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: false))
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: true))
        #expect(ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: true))
    }

    @Test func pasteHitTargetStaysAtLeastFortyFour() {
        #expect(ComposerHitTarget.minimum >= 44)
    }

    @MainActor
    @Test func layoutAndVoiceFirstDefaultsStayCompatibleAndRoundTrip() {
        let defaults = UserDefaults(suiteName: "opencode.tests.layout.\(UUID().uuidString)")!
        let state = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(state.layoutPreference == .automatic)
        #expect(state.voiceFirstInput == false)

        state.layoutPreference = .focus
        state.voiceFirstInput = true
        let restored = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(restored.layoutPreference == .focus)
        #expect(restored.voiceFirstInput == true)

        defaults.set("nope", forKey: AppState.layoutPreferenceKey)
        let unknown = AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
        #expect(unknown.layoutPreference == .automatic)
    }
}

struct ComposerOwnershipTests {
    @Test func pasteHandoffCapturesOriginBeforeProviderLoad() async {
        let source = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: UUID(), generation: 1))
        let destination = ComposerWriteOrigin(sessionID: "b", host: HostRequestSnapshot(hostProfileID: UUID(), generation: 2))
        var current = source
        var delivered: ComposerWriteOrigin?
        await ComposerPasteHandoff.captureThenLoad {
            let captured = current
            return { strings in
                #expect(strings == ["pasted"])
                delivered = captured
            }
        } load: {
            current = destination
            return ["pasted"]
        }
        #expect(delivered == source)
    }

    @MainActor
    @Test func pasteControlDecodesStringProvider() async {
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        let strings = await ComposerPastePayload.strings(from: [provider])
        #expect(strings == ["FOCUS_VOICE_PASTE_SENTINEL"])
    }

    @MainActor
    @Test func pasteControlCapturesOriginWhenPasteBegins() async {
        let coordinator = ComposerPasteControl.Coordinator()
        var generation = 0
        var delivered: (Int, [String])?
        coordinator.beginPaste = {
            generation += 1
            let captured = generation
            return { parts in
                delivered = (captured, parts)
            }
        }
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        coordinator.paste(itemProviders: [provider])
        #expect(generation == 1)
        coordinator.beginPaste = {
            generation += 1
            return { _ in
                delivered = (99, [])
            }
        }
        for _ in 0..<50 where delivered == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(delivered?.0 == 1)
        #expect(delivered?.1 == ["FOCUS_VOICE_PASTE_SENTINEL"])
    }

    @MainActor
    @Test func delayedPasteAfterSessionOrHostSwitchStaysOnSourceDraft() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let source = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("keep-a", for: "a", hostProfileID: hostA)
        state.currentHostProfileID = hostB
        state.currentSessionID = "b"
        ComposerOwnedWrite.pasteIntoSourceDraft(addition: "pasted", origin: source, state: state)
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "keep-a\npasted")
        #expect(state.draftText(for: "b", hostProfileID: hostB) == "")
        #expect(state.draftText(for: "a", hostProfileID: hostB) == "")
    }

    @MainActor
    @Test func deferredSpeechAfterSessionOrHostSwitchDoesNotEnterCurrentDraft() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let origin = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("hello", for: "a", hostProfileID: hostA)
        state.currentHostProfileID = hostB
        state.currentSessionID = "b"
        state.setDraftText("destination", for: "b", hostProfileID: hostB)
        let merged = ComposerOwnedWrite.speechIntoSourceDraft(
            prefix: "hello",
            transcript: "there",
            origin: origin,
            state: state
        )
        #expect(merged == "hello there")
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "hello there")
        #expect(state.draftText(for: "b", hostProfileID: hostB) == "destination")
        #expect(ComposerOwnedWrite.sameVisibleComposer(
            origin: origin,
            currentSessionID: state.currentSessionID,
            currentHostID: state.currentHostProfileID
        ) == false)
    }

    @MainActor
    @Test func noncurrentSpeechKeepsPasteAppendedAfterSwitch() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let origin = ComposerWriteOrigin(sessionID: "a", host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.setDraftText("hello partial\npasted", for: "a", hostProfileID: hostA)
        let merged = ComposerOwnedWrite.speechIntoSourceDraft(
            prefix: "hello",
            transcript: "final",
            origin: origin,
            state: state
        )
        #expect(merged == "hello final\npasted")
        #expect(state.draftText(for: "a", hostProfileID: hostA) == "hello final\npasted")
    }

    @MainActor
    @Test func nilSessionPasteStaysOnOriginHost() {
        let state = makeState()
        let hostA = state.currentHostProfileID
        let hostB = UUID()
        let origin = ComposerWriteOrigin(sessionID: nil, host: HostRequestSnapshot(hostProfileID: hostA, generation: 1))
        state.currentHostProfileID = hostB
        ComposerOwnedWrite.pasteIntoSourceDraft(addition: "orphan", origin: origin, state: state)
        #expect(state.draftText(for: nil, hostProfileID: hostA) == "orphan")
        #expect(state.draftText(for: nil, hostProfileID: hostB) == "")
        #expect(state.draftText(for: nil) == "")
    }

    @Test func pasteDuringSendFailureIsKeptWhenRevisionAdvances() {
        let edited = ComposerRevisionEdit.applying(current: "sent", revision: 3, edited: "sent\npasted")
        let host = HostRequestSnapshot(hostProfileID: UUID(), generation: 1)
        let restored = ChatComposerRestore.textAndAttachments(
            sourceSessionID: "a",
            currentSessionID: "a",
            capturedRevision: 3,
            currentRevision: edited.revision,
            capturedHost: host,
            currentHost: host,
            capturedSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sentText: "sent",
            sentAttachments: [],
            currentText: edited.text,
            currentAttachments: []
        )
        #expect(edited.revision == 4)
        #expect(restored.text == "sent\npasted")
        let clearedThenPasted = ChatComposerRestore.textAndAttachments(
            sourceSessionID: "a",
            currentSessionID: "a",
            capturedRevision: 3,
            currentRevision: 4,
            capturedHost: host,
            currentHost: host,
            capturedSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentSelection: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sentText: "sent",
            sentAttachments: [],
            currentText: "pasted",
            currentAttachments: []
        )
        #expect(clearedThenPasted.text == "sent\npasted")
    }

    @MainActor
    private func makeState() -> AppState {
        let defaults = UserDefaults(suiteName: "opencode.tests.ownership.\(UUID().uuidString)")!
        return AppState(
            apiClient: MockAPIClient(),
            sseClient: MockSSEClient(),
            sshTunnelManager: SSHTunnelManager(defaults: defaults),
            userDefaults: defaults,
            hostCredentialAccess: .noExternal
        )
    }
}
