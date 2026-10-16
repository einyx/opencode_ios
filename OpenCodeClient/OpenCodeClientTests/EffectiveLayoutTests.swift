import Foundation
import SwiftUI
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

    @Test func filesPushBecomesColumnThenInline() {
        let compactToRegular = PreviewLayoutTransition.apply(
            from: .compact,
            to: .regular,
            input: PreviewLayoutInput(
                slots: .empty,
                filesPath: ["notes.txt"],
                filesWorkspace: "/tmp/w06-files",
                filesHostMatches: true,
                pendingPath: nil,
                pendingWorkspace: nil,
                pendingHostMatches: true
            )
        )
        #expect(compactToRegular.slots.columnPath == "notes.txt")
        #expect(compactToRegular.slots.columnWorkspace == "/tmp/w06-files")
        #expect(compactToRegular.filesPath.isEmpty)

        let back = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: compactToRegular.slots,
                filesPath: compactToRegular.filesPath,
                filesWorkspace: "/tmp/w06-files",
                filesHostMatches: true,
                pendingPath: nil,
                pendingWorkspace: nil,
                pendingHostMatches: true
            )
        )
        #expect(back.slots.inlinePath == "notes.txt")
        #expect(back.slots.inlineWorkspace == "/tmp/w06-files")
        #expect(back.slots.columnPath == nil)
    }

    @Test func foreignHostFilesPushIsNotRestored() {
        let migrated = PreviewLayoutTransition.apply(
            from: .compact,
            to: .regular,
            input: PreviewLayoutInput(
                slots: .empty,
                filesPath: ["secret.txt"],
                filesWorkspace: "/other",
                filesHostMatches: false,
                pendingPath: "pending.md",
                pendingWorkspace: "/other",
                pendingHostMatches: false
            )
        )
        #expect(migrated.slots == .empty)
        #expect(migrated.filesPath.isEmpty)
        #expect(migrated.pendingPath == nil)
    }

    @Test func visibleColumnReplacesHiddenInline() {
        let slots = LayoutPreviewSlots(
            inlinePath: "old.md",
            inlineWorkspace: "/old",
            columnPath: "current.md",
            columnWorkspace: "/current"
        )
        let migrated = LayoutPreviewMigration.migrate(from: .regular, to: .compact, slots: slots)
        #expect(migrated.inlinePath == "current.md")
        #expect(migrated.inlineWorkspace == "/current")
        #expect(migrated.columnPath == nil)
    }

    @Test func visibleInlineReplacesHiddenColumn() {
        let slots = LayoutPreviewSlots(
            inlinePath: "current.md",
            inlineWorkspace: "/current",
            columnPath: "old.md",
            columnWorkspace: "/old"
        )
        let migrated = LayoutPreviewMigration.migrate(from: .compact, to: .regular, slots: slots)
        #expect(migrated.columnPath == "current.md")
        #expect(migrated.columnWorkspace == "/current")
        #expect(migrated.inlinePath == nil)
    }

    @Test func newerPendingOpenReplacesVisibleSlot() {
        let migrated = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: LayoutPreviewSlots(inlinePath: "old.md", inlineWorkspace: "/old", columnPath: "seen.md", columnWorkspace: "/seen"),
                columnSequence: 2,
                inlineSequence: 1,
                filesPath: [],
                filesWorkspace: nil,
                filesHostMatches: true,
                pendingPath: "link.md",
                pendingWorkspace: "/link",
                pendingHostMatches: true,
                pendingSequence: 3
            )
        )
        #expect(migrated.slots.inlinePath == "link.md")
        #expect(migrated.slots.columnPath == nil)
        #expect(migrated.pendingPath == nil)
    }

    @Test func olderPendingOpenDoesNotReplaceVisibleSlot() {
        let migrated = PreviewLayoutTransition.apply(
            from: .regular,
            to: .compact,
            input: PreviewLayoutInput(
                slots: LayoutPreviewSlots(inlinePath: "old.md", inlineWorkspace: "/old", columnPath: "seen.md", columnWorkspace: "/seen"),
                columnSequence: 5,
                inlineSequence: 1,
                filesPath: [],
                filesWorkspace: nil,
                filesHostMatches: true,
                pendingPath: "link.md",
                pendingWorkspace: "/link",
                pendingHostMatches: true,
                pendingSequence: 3
            )
        )
        #expect(migrated.slots.inlinePath == "seen.md")
        #expect(migrated.slots.inlineWorkspace == "/seen")
        #expect(migrated.slots.columnPath == nil)
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
            hasCaretFocus: true,
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
            hasCaretFocus: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 2, length: 0),
            speechOwnedUTF16End: 8
        )
        #expect(placement == .append)
    }

    @Test func markedTextDefersPaste() {
        #expect(
            ComposerPastePlanner.placement(
                hasCaretFocus: true,
                hasMarkedText: true,
                selectionUTF16: NSRange(location: 1, length: 0),
                speechOwnedUTF16End: nil
            ) == .deferUntilMarkedTextEnds
        )
    }

    @Test func nonEditingPasteAppends() {
        #expect(
            ComposerPastePlanner.placement(
                hasCaretFocus: false,
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

    @Test func voiceFirstStaysEditableWithoutAutoFocusUntilExplicitKeyboard() {
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: false, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: false, isEditing: false))
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: false))
        #expect(ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: true, isEditing: false))
        #expect(!ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: false))
        #expect(ComposerFocusPolicy.isTextEditable(voiceFirst: true, isEditing: true))
        #expect(!ComposerFocusPolicy.suppressesSoftwareKeyboard(voiceFirst: true, isEditing: true))
        #expect(ComposerFocusPolicy.requestsFirstResponder(voiceFirst: true, isEditing: true))
    }

    @Test func focusedCaretPasteInsertsWithoutSoftwareKeyboard() {
        let placement = ComposerPastePlanner.placement(
            hasCaretFocus: true,
            hasMarkedText: false,
            selectionUTF16: NSRange(location: 2, length: 0),
            speechOwnedUTF16End: nil
        )
        #expect(placement == .insert(NSRange(location: 2, length: 0)))
        let inserted = ComposerDraftMerge.inserting(
            draft: "hello",
            addition: "X",
            selectionUTF16: NSRange(location: 2, length: 0)
        )
        #expect(inserted.text == "heXllo")
    }

    @MainActor
    @Test func textViewSeparatesCaretFocusFromSoftwareKeyboard() {
        let previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let textView = ReloadCountingTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        textView.text = "hello"
        textView.isEditable = true
        textView.isSelectable = true
        textView.setSoftwareKeyboardSuppressed(true)
        textView.selectedRange = NSRange(location: 2, length: 0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        window.addSubview(textView)
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
            window.resignKey()
            previousKey?.makeKey()
        }
        window.makeKeyAndVisible()
        textView.layoutIfNeeded()
        #expect(textView.becomeFirstResponder())
        let reloadsAfterFocus = textView.reloadCount
        textView.setSoftwareKeyboardSuppressed(true)
        #expect(textView.reloadCount == reloadsAfterFocus)
        #expect(textView.isFirstResponder)
        #expect(textView.isEditable)
        #expect(textView.softwareKeyboardSuppressed)
        #expect(textView.inputView is ZeroHeightInputView)
        #expect(textView.inputView?.intrinsicContentSize.height == 0)
        let caret = textView.caretRect(for: textView.selectedTextRange!.start)
        #expect(caret.height > 0)
        textView.setSoftwareKeyboardSuppressed(false)
        #expect(textView.reloadCount == reloadsAfterFocus + 1)
        #expect(textView.inputView == nil)
        #expect(textView.isFirstResponder)
    }

    @MainActor
    @Test func tapFocusResignsWhenSessionEpochChanges() {
        let previousKey = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        let textView = IMEAwareTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        textView.text = "hello"
        textView.isEditable = true
        textView.setSoftwareKeyboardSuppressed(true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        window.addSubview(textView)
        defer {
            textView.resignFirstResponder()
            window.isHidden = true
            window.resignKey()
            previousKey?.makeKey()
        }
        window.makeKeyAndVisible()
        #expect(textView.becomeFirstResponder())
        #expect(textView.isFirstResponder)
        let coordinator = ChatComposerTextView.Coordinator(
            text: .constant("hello"),
            hasMarkedText: .constant(false),
            onSubmit: {}
        )
        coordinator.requestsFirstResponder = false
        coordinator.focusScheduled = true
        coordinator.applyFocusReset(epoch: 1, to: textView)
        #expect(!textView.isFirstResponder)
        #expect(!coordinator.focusScheduled)
        coordinator.applyFocusReset(epoch: 1, to: textView)
        #expect(coordinator.seenFocusResetEpoch == 1)
    }

    @MainActor
    @Test func pasteCallbackInsertsAtMiddleSelection() async {
        let coordinator = ComposerPasteButton.Coordinator()
        var selection = NSRange(location: 1, length: 0)
        var merged = ""
        coordinator.beginPaste = {
            let captured = selection
            return { parts in
                let addition = ComposerDraftMerge.joinedPaste(parts)
                merged = ComposerDraftMerge.inserting(
                    draft: "ab",
                    addition: addition,
                    selectionUTF16: captured
                ).text
            }
        }
        let provider = NSItemProvider(object: "FOCUS_VOICE_PASTE_SENTINEL" as NSString)
        coordinator.paste(itemProviders: [provider])
        for _ in 0..<50 where merged.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(merged == "aFOCUS_VOICE_PASTE_SENTINELb")
        #expect(selection.location == 1)
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
        let coordinator = ComposerPasteButton.Coordinator()
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

private final class ReloadCountingTextView: IMEAwareTextView {
    var reloadCount = 0

    override func reloadInputViews() {
        reloadCount += 1
        super.reloadInputViews()
    }
}
