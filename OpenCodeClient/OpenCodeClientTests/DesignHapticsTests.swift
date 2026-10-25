import Foundation
import Testing
@testable import OpenCodeClient

/// Covers the haptic policy in `Utils/DesignHaptics.swift`.
///
/// The rubric rows this file backs:
/// `POL-HAPTIC-01…07` (one distinct implementation per event),
/// `POL-HAPTIC-08` (nothing fires while the microphone is open),
/// `POL-HAPTIC-09` (an explicit Reduce Motion / silent-mode policy).
@MainActor
struct DesignHapticsTests {

    // MARK: - Event set

    @Test func theEventSetHasNotChangedWithoutUpdatingTheRubric() {
        // Canary: `docs/features/polish/rubric.md` enumerates the matrix. Adding
        // an event without updating the rubric must fail here first.
        #expect(DesignHapticEvent.allCases.count == 8)
        #expect(DesignHapticEvent.allCases.contains(.messageSent))
        #expect(DesignHapticEvent.allCases.contains(.sendFailed))
        #expect(DesignHapticEvent.allCases.contains(.permissionArrived))
        #expect(DesignHapticEvent.allCases.contains(.questionArrived))
        #expect(DesignHapticEvent.allCases.contains(.destructiveConfirmed))
        #expect(DesignHapticEvent.allCases.contains(.selectionChanged))
        #expect(DesignHapticEvent.allCases.contains(.recordingStarted))
        #expect(DesignHapticEvent.allCases.contains(.recordingStopped))
    }

    @Test func everyEventMapsToADistinctSignature() {
        // Two different events must never be felt as the same thing.
        let signatures = DesignHapticEvent.allCases.map { DesignHapticSignature.signature(for: $0) }
        #expect(Set(signatures).count == DesignHapticEvent.allCases.count)
    }

    @Test func thereIsAtLeastOneSpareSignature() {
        // A ninth event must not force two events onto the same signature.
        #expect(DesignHapticSignature.allCases.count > DesignHapticEvent.allCases.count)
    }

    // MARK: - Microphone guard (POL-HAPTIC-08)

    @Test func microphoneGuardSuppressesEveryEvent() {
        // While the microphone is open, nothing may fire: a haptic is a
        // mechanical event the capture can pick up. There is no blanket
        // exemption — the recording events are exempt from their *own* capture
        // by construction, because the call site evaluates the capture state
        // before its own capture opens and after it closes.
        for event in DesignHapticEvent.allCases {
            #expect(!event.isAllowed(reduceMotion: false, microphoneOpen: true), "\(event.rawValue)")
        }
    }

    @Test func theRecordingPairIsTheOnlyBoundaryEvent() {
        // Documents which events announce a capture boundary. They get no
        // exemption — they only happen to be evaluated outside their own
        // capture window.
        let boundary = Set(DesignHapticEvent.allCases.filter(\.isMicrophoneBoundary))
        #expect(boundary == [.recordingStarted, .recordingStopped])
    }

    @Test func anOpenMicrophoneSuppressesEvenTheAlertingEvents() {
        // An alerting event must not survive an open microphone: "the agent needs
        // you" is still something the session indicator and the card convey.
        for event in DesignHapticEvent.allCases where event.isAlerting {
            #expect(!event.isAllowed(reduceMotion: false, microphoneOpen: true), "\(event.rawValue)")
        }
    }

    // MARK: - Reduce Motion (POL-HAPTIC-09)

    @Test func reduceMotionKeepsAlertingEventsAndDropsConfirmingOnes() {
        // Alerting events carry information the user cannot otherwise see, so
        // Reduce Motion does not silence them.
        for event in DesignHapticEvent.allCases {
            let allowed = event.isAllowed(reduceMotion: true, microphoneOpen: false)
            #expect(allowed == event.isAlerting, "\(event.rawValue)")
        }
    }

    @Test func alertingSetIsExactlyTheFourEventsThatNeedAttention() {
        let alerting = Set(DesignHapticEvent.allCases.filter(\.isAlerting))
        #expect(alerting == [.sendFailed, .permissionArrived, .questionArrived, .destructiveConfirmed])
    }

    @Test func theSilentModePolicyIsUnchanged() {
        // A canary on a policy constant, not a behavioural assertion: the
        // silent-mode rule is written policy (the ringer switch is not
        // consulted), and no platform guarantee is claimed for it. If a future
        // change makes silent mode suppress an event, this fails and §QT-HAPTIC
        // has to be updated with it.
        for event in DesignHapticEvent.allCases {
            #expect(!event.isAffectedBySilentMode, "\(event.rawValue)")
        }
    }

    @Test func everythingIsAllowedByDefault() {
        for event in DesignHapticEvent.allCases {
            #expect(event.isAllowed(reduceMotion: false, microphoneOpen: false), "\(event.rawValue)")
        }
    }

    // MARK: - Announcement ledger

    @Test func theLedgerAnnouncesEachIdOnlyOnce() {
        var ledger = DesignAnnouncementLedger()
        #expect(ledger.needsAnnouncement("a"))
        ledger.markAnnounced("a")
        #expect(!ledger.needsAnnouncement("a"))
        #expect(ledger.needsAnnouncement("b"))
    }

    @Test func theLedgerSurvivesTheRequestBeingRemovedFromTheLiveList() {
        // Drives the production path. The bug this guards: "already seen" was
        // derived from the live pending list, so answering a permission removed
        // it from that list and the next poll re-announced it.
        //
        // The isolated `UserDefaults` suite is the repo convention — the default
        // `.standard` leaks state across suites and between runs.
        let defaults = UserDefaults(suiteName: "DesignHapticsTests.\(UUID().uuidString)")!
        let state = AppState(apiClient: MockAPIClient(), sseClient: MockSSEClient(),
                             sshTunnelManager: SSHTunnelManager(defaults: defaults),
                             userDefaults: defaults, hostCredentialAccess: .noExternal)

        // Seed the live list, so the scenario is modelled rather than asserted:
        // `PendingPermission.id` is the composite "sessionID/permissionID"
        // (`AppState.swift:1868`), so that is the key the announcement uses.
        let permission = PendingPermission(sessionID: "s1", permissionID: "p1",
                                         permission: "write", patterns: [],
                                         allowAlways: false, tool: "write",
                                         description: "write")
        state.pendingPermissions = [permission]
        #expect(permission.id == "s1/p1")

        #expect(state.announcePermissionArrival(permission.id))
        #expect(!state.announcePermissionArrival(permission.id))

        // Answering removes the request from the live list. The ledger is
        // deliberately independent of it, so the request is not re-announced.
        state.pendingPermissions = []
        #expect(!state.announcePermissionArrival(permission.id))

        // A different request is still announced.
        #expect(state.announcePermissionArrival("s1/p2"))
        #expect(state.announceQuestionArrival("q-1"))
        #expect(!state.announceQuestionArrival("q-1"))
    }

    @Test func theLedgerIsBounded() {
        var ledger = DesignAnnouncementLedger(limit: 4)
        for index in 0..<10 { ledger.markAnnounced("id-\(index)") }
        // The oldest ids are evicted, so the ledger cannot grow without bound.
        #expect(!ledger.needsAnnouncement("id-9"))   // newest is still remembered
        #expect(ledger.needsAnnouncement("id-0"))    // oldest was evicted
    }
}
