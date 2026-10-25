//
//  DesignHaptics.swift
//  OpenCodeClient
//
//  Named haptic events and the policy that governs when they may fire.
//  The machine-checkable form of this policy is `docs/design.md` §QT-HAPTIC;
//  the rubric rows it backs are `POL-HAPTIC-01…09` in
//  `docs/features/polish/rubric.md`.
//

import Foundation

#if os(iOS)
import UIKit
#endif

// MARK: - Event

/// A named haptic event — one case per interaction class.
///
/// Every haptic the app can fire is listed here, so the rubric matrix has
/// exactly one implementation site per event and the two can be checked against
/// each other.
nonisolated enum DesignHapticEvent: String, CaseIterable {
    /// A message was accepted by the server.
    case messageSent
    /// A message could not be sent; the draft was restored for the user.
    case sendFailed
    /// The agent is asking for a permission.
    case permissionArrived
    /// The agent is asking a question.
    case questionArrived
    /// The user committed a destructive action (session delete).
    case destructiveConfirmed
    /// The selected session changed.
    case selectionChanged
    /// Voice recording started.
    case recordingStarted
    /// Voice recording stopped.
    case recordingStopped

    /// Alerting events carry information the user cannot otherwise see, so they
    /// survive Reduce Motion. Confirming events refine an action the user already
    /// sees, so they are dropped when motion is reduced.
    var isAlerting: Bool {
        switch self {
        case .sendFailed, .permissionArrived, .questionArrived, .destructiveConfirmed:
            return true
        case .messageSent, .selectionChanged, .recordingStarted, .recordingStopped:
            return false
        }
    }

    /// Events that fire exactly as the microphone opens or closes.
    ///
    /// These are **not** exempt from the microphone guard. They are exempt from
    /// *their own* capture by construction: the recording sites evaluate the
    /// capture state before their own capture opens and after it closes, so the
    /// flag they pass describes whether some *other* capture is live. A
    /// simultaneous Ambient capture still suppresses them.
    var isMicrophoneBoundary: Bool {
        self == .recordingStarted || self == .recordingStopped
    }

    /// Silent mode does not affect haptics. The feedback generators emit no
    /// audio component, so the ringer switch is irrelevant — only Reduce Motion
    /// and the microphone guard suppress an event.
    var isAffectedBySilentMode: Bool { false }
}

// MARK: - Signature

/// The concrete haptic an event maps to.
///
/// Kept separate from UIKit so the mapping stays pure and testable, and so every
/// event is guaranteed a distinct signature. There is one spare case so a ninth
/// event does not force two events onto the same signature.
nonisolated enum DesignHapticSignature: String, CaseIterable, Equatable {
    case lightImpact
    case mediumImpact
    case heavyImpact
    case rigidImpact
    case softImpact
    case errorNotification
    case warningNotification
    case successNotification
    case selectionChange

    /// The signature each event fires. Every event maps to a distinct signature,
    /// so two different events are never felt as the same thing.
    static func signature(for event: DesignHapticEvent) -> DesignHapticSignature {
        switch event {
        case .messageSent: return .lightImpact
        case .questionArrived: return .mediumImpact
        case .recordingStopped: return .heavyImpact
        case .recordingStarted: return .rigidImpact
        case .permissionArrived: return .softImpact
        case .sendFailed: return .errorNotification
        case .destructiveConfirmed: return .warningNotification
        case .selectionChanged: return .selectionChange
        }
    }
}

// MARK: - Policy

/// The policy, as a pure function so it can be tested without UIKit.
///
/// 1. **Microphone guard.** While the microphone is open, **no** haptic fires. A
///    haptic is a mechanical event that the capture can pick up, and the
///    privacy review requires that nothing fires while audio is being
///    recorded. There is no blanket exemption: the recording start and stop
///    events pass the capture state as it is *before* their own capture opens
///    and *after* it closes, so they are unaffected by their own capture and
///    still suppressed by any other one.
/// 2. **Reduce Motion.** Confirming events are dropped; alerting events are
///    kept, because their information is not otherwise available.
/// 3. **Silent mode** has no effect — see `isAffectedBySilentMode`.
nonisolated extension DesignHapticEvent {
    func isAllowed(reduceMotion: Bool, microphoneOpen: Bool) -> Bool {
        if microphoneOpen { return false }
        if reduceMotion && !isAlerting { return false }
        return true
    }
}

// MARK: - Announcement ledger

/// A bounded, insertion-ordered set of request ids that have already been
/// announced haptically.
///
/// This is deliberately separate from the live pending-request lists. Those are
/// mutated by answering: answering removes a request, and a poll can briefly
/// re-list one the server has not yet dropped. Deriving "already announced"
/// from the live list therefore re-announced a permission the instant the user
/// answered it.
///
/// Request ids are unique per request, so a genuinely new request is still
/// announced and a re-listed one is not. The ledger is capped so a long-lived
/// session cannot grow it without bound.
nonisolated struct DesignAnnouncementLedger {
    private var order: [String] = []
    private var members: Set<String> = []
    private let limit: Int

    init(limit: Int = 128) {
        self.limit = max(1, limit)
    }

    /// True when `id` has not been announced before.
    func needsAnnouncement(_ id: String) -> Bool {
        !members.contains(id)
    }

    /// Record `id` as announced.
    mutating func markAnnounced(_ id: String) {
        guard !members.contains(id) else { return }
        members.insert(id)
        order.append(id)
        while order.count > limit {
            members.remove(order.removeFirst())
        }
    }
}

// MARK: - Firing

/// Fires the app's haptics.
///
/// The generators are long-lived so the Taptic Engine stays warm between
/// events; `prepare()` is called before each event so the *next* one is not
/// late. It cannot warm the engine for the event it precedes — the interaction
/// has to be anticipated to do that.
@MainActor
enum DesignHaptics {
    #if os(iOS)
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    /// Fire `event`.
    ///
    /// - Parameter microphoneOpen: **must** be passed explicitly — there is no
    ///   default. A default would silently let a call site announce itself into
    ///   an open capture, which is exactly the exposure the microphone guard
    ///   exists to prevent. Pass `state.isMicrophoneCaptureActive` from an
    ///   `AppState`-aware site.
    static func fire(_ event: DesignHapticEvent, microphoneOpen: Bool) {
        #if os(iOS)
        guard event.isAllowed(reduceMotion: UIAccessibility.isReduceMotionEnabled,
                              microphoneOpen: microphoneOpen) else { return }
        switch DesignHapticSignature.signature(for: event) {
        case .lightImpact:
            lightImpact.prepare()
            lightImpact.impactOccurred()
        case .mediumImpact:
            mediumImpact.prepare()
            mediumImpact.impactOccurred()
        case .heavyImpact:
            heavyImpact.prepare()
            heavyImpact.impactOccurred()
        case .rigidImpact:
            rigidImpact.prepare()
            rigidImpact.impactOccurred()
        case .softImpact:
            softImpact.prepare()
            softImpact.impactOccurred()
        case .errorNotification:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.error)
        case .warningNotification:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.warning)
        case .successNotification:
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(.success)
        case .selectionChange:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        }
        #endif
    }
}
