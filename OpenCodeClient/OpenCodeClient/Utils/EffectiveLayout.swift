import Foundation
import SwiftUI

enum LayoutPreference: String, CaseIterable, Identifiable {
    case automatic
    case focus

    var id: String { rawValue }

    static func resolved(from raw: String?) -> LayoutPreference {
        guard let raw, let value = LayoutPreference(rawValue: raw) else { return .automatic }
        return value
    }
}

enum WindowWidthClass: Equatable {
    case regular
    case compact
    case unspecified

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        switch horizontalSizeClass {
        case .regular:
            self = .regular
        case .compact:
            self = .compact
        default:
            self = .unspecified
        }
    }
}

enum EffectiveLayout: Equatable {
    case compact
    case regular
}

enum EffectiveLayoutResolver {
    static func resolve(preference: LayoutPreference, width: WindowWidthClass) -> EffectiveLayout {
        switch preference {
        case .focus:
            return .compact
        case .automatic:
            return width == .regular ? .regular : .compact
        }
    }
}

private struct EffectiveLayoutKey: EnvironmentKey {
    static let defaultValue = EffectiveLayout.compact
}

extension EnvironmentValues {
    var effectiveLayout: EffectiveLayout {
        get { self[EffectiveLayoutKey.self] }
        set { self[EffectiveLayoutKey.self] = newValue }
    }
}

struct LayoutPreviewSlots: Equatable {
    var inlinePath: String?
    var inlineWorkspace: String?
    var columnPath: String?
    var columnWorkspace: String?

    static let empty = LayoutPreviewSlots()
}

enum LayoutPreviewMigration {
    static func migrate(
        from: EffectiveLayout,
        to: EffectiveLayout,
        slots: LayoutPreviewSlots
    ) -> LayoutPreviewSlots {
        guard from != to else { return slots }
        var next = slots
        switch to {
        case .compact:
            if next.inlinePath == nil, let column = next.columnPath, !column.isEmpty {
                next.inlinePath = column
                next.inlineWorkspace = next.columnWorkspace
                next.columnPath = nil
                next.columnWorkspace = nil
            }
        case .regular:
            if next.columnPath == nil, let inline = next.inlinePath, !inline.isEmpty {
                next.columnPath = inline
                next.columnWorkspace = next.inlineWorkspace
                next.inlinePath = nil
                next.inlineWorkspace = nil
            }
        }
        return next
    }
}

enum ChatViewportReset: Equatable {
    case sessionChange
    case layoutChange
}

enum ChatViewportPolicy {
    static func forcesBottom(on reset: ChatViewportReset) -> Bool {
        switch reset {
        case .sessionChange:
            return true
        case .layoutChange:
            return false
        }
    }
}

enum ComposerHitTarget {
    static let minimum: CGFloat = 44
}

struct ComposerWriteOrigin: Equatable, Sendable {
    var sessionID: String?
    var host: HostRequestSnapshot
}

struct DeferredPasteWrite: Equatable {
    var addition: String
    var origin: ComposerWriteOrigin
}

struct DeferredSpeechWrite: Equatable {
    var prefix: String
    var transcript: String
    var origin: ComposerWriteOrigin
}

enum ComposerPasteHandoff {
    static func captureThenLoad(
        begin: () -> ([String]) -> Void,
        load: () async -> [String]
    ) async {
        let deliver = begin()
        let strings = await load()
        deliver(strings)
    }
}

enum ComposerRevisionEdit {
    static func applying(current: String, revision: UInt64, edited: String) -> (text: String, revision: UInt64) {
        guard edited != current else { return (current, revision) }
        return (edited, revision &+ 1)
    }
}

enum ComposerOwnedWrite {
    static func sameVisibleComposer(
        origin: ComposerWriteOrigin,
        currentSessionID: String?,
        currentHostID: UUID
    ) -> Bool {
        origin.host.hostProfileID == currentHostID && origin.sessionID == currentSessionID
    }

    @discardableResult
    static func pasteIntoSourceDraft(
        addition: String,
        origin: ComposerWriteOrigin,
        state: AppState
    ) -> String {
        let latest = state.draftText(for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        let merged = ComposerDraftMerge.appending(draft: latest, addition: addition)
        state.setDraftText(merged, for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        return merged
    }

    @discardableResult
    static func speechIntoSourceDraft(
        prefix: String,
        transcript: String,
        origin: ComposerWriteOrigin,
        state: AppState
    ) -> String {
        let latest = state.draftText(for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        let merged = ComposerDraftMerge.mergingSpeech(
            prefix: prefix,
            transcript: transcript,
            latestDraft: latest
        )
        state.setDraftText(merged, for: origin.sessionID, hostProfileID: origin.host.hostProfileID)
        return merged
    }
}

enum ComposerFocusPolicy {
    static func isTextEditable(voiceFirst: Bool, isEditing: Bool) -> Bool {
        _ = (voiceFirst, isEditing)
        return true
    }

    static func requestsFirstResponder(voiceFirst: Bool, isEditing: Bool) -> Bool {
        voiceFirst && isEditing
    }

    static func suppressesSoftwareKeyboard(voiceFirst: Bool, isEditing: Bool) -> Bool {
        voiceFirst && !isEditing
    }

    static func shouldAssignComposerText(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }
}

enum ComposerPastePlacement: Equatable {
    case append
    case insert(NSRange)
    case deferUntilMarkedTextEnds
}

enum ComposerPastePlanner {
    static func placement(
        hasCaretFocus: Bool,
        hasMarkedText: Bool,
        selectionUTF16: NSRange?,
        speechOwnedUTF16End: Int?
    ) -> ComposerPastePlacement {
        if hasMarkedText { return .deferUntilMarkedTextEnds }
        guard hasCaretFocus, let selectionUTF16, selectionUTF16.location != NSNotFound else { return .append }
        if let speechEnd = speechOwnedUTF16End, selectionUTF16.location < speechEnd {
            return .append
        }
        return .insert(selectionUTF16)
    }
}

enum ComposerDraftMerge {
    static func joinedPaste(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func appending(draft: String, addition: String) -> String {
        guard !addition.isEmpty else { return draft }
        guard !draft.isEmpty else { return addition }
        return draft + "\n" + addition
    }

    static func inserting(draft: String, addition: String, selectionUTF16: NSRange) -> (text: String, cursorUTF16: Int) {
        guard !addition.isEmpty else {
            return (draft, selectionUTF16.location)
        }
        let ns = draft as NSString
        let length = ns.length
        let location = min(max(0, selectionUTF16.location), length)
        let rangeLength = min(max(0, selectionUTF16.length), length - location)
        let replaced = ns.replacingCharacters(in: NSRange(location: location, length: rangeLength), with: addition)
        return (replaced, location + (addition as NSString).length)
    }

    static func speechText(prefix: String, transcript: String, tail: String) -> String {
        appending(
            draft: ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript),
            addition: tail
        )
    }

    /// Keep newline-appended user text from the source draft. Do not replace that draft with a cached tail.
    static func mergingSpeech(prefix: String, transcript: String, latestDraft: String) -> String {
        let speech = ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript)
        let addition = userAppendedTail(in: latestDraft, afterPrefix: prefix)
        if addition.isEmpty {
            if latestDraft.isEmpty || prefix.isEmpty || latestDraft.hasPrefix(prefix) {
                return speech
            }
            return latestDraft
        }
        if speech == addition || speech.hasSuffix("\n" + addition) {
            return speech
        }
        return appending(draft: speech, addition: addition)
    }

    static func userAppendedTail(in draft: String, afterPrefix prefix: String) -> String {
        guard !draft.isEmpty else { return "" }
        let rest: Substring
        if prefix.isEmpty {
            rest = Substring(draft)
        } else if draft.hasPrefix(prefix) {
            rest = draft.dropFirst(prefix.count)
        } else {
            return ""
        }
        guard let newline = rest.firstIndex(of: "\n") else { return "" }
        return String(rest[rest.index(after: newline)...])
    }

    static func tail(afterSpeech speech: String, in rendered: String) -> String {
        guard !speech.isEmpty else { return rendered }
        if rendered == speech { return "" }
        let withBreak = speech + "\n"
        if rendered.hasPrefix(withBreak) {
            return String(rendered.dropFirst(withBreak.count))
        }
        if rendered.hasPrefix(speech) {
            let rest = rendered.dropFirst(speech.count)
            if rest.hasPrefix("\n") {
                return String(rest.dropFirst())
            }
            return String(rest)
        }
        return ""
    }
}

struct SpeechDraftProtector: Equatable {
    var anchor: String = ""
    var tail: String = ""
    var ownerSessionID: String?
    var tailsBySession: [String: String] = [:]

    mutating func begin(prefix: String, sessionID: String?) {
        anchor = prefix
        tail = ""
        ownerSessionID = sessionID
        if let sessionID {
            tailsBySession[sessionID] = ""
        }
    }

    mutating func ensureAnchor(_ prefix: String) {
        if anchor.isEmpty {
            anchor = prefix
        }
    }

    mutating func noteVisibleText(_ text: String) {
        guard !anchor.isEmpty else { return }
        if text == anchor || text.hasPrefix(anchor) {
            tail = ComposerDraftMerge.tail(afterSpeech: anchor, in: text)
            if let ownerSessionID {
                tailsBySession[ownerSessionID] = tail
            }
        }
    }

    func preservedTail(for sessionID: String?) -> String {
        guard let sessionID else { return tail }
        return tailsBySession[sessionID] ?? ""
    }

    mutating func render(prefix: String, transcript: String) -> String {
        let speech = ChatSpeechRouting.mergedInput(prefix: prefix, transcript: transcript)
        let rendered = ComposerDraftMerge.appending(draft: speech, addition: tail)
        anchor = speech
        return rendered
    }
}
