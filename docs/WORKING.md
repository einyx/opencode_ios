# OpenCode iOS Client — Working Document

> Progress, issues, and decision log from the implementation work

## Current Status

### Superpolished app experience — initiative kickoff (plan confirmed, Phase 0 pending)

- [x] The user asked for the app experience to be "superpolished". A four-lens dev-team session (PM / Architect / Developer / QA) ran against the working tree and produced three candidate backlogs, which converged on a single shape: **a checkable rubric and an executable enforcement layer first, then a conformance-driven sweep, then one vertical slice.** No persona was willing to write polish code before the definition of done existed.
- [x] The planner re-measured the tree and corrected three premises from the brief: **"87 TODO/placeholder markers" is actually 0** (the hits were legitimate `TextField(placeholder:)` API usage and `L10n` key names — the real seams are the raw colour literals, the ad-hoc opacities, the hardcoded spacings, a second blue in `QuestionCardView`, a red error block `design.md:63` forbids, and the `.font(.system(size: 1))` accessibility-probe hacks — all counted live by `gen_audit.py`); **the token layer itself violates the mandated 22/16/13/12 scale** (`DesignTokens.swift:121` display=20pt, `:127` body=17pt, `:133` meta=12pt, `:136` micro=11pt, plus a fifth step at `:124`), so "migrate to tokens" alone is insufficient; and **"a foundation pass with no visual diff" is impossible** — with non-conformant tokens, any honest type fix repaints every screen, so Phase 3b becomes *the* single isolated app-wide visual diff instead.
- [x] **Decisions taken (2026-10-25):**
  - **TENSION A → A1.** `docs/design.md` (Quiet Tech) is the authority; current violations are bugs. No new accent color, no gradient, no v3 spec. Phase 3b is a single reviewable app-wide diff.
  - **Sub-tension D → D1.** The scale is implemented with `Font.custom(..., size:, relativeTo:)` so nominal sizes are exact *and* Dynamic Type still scales. **A physical-device Dynamic Type spike at `accessibility3` is an entry condition for Phase 3b**, not a follow-up. D2 (fixed sizes + waiver) and D3 (re-spec to semantic fonts) are rejected.
  - **First vertical slice → the chat message stream** (`MessageRowView`, `ToolPartView`, `FileCardView`, `PermissionCardView`, `QuestionCardView`, `PatchPartView`, `TodoListInlineView`, `TaskNotificationCardView`), explicitly excluding the composer, the voice rail, and `ChatTabView+VoiceInput.swift` — because PRs #215/#216 are still awaiting on-device acceptance for exactly that surface.
  - **Watch scope → deferred.** `OpenCodeWatch/WatchAmbientApp.swift` is out of v1 with a visible `DEFERRED` rubric row and its reason, not silent coverage. No Phase 7.5 unless the watch is promoted out of Experimental.
- [x] The plan is recorded in full at `docs/features/polish/plan.md` (the tracker path the plan itself prescribes for Phase 0). Estimate: **≈5.5–7.5 weeks** for the full initiative, **≈1.5 weeks** if it stops after the rubric + lint harness.
- [ ] **Phase 0 has not started.** It is blocked on the rubric and the audit table, neither of which exists yet. Phase 0 changes documentation only — no `.swift` file — so it cannot collide with the open PRs and does not re-trigger on-device acceptance.
- [ ] The rubric needs a named owner after Phase 0. A rubric with no owner decays into a document nobody enforces.
- [x] **Phase 0 is complete** — the definition of done now exists, and it is measured. Five sub-tasks, all documentation-only: **zero `.swift` file changed**, so nothing here can collide with the open PRs or re-trigger on-device acceptance.
  - **P0-1 / PRY-5** — every `##` section of `docs/design.md` now carries a stable clause ID (`QT-PRINCIPLE`, `QT-PALETTE`, `QT-TYPE`, `QT-CARD`, `QT-MESSAGE`, `QT-COMPOSER`, `QT-MOTION`, `QT-LAYOUT`, `QT-EMPTY`, `QT-NONGOAL`, `QT-BOUNDARY`, `QT-LANDING`, `QT-MOCKUP`, `QT-RETRO`, `QT-SPEAKER`, `QT-FILECARD`, `QT-TOOLTILE`, `QT-TILEGRID`, `QT-TOOLBOUND`) plus a new `QT-INDEX` clause index. Headings only; no prose changed.
  - **P0-2 / PRY-6** — `docs/features/polish/rubric.md`: **102 checkable rows** across 11 families (COLOR 19, TYPE 13, CARD 12, MESSAGE 7, COMPOSER 10, MOTION 10, HAPTIC 9, STATE 7, ERROR 5, A11Y 7, PREVIEW 3). Each row carries an ID, the rule, its source clause (`QT-*` / `REPO` / `INIT`), a machine-checkable predicate, its enforcement mechanism, and its scope (including the `ios-only` / `android-shared` parity split). Includes the per-surface acceptance list (P0-5 / PRY-9).
  - **P0-3 / PRY-7** — `docs/features/polish/audit.md`: the measured baseline, **one row per rubric ID, 1:1 verified**. Result at the time of the Phase 0 audit: **35 PASS, 9 PARTIAL, 14 REVIEW, 44 FAIL**; after the merge re-baselining it is **43 PASS, 8 PARTIAL, 14 REVIEW, 37 FAIL**. Labelled non-gating on purpose — a static table cannot prevent regressions, which is what Phase 1's lint is for.
  - **P0-4 / PRY-8** — the ranked backlog is in `docs/features/polish/plan.md`, ordered by user-visible impact ÷ review cost.
- [x] **Three findings the audit surfaced that the plan had not seen.**
  1. **The "OpenCode" reply title is deliberately absent.** `design.md` §QT-SPEAKER requires an `OpenCode` text title on every AI reply, but `MessageRowView.swift:687` reads `// No "OpenCode" speaker title — the user's blue left-bar vs the`. The code and the written spec contradict each other. This is a **decision**, not a bug — see the Open Questions below. `POL-TYPE-11`.
  2. **The action-card stripe widths are inconsistent.** `PermissionCardView.swift:22` is 3 pt (correct), `QuestionCardView.swift:43` is 4 pt, and the user-message stripe at `MessageRowView.swift:617-619` is 4 pt where §QT-MESSAGE says 3 pt. `POL-CARD-03`, `POL-MESSAGE-01`.
  3. **There is no `bg.primary` token at all.** `DesignColors.Neutral` defines only the surface and composer colours, and no view sets an explicit chat background, so the app inherits the system background instead of the spec's `#0B0C0E`. `POL-COLOR-01`.
- [x] **Two corrections to the plan's own measurements, made against the current tree.** The plan claimed `DisclosureGroup` appears once; it appears **twice** (`ToolPartView.swift:90` *and* `TaskNotificationCardView.swift:29`), so PRY-25's acceptance criterion was widened. And the plan's audit scope was `Views/`, which misses `ContentView.swift` at the app root — 2 of the 7 accessibility-probe sites live there. `POL-COLOR-08` was re-counted against the whole target.
- [x] **The measured baseline is stronger than the plan assumed.** 35 of 102 rows already PASS: the corner radii are exactly right (6/12/16), there are **zero** gradients, the file-card classifier routes exactly the four specified tools, the half-width tile grid works, the composer slot mechanics are correct, and the session-indicator accessibility work is done and tested. The gaps are concentrated in type scale, motion, haptics, and token discipline — not spread across the app.
- [x] **R1 — the haptic matrix — is implemented** (`PRY-26`, `PRY-27`). This was the top-ranked item in the polish backlog and the only high-ranked one with **no visual dependency**, so it was pulled out of phase order deliberately: it touches no pixels, so the Phase 3 type-scale work cannot invalidate it.
  - New `Utils/DesignHaptics.swift`: `DesignHapticEvent` (8 named events), `DesignHapticSignature` (9 signatures, 8 in use, one spare so a ninth event cannot force a collision), `DesignAnnouncementLedger`, and the policy as a pure, testable function.
  - The policy, now written into `docs/design.md` as a new **§QT-HAPTIC** clause so the spec and the code cannot drift apart again: **alerting** events (send failed, permission arrived, question arrived, destructive confirmed) survive Reduce Motion because their information is not otherwise available; **confirming** events (message sent, selection changed, recording started/stopped) do not. **Nothing fires while the microphone is open** — a haptic is a mechanical event an open capture can pick up — and there is no blanket exception: the recording events pass the capture state as it is *before* their own capture opens and *after* it closes. **Silent mode does not suppress haptics** — a written policy, not a platform guarantee. **A request is announced once**, tracked in a ledger separate from the live pending lists.
  - 11 firing sites covering all 8 events, reached through 13 call paths: `Views/Chat/ChatTabView.swift` (send success, send failure), `AppState.swift` (`announcePermissionArrival` / `announceQuestionArrival`), `AppState+SSE.swift` (permission asked, question asked), `AppState+Permissions.swift` (both poll paths), `Views/SessionListView.swift` (selection change, destructive swipe-delete), `Views/Chat/ChatTabView+VoiceInput.swift` (recording start/stop).
- [x] **The review gate returned FAIL twice, and both rounds are recorded.** The plan makes an independent code review and an independent privacy review a hard gate for this phase. Both ran; both returned **FAIL**. Every finding was addressed rather than quietly dropped — the full table is in `docs/features/polish/plan.md` under "The review gate — two FAILs, both addressed". The two that mattered most:
  - **BLOCKER (code review): the file did not compile for visionOS.** `UIFeedbackGenerator` and its subclasses are `API_UNAVAILABLE(visionos)`, and the platform guard was `canImport(UIKit) && !os(watchOS)` — which is **true** on visionOS. The app target ships `xros` with a 26.0 deployment target, so the visionOS build was broken and the iOS-only test run never caught it. The guard is now `#if os(iOS)`, and **`xcodebuild … -destination 'generic/platform=visionOS Simulator'` → BUILD SUCCEEDED**.
  - **MAJOR (privacy review): the microphone guard was bypassed at 6 of 10 call sites.** The AppState-level sites (permission/question arrival) and the session-list sites passed no capture flag, and the Ambient/Car live-voice path holds the device microphone open **by design** while it answers permissions by voice — so a permission arriving during a hands-free session fired a haptic straight into an open capture. The guard is now unbypassable: `DesignHaptics.fire(_:microphoneOpen:)` has **no default** for the flag, so the compiler forces every call site to state the capture state, and all of them pass one authoritative `AppState.isMicrophoneCaptureActive` covering both the Ambient capture and the chat composer capture.
  - Also fixed from the reviews: `.recordingStarted` now fires **before** the microphone opens rather than inside an already-live capture; `.destructiveConfirmed` fires **after** the delete succeeds instead of on the gesture; answering a permission no longer re-announces it (the "already seen" check was derived from the live pending list that answering mutates — now a bounded `DesignAnnouncementLedger`); the silent-mode policy is written down and asserted; `POL-HAPTIC-01…07` no longer claim `test` enforcement they do not have (the lint that will enforce them is PRY-10 and does not exist yet); the value enums are explicitly `nonisolated` per house style; the test suite is `@MainActor`; and the `isAllowed(reduceMotion:micphoneOpen:)` typo in the rubric and audit is corrected.
  - **Two deviations from the plan are recorded rather than left implicit:** the implementation uses the UIKit feedback generators instead of `sensoryFeedback` (a SwiftUI view modifier cannot host a cross-cutting policy in one place), and the plan's file-level do-not-touch on `ChatTabView+VoiceInput.swift` was overridden. **Consequence: PRs #215/#216 will need a rebase with hand-merged hunks in `ChatTabView+VoiceInput.swift`.** The ambient-voice behaviour itself is unchanged — the change only publishes a capture flag and fires a haptic.
  - **Re-verification is outstanding**, so PRY-27 stays **In Review**. No on-device verification was performed: haptics cannot be validated in the simulator.
- [x] **Round 2 of the review gate: the code review found two new MAJORs — both introduced by the round-1 fixes — and the privacy review passed with nits.** All findings recorded in `docs/features/polish/plan.md` under "The review gate — three rounds".
  - **MAJOR — the CarLive capture predicate could report "closed" while the engine was live.** The window between the engine opening and the capture being registered was covered only by `phase == .connecting`, and three paths leave that phase without stopping the engine: `cancelStartBeforeCapture()`, `failStart()` and `performShutdown`. Fixed with `captureStartPending`, set **before** the `audio.startCapture()` await and cleared only once the engine is confirmed closed — so the phase is no longer load-bearing for the invariant. The privacy review also found that `earlyCapture` is **always nil on iOS** (`startsBeforeConnection` is watchOS-only), so that clause of the predicate is dead code on every platform that actually ships haptics; the doc comment now says so.
  - **MAJOR — `chatSpeechCaptureActive` leaked on the realtime gate-rejection path.** The microphone never opened there, the flag stayed `true`, and every non-boundary haptic in the app was silently suppressed — "haptics stopped working" with no other signal. The flag and `isStartingRecording` are now cleared before that `return`.
  - Also fixed: `.recordingStarted` is now paired with `.recordingStopped` on all three failure paths; the silent-mode wording is a **policy** statement with no unsourced platform claim ("the generators emit no audio component" was not defensible for `UINotificationFeedbackGenerator`); the rubric row's enforcement is `test, review` accordingly; the ledger regression test now drives `AppState.announcePermissionArrival` with an isolated `UserDefaults` suite instead of a local list the ledger never sees; `QT-HAPTIC` was added to the clause index; and the stale counts ("14 tests" → 13, "7 call sites" → 11 firing sites, "52 files" → 53) were corrected.
  - The privacy re-review confirmed the payload surface is **empty** (no error text, path, token or request id can reach a haptic), that nothing is logged or persisted, that credentials and transport are untouched, and that the watch target and visionOS are inert and compiling.
- [x] **Round 3 of the review gate: no BLOCKER and no MAJOR code defect remained** — the findings were all on the documentation contract, and all are addressed:
  - **MINOR — `captureStartPending` was not scoped to a run.** `start()` can be re-entered on the same controller while an older `beginAudio` is still suspended, so the superseded run could clear the newer run's flag and the predicate would fall back to `phase == .connecting` — the exact dependency the fix had removed. The flag is now `captureStartPendingToken: UInt64?`, set to the run's token and cleared only by that token, plus a reset in `start()`.
  - **MINOR — the audit still claimed the platform guarantee the round-2 fix had removed**, and cited a test name that no longer existed. Both the `POL-HAPTIC-09` evidence and `docs/WORKING.md` now state the policy as written, and the rubric row's enforcement is `test, review`.
  - **MINOR — the `POL-HAPTIC-07` evidence contradicted itself** (claimed the pair is "never left open" while also noting the cleanup paths that leave it open). Reworded: the cancel and navigation paths release the microphone without pairing the haptic, deliberately.
  - **MINOR — a duplicate `QT-HAPTIC` row in the clause index** (the merge brought one in alongside mine). Merged into a single row with the combined wording.
  - **NIT — the ledger regression test never seeded the live list**, so `state.pendingPermissions = []` was a no-op. It now seeds a real `PendingPermission` (whose `id` is the composite `"sessionID/permissionID"`) and announces by that id.
  - **NIT — the `captureStartPending` doc comment misstated when the flag was cleared.** Corrected.
- [x] **The merge re-baselined the rubric, and the audit is now re-measured against the merged tree — mechanically, by a generator.** The previous claim that the audit had been re-measured was **false**: the merge rewrote six files the audit pointed into (`ChatTabView` 284 lines, `MessageRowView` 201, `ToolPartView` 341, `DesignTokens` 16, `SessionListView` 23, `ContentView` 3), which invalidated most of its `file:line` anchors — and three rows ended up citing evidence that no longer existed in the files. The fix is structural: `docs/features/polish/gen_audit.py` **measures the working tree at generation time** and every anchor in `audit.md` is produced by running the grep then, never copied by hand. A hand-maintained anchor is a lie the moment the file is edited, and a merge that rewrites a file silently invalidates every line number pointing into it.
  - The merge (`bab588b`, `f1dee7e`) brought a **new tool-card design** — the merged `N tool calls` group is gone; every non-file tool renders its own compact row, file cards keep the 2/3-column grid, and thinking/tool-call rows are full width — plus a new `QT-CHATSCREEN` clause. Five rubric rows encoded the *removed* design and were rewritten (`POL-CARD-08`, `POL-CARD-09`, `POL-MOTION-02`, and — because the merge also replaced the user message's accent stripe with a right-aligned bubble — `POL-MESSAGE-01` and `POL-MESSAGE-02`). `POL-MOTION-02` was re-measured as a FAIL: the tool row expands with `DesignAnimation.spring` (response 0.35 / damping 0.80) where §QT-MOTION specifies 0.32 / 0.82.
  - **Two things this left unresolved, both recorded in `docs/features/polish/plan.md`:** the merged spec is now internally inconsistent for tool rows (one bullet says tool expansion uses a custom spring, the next says the full-width process row expansion has no animation — and every tool row is now a full-width process row), and **`QT-CHATSCREEN` has no rubric rows at all**, so the rubric is complete against the spec as of `48fd2b3` but not against the merged spec.
- [x] **The merge also broke the visionOS build, independently of this work.** `7a8847d chore: v2` added `Utils/GlassSurface.swift`, which uses SwiftUI's `Glass` behind `if #available(iOS 26.0, *)`. That check is *true* on visionOS 26, but `Glass` is `API_UNAVAILABLE(visionos)`, so the symbol does not compile there. The **iOS** build succeeds; the visionOS target does not. Tracked as **PRY-44**. This is the same class of defect the haptic work hit — a platform guard that looks right but is wrong for one shipping destination.
- [x] **Verification after the round-3 fixes, on the merged tree.** `xcodebuild build -destination 'generic/platform=iOS Simulator'` → **BUILD SUCCEEDED** · `DesignHapticsTests` **13/13** · full `./scripts/test_unit.sh` → **1083 tests / 110 suites passed**, exit 0, xcresult parsed/Passed. The **visionOS** build fails on the merged tree for the unrelated `GlassSurface.swift` reason recorded as PRY-44; the haptic platform guard itself is correct and was verified independently.
- [x] **The two UI-test failures are pre-existing, confirmed against a clean tree.** The pre-haptic tree at `08402c6`, built and run on the same iOS 18.4 runtime, fails **both** at the **same lines** (`PreviewMigrationUITests.swift:56`, `QuestionWebPreviewRecoveryUITests.swift:20`), so neither is attributable to the haptic work. `CarModeUITests.testExperimentalCarModeToggleControlsTab` failed in the full suite but passed in isolation — flaky. Tracked as **PRY-42** and **PRY-43**.
- [x] **Verification after the fix round.**
  - `xcodebuild build -destination 'generic/platform=visionOS Simulator'` → **BUILD SUCCEEDED**. This is the destination the original platform guard broke, and the one no earlier run in this initiative had exercised.
  - `OPENCODE_TEST_ONLY=OpenCodeClientTests/DesignHapticsTests ./scripts/test_unit.sh` → **13/13 passed**.
  - Full `./scripts/test_unit.sh` → **1083 tests / 110 suites passed**, exit 0, xcresult parsed/Passed (from the 1070/109 baseline: 13 new tests in 1 new suite). Evidence `.occlient/test-runs/unit-20261025T084135Z-ATUdIM` (re-run after the second fix round: 1083/110, exit 0).
  - Two earlier runs are recorded as **not** passes: one failed on `theLedgerIsBounded()` — an inverted assertion in the new test, not a product defect (the ledger correctly evicted the oldest ids) — and one was killed during result collection (exit 143) after its tests had already passed, because two `xcodebuild` invocations overlapped on the shared simulator. Both were re-run; neither is counted as a pass.
- [x] **The 36 initiative issues were created in Linear** (project `OpenCode App for Ios`, team `PRY`, identifiers `PRY-5` … `PRY-40`; all labelled `Improvement`; Phase 0 in `Todo`, Phases 1–8 in `Backlog`). The creation manifest with the full title/dependency/acceptance mapping is `docs/features/polish/linear-backlog.md`. The OAuth MCP path was abandoned in favour of a Linear personal API key against `api.linear.app/graphql`, because Linear's MCP consent screen requires an interactive Linear login that cannot be automated.
- [x] **PR-collision blocker cleared.** The in-flight host-profile change landed in commit `fe3ec83 feat(hosts): start without a host and let the last host be removed`. Phase 7's session-list and host-profile rollouts are unblocked; Phase 2 still excludes `HostProfilesView.swift` as a sequencing choice rather than a conflict. `PRY-15` and `PRY-36` were updated in Linear to match. **PRs #215/#216 (ambient voice) remain the one open collision**, and Phase 7 step 5 (composer / voice rail) is still sequenced behind their on-device acceptance.

### OpenCode V2 server support + `opencode pair` QR onboarding

- [x] Root cause found: the app only spoke V1 routes, and a V2 server answers every V1 path with the packaged SPA shell (`200 text/html`), so the health probe could not decode and **the app could not connect to any V2 server at all**. `/api/info` is the V2 marker (`/api/health` is 404).
- [x] Generation detection implemented against upstream `v2.1.3` (measured from `/openapi.json`, 121 paths): `/global/health` counts as V1 only when it is 200 JSON, otherwise `/api/info` decides. A 401/403 is an authentication failure and never falls through to the other probe.
- [x] New `ServerGeneration`, `V2Mapper`, `V2EventTranslator`, `PairingLink`, `PairingClient`. `HostProfile.apiGeneration` stores the detected generation; changing the address clears it.
- [x] V2 routes implemented: session CRUD, messages, prompt (text + files), interrupt, active status, permissions and forms (**queried per session**, V1 lists them globally), provider/model/agent, fs list/read/find, vcs status, diff, fork, revert/stage, project/location.
- [x] V2 SSE frames are translated into the V1 shapes, so the event handlers and the MessageStore are untouched: `session.text.*` → `message.part.*`, `form.*` → `question.*`, `session.execution.failed` → `session.error`. `session.created/renamed/metadata.updated` carry no session body, so the client reads the session back.
- [x] `opencode pair` onboarding: parses the printed link and the QR payload (`{"code","urls"}`), redeems the code at `GET /auth/connect/:code` with `Accept: application/json`, and saves the session token as the host's Basic-auth password (username `opencode`). Added a camera scan (AVFoundation, iOS only) and a paste-a-link entry point.
- [x] The difference against the repo's existing spec was measured and written back into `docs/v2_server_compatibility.md`: **v2.1.3 does write the archive** (`PATCH /api/session/:id` with a top-level `{"archived": true}`; the V1 `time.archived` body is still ignored). The todo route is still missing, so `sessionTodos` keeps returning `[]`.
- [x] Evidence: `scripts/v2_contract_check.py` is 45/45 against the live v2.1.3 server. Every route and body shape the client sends was re-checked with curl (agent/model switch 204, interrupt 200, permission/form 200, fs `location[directory]` 200, patch title/archived 204, delete 204).
- [ ] The camera scan and the pairing flow are not verified on a device. The Car Mode live paths have V2 branches but were not run on a device.

### No default host on a fresh install

- [x] A fresh install used to seed a `Local OpenCode` host that pointed at the
  device's own loopback (`127.0.0.1:4096`). On a phone that address is never
  the right server, and the entry could not be removed: the app refused to
  delete the last host and an empty host list was never persisted, so it came
  back on the next launch.
- [x] A fresh install now starts with no host. The host is added with the host
  form or with an `opencode pair` link. The flat preferences of an older
  install are still migrated, but only when they hold a host the user
  configured (a custom server address, a username or a password).
- [x] The last host can be deleted, the empty list is persisted, and the
  credentials of the removed host are dropped, so the removal sticks.


### Watch Ambient (Experimental, PR #223)

- [x] Antigravity drafted the PRD/RFC and completed asynchronous design and implementation review; added a watchOS 11 app, a standalone phone-bridge client, tool deduplication and result sharding, and post-gateway-confirmation receipts.
- [x] Fixed the review items: commentary is offered in enqueue order and discarded without counting as success if it is not confirmed after 8 seconds; confirmation retries walk a snapshot; phone initialization reconnect has a 20-second deadline; the phone's own background audio hold branch is preserved.
- [x] Voice capture on a physical device, tool result relay, and one phone-side background initial connection succeeded; an explicit reconnect can also recover. With the phone in the foreground nearby or in the background, the connection can still drop during an answer or a second turn, and later reconnects do not eliminate the recurrence. Integrated as Experimental per the user's request.
- [x] Removed the shared 15-second monotonic clock budget; hardware cleanup keeps ownership until completion, preventing overlapping new captures. Watch sends have a 5-second deadline, with no auto-reconnect and no tool replay; the exact owner replaces the old lease, and old end/poll calls do not clear a new run. Fixed leftover busy/run state from the probe and reused the iOS icon.
- [x] After the final socket diagnostic increment, the full 1011 tests / 106 suites passed (exit 0, xcresult Passed); an additional 11 background-return tests and 11 transport tests passed in a targeted run, and the signed iPhone+Watch build plus the visionOS Simulator build passed. The independent close-and-reconnect review found no P0/P1.
- [ ] Multi-turn voice stability is unresolved: the known direct trigger is the client exiting after 5 seconds when audio frame sending has not completed, and the underlying cause is unconfirmed. The phone log still shows tool results and normal bridge responses, so it cannot be attributed to WatchConnectivity. Continuous background operation, lock-screen behavior, and SSH wake recovery are not yet accepted.
- [ ] The new socket/scenario/frame-count aggregate diagnostics contain no audio, body text, URLs, credentials, or error descriptions. The latest native log can be listed on the watch, but the developer file transfer channel is disconnected so it has not been read back; the watch is already kept awake and unlocked next to the phone, so export failure is no longer attributed to placement or lock screen. Build, test, and install do not constitute continuous voice acceptance.

This round's development evidence is kept in the ignored `.occlient/watch-ambient/`, preserving the existing permission metadata migration and other uncommitted work.

### Current round: Ambient background / headphones / screen-off voice (PR #216 published, not merged)

The final 48pt UI increment review on PR #215 was a PASS with no blockers; it was merged per user authorization with merge commit `f3b6485`. This round's branch `feat/ambient-background-voice` was created from the merged master. On 2026-10-17 the background build was deployed in place per user authorization, followed by a deployment of the shared audio session cleanup fix; the actual background capture and playback behavior still awaits the user's re-test, and a successful install cannot substitute for on-device behavior acceptance.

- [x] Reviewed Apple's playAndRecord / record background audio requirements and the route-disconnect / interruption behavior; referenced a standalone app's background implementation.
- [x] Official client adaptation: continues a call the user already started with capture running, keeping the necessary SSE/SSH; with no call in progress it disconnects normally in the background and reclaims the connection when the background period ends.
- [x] Keeps the cleanup for system interruptions, headphone/USB/AirPlay/CarAudio external route disconnects, explicit ends, and host/project/feature-toggle invalidation, without automatically reopening the microphone; updated the existing microphone usage description.
- [x] The independent Cursor code/privacy review documents were both read back with a PASS verdict. Fixed the low-severity items: capture the background epoch before any await, and a late-arriving network cleanup must still belong to the same epoch and must not disconnect the replacement connection.
- [x] The final 940 unit tests (99 suites) passed normally; the 5 Ambient UI tests passed before the final epoch-only fix, and the signed iPhone build was re-verified successfully after that fix, with the artifact's UIBackgroundModes containing only audio. No physical-device/headphone/screen-off testing was done.
- [x] The background voice commit `b2f79e6` was published as [PR #216](https://github.com/grapeot/opencode_ios_client/pull/216) and remains unmerged; it was not deployed at initial publication, and the later 2026-10-17 deployment records are below.
- [x] On 2026-10-17 fixed the idle or transcription-only Chat cleanup incorrectly calling the microphone discard, and the idle stale-TTS cleanup incorrectly releasing the shared audio session. Added regression coverage for the real cleanup helper entry point and the ownership check; did not exercise a real SwiftUI scenePhase or AVAudioSession device assertion, so it is not claimed that the single cause of the user-reported issue is proven. The fixed build was installed in place and launched.
- [x] As requested, Antigravity rewrote the whole prompt into a concise "project manager + voice assistant" form: locate the session first and read its history, then dispatch according to context; a progress inquiry only queries; when explicitly forwarding original text, keep the original text; keep the terms for the current entry point, the user, and another session separate, and do not automatically relay local corrections. The continue tool supplies no model parameters, and an anomalous model is checked against the actually visible metadata; "accepted" does not mean "done", and no proactive notification is promised for anything not implemented. 169 Unicode characters on the iPhone front end, 1325 on the back end; the core is shared with Android, with only the platform name substituted. The eight tools and their required parameters are unchanged.
- [x] The new prompt and the audio cleanup fix were verified together: 945 unit tests / 99 suites passed normally and the signed iPhone build passed. The copy for three interaction scenarios was reviewed; no paid-model behavior evaluation was done. The deployment, test, and prompt-alignment evidence exists only in the ignored artifact directory.
- [ ] The new PR stays unmerged, awaiting user testing and further instructions. Phone WDA automation stays disabled.

The research basis and scope are recorded in the ignored `.occlient/live-integration/background-voice-next-plan.md` and `background-voice-apple-evidence.md`; the implementation handover and the not-yet-accepted boundaries are appended later.

Previous checkpoint record: after the original implementation owner stopped, the research and source code were retained; the Cursor wide-scope takeover task timed out at 900 seconds with no final JSON, so it was not taken as evidence of no changes or of completion. Small tasks using a pre-created chat, stream-json, and writing a checkpoint first were then used to fix cross-file private access, with exit 0, a final success/is_error=false, and a matching session. At that point the main thread's local 939 unit tests (99 suites) and the 5 Ambient UI tests all passed normally, the physical-device signed build succeeded with the artifact's `UIBackgroundModes=[audio]` verified, and the review was still running independently. The new background build was not deployed and phone automation was not enabled; these local results are not treated as headphone/screen-off field testing.

Final acceptance addendum: the epoch minimal-fix invocation still timed out, but the source code and the completed checkpoint were written to disk; the main thread read them back and, after passing 940 actual tests, accepted the source, without turning the CLI exit 124 into a success. The final code-review continuation finished writing the PASS document and the PR text, while the CLI wrap-up reported WritableIterable closed/exit1; the invocation remains recorded as failed, and the review artifacts together with the corresponding source/regression evidence were re-checked by the main thread. The privacy continuation exited 0 on the same session and closed two nits. Publication evidence: `background-voice-epoch-unit.log`, `background-voice-ui.log`, `background-voice-publish-device-build.log`, `cursor-background-code-review.md`, `cursor-background-privacy-review.md`, all in the ignored `.occlient/live-integration/`. Still no phone deployment, no WDA startup, and the new PR is not merged.

### PR #215 additional UI: microphone capsule input level (48pt deployed)

- [x] Kept the three-button layout; the 48pt microphone capsule fills from the bottom upward based on the real inputLevel, while the outer outline, bracket, and base stay fixed; 65ms rise, 320ms fall. The other two icons remain 28pt and the button height remains 72pt.
- [x] The Ambient Mode Tab replaces car.fill with a static waveform, reusing the existing selected style; the internal identifiers and settings keys are unchanged.
- [x] Muted keeps the slash and the selected background color and clears the fill immediately; the control is disabled when not connected, connecting, or ending; the details keep the exact raw RMS value. The UI uses a sqrt(raw / 0.25) mapping and does not rewrite the real input value.
- [x] For the initial level version, the full 917 unit tests (97 suites) and the 5 Ambient UI tests passed; at 40pt the targeted 10 level unit tests and the icon UI passed; at the final 48pt the 10 level unit tests were rerun and the physical-device signed build passed. Synthetic screenshots for low/medium/high/muted and dark mode were read back, with no clipping in the 40pt screenshots; after the 48pt size change the unrelated full test suite was not rerun.
- [x] The user-authorized review continues in the background and deployment does not wait for it to finish. The 48pt official client was installed in place and launched Ether normally; the evidence `microphone-meter-install.json` / `microphone-meter-launch.json` both report success. WDA stays disabled; the microphone is not opened automatically and nothing is merged.

The evidence is in `.occlient/live-integration/`: `microphone-meter-unit.log`, `microphone-meter-ui.log`, `microphone-meter-48-unit.log`, `microphone-meter-48-device-build.log`, and `microphone-meter-visual/`. The screenshots are synthetic data only and do not represent acceptance of the phone's actual audio capture. The code and verification notes are to be synced to the existing PR #215.

### PR #215 additional fix: crash on returning from background / Ending Voice wrap-up (deployed)

- [x] The two latest device crashes were both audio-queue SIGABRTs, pointing to calling player.play on a stopped engine after clearPlayback; the raw device artifacts are kept only in the ignored directory and are not committed.
- [x] The clear enqueue captures the capture/playback generation, only clearing buffers and stopping without restarting the player; only the schedule path with PCM present, the engine running, and the same generation plays, and a stale-generation cleanup does not touch the new player.
- [x] The close budget starts before any await and uses ContinuousClock; both sending close and closing the socket are bounded by the remaining budget and do not join a hanging send; repeated stops share one task, cancellation does not busy-wait, the normal usage grace is preserved, and OpenCode is not aborted.
- [x] The user-authorized local metadata log lives at CarLiveLifecycle/events.jsonl in Application Support, uses a fixed field/string allowlist, and contains no body text, audio, credentials, or URLs; it is written on the utility queue and trimmed to a 128KiB target under normal I/O, without claiming a hard cap for pending writes or failure scenarios.
- [x] The local 907 unit tests (96 suites) and the physical-device signed build passed; the incremental code/privacy reviews were both PASS. The unchanged UI suite was not rerun this round, and unit tests are not equated with on-device reproduction.
- [x] The fix commit `a404059` was updated into PR #215 and installed in place, launching Ether normally; `background-return-install.json` / `background-return-launch.json` both report success. WDA control is not restored and nothing is merged; the minimize/restore behavior of the fixed build awaits the user's manual acceptance.

The existing evidence and records are in `.occlient/live-integration/`: `background-return/metadata.md`, `background-return-unit-3.log`, `background-return-device-build.log`, `background-return-code-review.md`, `background-return-privacy-review.md`. The WDA session was closed and shut down, the owned runner exited, and the service is no longer reachable; only local development continues. The real minimize/restore behavior still awaits the user's verification on the fixed build.

### PR #215 additional fix: keep voice across pages in the foreground (updated and deployed)

- [x] Switching between Chat / Files / Settings and other pages inside the app does not end Ambient Live; on return the same session and subtitles are reused.
- [x] Removed the reset-voice-session entry in the top right and the per-sentence mode menu in the top left; the official entry keeps only Live Voice; the legacy mode preference no longer affects routing, and LegacyCarModeView was deleted.
- [x] The connection task is owned by AppState, with a UUID + epoch protecting the old connection's tail so it does not cancel the new task; explicit end, backgrounding, host/project switching, and turning the feature off still clean up, and the HTTP token is retired first.
- [x] The full 893 unit tests (95 suites), the 5 Ambient UI tests, and the 5 entry/compatibility UI tests passed, with 1 iPad-only test skipped; all runners and result bundles were accepted normally. The incremental code/privacy reviews were both PASS, and the physical-device signed build succeeded.
- [x] The fix commit `a5c63de` was updated into PR #215; the official client was installed in place and launched Ether normally; `foreground-install.json` and `foreground-launch.json` both report success. The PR stays unmerged, awaiting the user's test confirmation.

The evidence is in `.occlient/live-integration/`: `foreground-unit-3.log`, `foreground-live-ui.log`, `foreground-entry-ui.log`, `foreground-device-build.log`, plus `foreground-code-review.md` / `foreground-privacy-review.md`. An earlier full-suite hang was traced to test tokens polluting the shared Keychain; Builder token access now goes through the injected credentials interface, and `.noExternal` no longer reads or writes the real Keychain, while the default Keychain storage key on a normal device is unchanged. The synthetic screenshot `foreground-ui-ready.png` was read back; the plus sign at its top right is only the fixture's result-update control, not a new-session button in the production entry.

The scope is still foreground voice; this round did not authorize adding background or screen-off continuous recording.

### Ambient Mode wrap-up for this round (PR published, awaiting user on-device acceptance)

- [x] Ambient Mode visible naming, large icons in one row, an explicit selected state for Mute, an instant Stop Playback, and a red End Voice; the localized screen-reader labels are preserved.
- [x] The playback volume slider reuses the system MPVolumeView, with no new audio amplification path. The simulator only validates the real container layout and does not pretend hardware volume is adjustable.
- [x] Reviewed the existing logs and improved interleaved subtitles and playback interruption: no historical voice event log was obtained; subtitles are aggregated independently per role, segments are split only when the audio gap exceeds 2 seconds, and a missing timestamp or delivery delay does not fragment the text; suppression of local playback still awaits acceptance by a human listener.
- [x] The eight tools include archive_job / unarchive_job: the server-side subtree is discovered, archiving goes descendants first and root last, restoring goes root first and descendants last; a cancelled archive writes 0, each item is read back, partial failures are not reported as a fully successful tree, and the task is neither aborted nor rebuilt.
- [x] The independent subagent code review and privacy review both ended as PASS; findings such as token reuse, HTTP retirement delay, TLS downgrade, and collapsed screen-reader body text were fixed.
- [x] The final 886 unit tests (94 suites) and the 4 Ambient UI tests passed normally, and the wrapper / xcodebuild / result bundle were all accepted; the physical-device signed build succeeded and the synthetic UI screenshot was read back. The ordinary build and test problems were fixed and the failure records retained.
- [x] The official client was installed in place and launched Ether normally; the install and launch records both report success, and the microphone was not opened automatically nor was paid voice started.

The user's latest confirmation is to wrap up as-is: do not add background or screen-off continuous calling to the official client; only stop in the background and keep the temporary inactive state. Submitting and publishing a new PR and deploying Ether are allowed; no merge, awaiting the user's on-device testing and explicit confirmation.

The first actual query confirmed the current branch has no PR, and the user was informed first; the user then explicitly authorized publishing a new PR. The feature commit `f79df5d` was published as [PR #215](https://github.com/grapeot/opencode_ios_client/pull/215), with status OPEN and unmerged; GitHub reports MERGEABLE / CLEAN. Awaiting the user's on-device testing and explicit confirmation.

Final evidence: `.occlient/live-integration/ambient-release-unit.log`, `ambient-release-ui-2.log`, `ambient-release-device-build.log`; the review records are `final-code-review.md` and `final-privacy-review.md`, all in the same ignored directory. The icon screenshot is `ambient-release-ui.png`. Non-blocking follow-up: when some child nodes fail to write, the root archived metadata in the partial may still carry the discovery snapshot; it returns ok=false and will not report a fully successful tree archive. The tool's actual voice and the system volume slider are for the user to accept on a physical device.

- **Last updated**: 2026-10-16
- **Baseline**: `4a9b11e`; this round's branch `feat/car-mode-hosted-live`.
- **Build/Test**: The final 886 unit tests, 94 suites, and the 4 Ambient UI tests passed normally; the code/privacy reviews were both PASS; the physical-device signed build succeeded. The first-round 856-test run and the legacy-mode UI records are retained below.
- **Phase**: This round's as-is build was published as PR #215 and deployed in place; the evidence `.occlient/live-integration/ambient-release-install.json` and `ambient-release-launch.json` both report success. It stays unmerged, awaiting the user's confirmation.

### 2026-10-16 — Hosted Live Car Mode first-round integration record

| Item | Current record |
|---|---|
| Platform contract | AI Builder Space PR #65 has been merged; local master `5ce8b64`, with `docs/speech_live_websocket.md` as the source of truth |
| Authentication | Reuse the existing Builder token; the OpenCode host credentials stay on the phone; no OpenAI key is introduced |
| Client scope | Add the Live controller / transport / audio and the tool bridge inside the only shipped app tree; wire it into the existing Car Tab |
| Tool scope | query_jobs, get_session_messages, start_job, continue_job, stop_job, answer_pending |
| Compatibility boundary | Keep the explicit legacy per-sentence mode along with its navigation, Health permission, and callback chain; a Live failure does not switch or replay automatically |
| Lifecycle | Switching host/project, backgrounding, and a new conversation invalidate old voice ownership; closing the voice does not abort background tasks |
| Interface | Bidirectional subtitles, in-conversation tool arguments/results, automatic scroll-to-bottom, collapsible connection and cost details |
| This round's verification | The final 856 unit tests / 94 suites passed normally, evidence `.occlient/live-integration/full-unit-release-2.log`; 3 Live UI tests Passed, 4 legacy Car UI tests Passed and 1 skipped, and both UI runners exited normally |
| Repository boundary | Keep the existing README modifications and untracked artifacts; nothing was committed or pushed this round; Ether was installed in place per the authorization |

After a static read-back and an independent review, these were fixed: stale tool results being written across generations, an old start stopping a new capture, a server-initiated close not stopping the capture, audio send failures being silently ignored, reentrancy on the send queue actor, a playback segment going idle too early, a configuration change carrying over the old audio format, long history exceeding the 64KiB function result limit, and a transport retire mistakenly closing the new generation. Subtitles and tools share the same incrementing sequence, and after a tool is interleaved, same-role subtitles open a new line. Platform portal costs are replaced per request_id and are listed separately from the local token estimate.

An earlier 851-test run showed transport request bodyStream test errors and timeouts and is not counted as a pass; after the fix it did pass 851 tests normally, and the final timeline version passed 853 tests. The first UI round timed out during AX initialization and ran no cases; after restarting this repo's simulator the second round executed three cases, the scroll-to-bottom case passed, and the two failures are retained in `.occlient/live-integration/live-ui-2.log` and are not recorded as a UI pass. The independent prototype's background voice and new-conversation changes were verified, committed, and installed in their own repo, and are not mixed in with official client device verification.

Final UI: the tool row and details button went from about 20pt to at least 44pt, and the cost details have a capped height and are scrollable. All three Live UI tests passed, evidence `.occlient/live-integration/live-ui-3.log`; the legacy mode, toggles, the Health local-permission sheet, and the legacy structured-reply UI passed on regression, evidence `.occlient/live-integration/legacy-ui.log`. The synthetic fixture screenshot `.occlient/live-integration/final-live-fixture.png` was read back with no occluded controls and no user data; it does not represent real full-duplex voice verification. A newly started empty history clears both subtitles and tool rows, while a permission denial or missing token keeps the old screen; the related new tests bring the final unit test count to 856.

Ether deployment: `.occlient/live-integration/device-build.log` is BUILD SUCCEEDED. Both the first install attempt and one bounded retry returned CoreDevice 4016, with `installedApplications` at 0, and the app was not launched. A device list showing connected does not mean a power assertion / trusted remote service can be obtained. The evidence is `device-install.json`, `device-install-retry.json`, and `device-apps.json`, all in the same ignored artifact directory. The user must unlock the device and restore the connection before installation can continue; it cannot be claimed that the official client has been deployed.

Deployment follow-up: the user explained that a system update was in progress, and after the reboot authorized installation again. `device-install-after-update.json` returned success with installedApplications at 1. The launch command timed out after waiting 30 seconds, and the subsequent `device-processes-after-update.json` query succeeded, confirming the OpenCodeClient process is running. This confirms the in-place install and that the app is running; the launch command's timeout record is not rewritten as a normal exit. The microphone has not been opened automatically and paid Live has not been invoked; the real voice experience awaits the user's acceptance.

### 2026-10-16 — Preview close and source validation wrap-up

Added three-column navigation simplification: removed the duplicate layout entry next to the Sessions gear, kept only the entry to the left of the chat model button in the three-column layout, and hid the system Chat / Files / Settings in the rightmost chat column; Focus, narrow windows, and iPhone restore the system navigation, while the chat remains the original TabView child instance. The layout choice became a same-icon button plus a confirmationDialog. The final 807 unit tests, 3 iPad navigation UI tests (plus 1 phone-only test skipped), and 1 iPhone UI test passed normally, and the main thread checked the result bundle and the Regular / Focus screenshots. The final navigation code compiles for visionOS Simulator; the visionOS archive of the previous preview code succeeded, and it is not mixed in as the final navigation archive. A new round of merge-scope code/privacy review is running in the background; per the latest authorization a PR was submitted and deployed to two devices, with the merge deferred until the user's acceptance.

Follow-up after PR #213 was merged: after `Task.yield` the sheet dismiss only clears the capture sequence number and does not erase new pending requests; the layout test button is limited to `DEBUG`; when the Files navigation stack is already empty `ignoreNextShrink` is not set, so the next back navigation is not swallowed. The external file link uses `ExternalFileOpenOwner` to store a host snapshot of the loaded document together with the chat-bound session (nil for Files), validated at stage / adopt / layout. When the same file moves from Files to Chat only the session is rebound, and the body is not refetched. WK is rebuilt by document identity, and late callbacks still validate the original owner; pending events are observed by sequence number, so the same path in a different workspace is not missed.

Final verification: the 807 unit tests (89 suites), 2 PreviewMigration UI tests, and 1 same-file source-rebinding UI test all exited 0 normally with Passed result bundles; the Xcode 27.1 generic visionOS Release unsigned archive succeeded. The rebinding regression keeps the body load count at 1, and asserts through the rendered-page bridge and the production handler that the link's pending owner is session-b, without claiming that an actual tap on a web link was verified. The earlier failures came from the fixture's current session not matching and from the probe reset, and the failure records are retained. The independent code/privacy review has no remaining must-fix items. The user subsequently asked for the three-column navigation simplification to be added; after that a PR was submitted and deployed in place to iPad and iPhone, kept unmerged and awaiting the user's acceptance.

### 2026-10-16 — visionOS archive input accessory bar compatibility fix

Fixed the six compile errors in build 135 caused by `ChatComposerTextView` calling `leadingBarButtonGroups` / `trailingBarButtonGroups`, which are unavailable on visionOS. The accessory bar's state, save, clear, and restore are confined to `#if os(iOS)`, with empty implementations on other platforms; the cross-platform `inputView`, focus handling, and Chinese input handling are preserved, and the iOS execution order is unchanged.

The local Xcode 27.1 visionOS Release unsigned archive succeeded, with the artifact being `xros` / `xros27.0` and device family `[7]`; the iOS `EffectiveLayoutTests` 22 tests passed, and the wrapper and result bundle both passed normally. The local result validates compilation and archiving; it does not mean cloud signing or upload succeeded.

### 2026-10-16 — Paste appearance and keyboard-free cursor feedback

Per the feedback, the paste key became a blue icon with the large solid background removed: the native `UIPasteControl` keeps a 44pt tap area, its background blends into the voice bar, and both light and dark modes were checked via screenshots. The system `configuration` can only be configured at build time, so a theme change only rebuilds the paste control and does not modify the returned immutable configuration.

Voice-first text supports tapping to place the cursor without popping up the soft keyboard; only the explicit keyboard button summons the system keyboard; when focused, paste inserts at the selection, and when unfocused it appends at the end. The input view is refreshed only when the input mode truly changes, and a session / host switch releases focus with `focusResetEpoch` to avoid inconsistent cursor and paste state. The issues from the independent code / privacy review have been fixed and closed.

Verification: 794 unit tests (89 groups) and six iPhone UI tests passed (one iPad-only test skipped), and the new iPad cursor and paste single test passed, all exiting normally with passing result bundles. The UIKit selection offset of 1 verifies `a+sentinel+b`; the UI test matches against the actual selection and does not describe it as proof of tapping in the middle of the text. Both paired physical devices were installed and launched in place, and PR #211 stays unmerged.

### 2026-10-16 — Focus layout and voice-first input

Implemented a device-local automatic / focus layout, defaulting to automatic; the large-screen focus mode keeps the single-content chat and file preview with the input area preserved, and the same round measures the three columns with `GeometryReader` while keeping a single chat instance. Voice-first is off by default; once enabled the draft text is selectable but the keyboard does not pop up automatically, and an explicit keyboard plus the native `UIPasteControl` plain-text paste are provided; paste and keyboard share the voice bar with the microphone, shortening the waveform and saving a row, while the microphone and send positions are unchanged. Async writes are attributed to the source host / session, and on send failure the original text, the newly added text, and the ID-deduplicated attachments are merged. The real issues from the independent code / privacy review have been fixed and re-reviewed. See the design in [focus_voice_input/design.md](features/focus_voice_input/design.md).

The final source passed 790 unit tests in 89 groups under Xcode 27.0 / iOS 18.4, with five iPhone 16 UI tests passing and one iPad-only test skipped; both wrappers, xcodebuild, and the result bundles passed normally. Under Xcode 27.1 / iOS 18.4, the iPad mini focus preview automatic→focus→automatic and portrait→landscape→portrait single tests passed with a normal runner exit, and three screenshots were read back. On Duo 27.1 the single test for tapping the draft and using the actual system paste also produced a passing result with a normal exit.

Under Xcode 27.1 some whole-group runs timed out during result collection; the failure evidence is retained and not counted as a pass. The Duo inner-screen opening/closing is not yet verified, and `XCUIDevice` rotation did not change the Duo window, so full readiness is not claimed. The signed build plus in-place install and launch are done for the paired iPhone; the microphone, cross-app paste, and grip experience are still for the user to accept on a physical device. The PR stays unmerged.

### 2026-10-14 — Parent-row blue reminder confirmed per source version

When P's children C/D are unread, opening P and switching away no longer redisplays the same batch of blue reminders; C/D content stays unread. The implementation touches `AppState.swift`, `AppState+Sessions.swift`, and `Stores/SessionReadStateStore.swift`: each row stores a per-source confirmation for a positive updated value, and a snapshot is captured and committed synchronously only when `selectSession` starts and the row really shows blue with a trustworthy state. A confirmation affects only that row and does not stop propagation to higher ancestors; after C=100 and D=200 are confirmed, C=101 still raises the reminder again. New descendant versions that arrive during current are not confirmed on exit.

`lastViewedAt`/`failedAt` and the source-unread predicates are preserved; opening a parent is not understood as having read its children. The optional dictionary stays compatible with old JSON, is isolated per device-local host profile, is not cleared on paging removal, and a confirmed deletion clears the row and its source references. This round only fixes the aggregate reminder and still inherits the clock limitation of the source's `updated > lastViewedAt` and the limitation that identical updated values cannot distinguish content changes; self-version migration, message revision, and server protocol changes were not implemented. The effective contract is in the [design](features/session_row_indicator/design.md#content-read-state-and-parent-row-reminder-acknowledgment).

The two test files are `SessionIndicatorTests.swift` and `SessionReadStateStoreTests.swift`. A targeted run passed 43 tests, evidence `.occlient/test-runs/unit-20261014T045654Z-MrJ8zA/`; a subsequent full run passed 763 tests in 87 suites, evidence `.occlient/test-runs/unit-20261014T045728Z-IuLjlH/`. Both runners and xcodebuild exited 0, with the xcresult parsed/Passed. Coverage includes the original issue, unread children, independent ancestors, a read source clearing the ancestor contribution, out-of-order sibling new tokens, supplementary loads and paging, the parent's own update, an update during current not being swallowed on exit, non-blue states, old JSON, host isolation, and deletion references.

The main thread independently reran the 43 targeted tests, and xcodebuild, the wrapper, and the result bundle acceptance were all 0; evidence `.occlient/test-runs/unit-20261014T045918Z-6I7UDt/`. The independent code/privacy review found no HIGH/MEDIUM blockers, and the device build passed (`.occlient/parent-unread-device-build.log`). The UI runner was not run this round and Android was not changed; per the user's authorization the merge happened first and iPad was deployed afterwards. The earlier runner work is retained below.

### 2026-10-14 — Test runner live logs and failure-closure acceptance

Applied the P1 draft from the independent review to the two runners and `lib_test_observability.sh`. The original `lib_simulator.sh` is byte-identical, and neither the app source nor the XCTest cases change. The existing UUID/DerivedData/ONLY/REBUILD/launch-skip rules are kept, log filtering is removed, and a full live tee, stage timings, separation of raw codes from final acceptance, per-round independent logs, and explicit result bundles are added. The new parameters and the exit 0/65/73/74 boundaries are detailed in [tests.md](tests.md#daily-runner-logs-result-evidence-and-exit-codes). The full stdout is for local development only; ignored does not protect the public console.

`scripts/tests/test_runner_observability.sh` runs independently from the repo with no workspace-private paths; 35 mock scenarios and 8 real Git-boundary scenarios in temporary repos all passed, covering raw-code preservation, failure closure of the result evidence for both entry points, live logs, timeout/interruption, and output-root protection. The final regression evidence is the system temporary directory `occlient-runner-tests-MEDWvp`, which is not committed.

The real acceptance ran only once, with `OPENCODE_TEST_ONLY=OpenCodeClientTests/SessionIndicatorTests`, explicitly naming the released iPhone 16 / iOS 18.4 UUID, reusing `.occlient/DerivedData`, pinning Xcode 27.0 / 27A266a, and a 180-second per-stage deadline. Preflight 1s, build 19s, test 9s, xcresult query 0s, 29s in total; each stage's command/tee/wrapper was 0 and 36/36 unit tests passed. The first final acceptance was 65: the real summary field is `result`, while the isolated mock had previously assumed `testResult`. Only the parser field was fixed, an offline-verifiable parsing function was extracted, and a real-summary subset fixture with device identity, time, and path removed was added; the offline run was then repeated with 43/43.

The original run evidence `.occlient/test-runs/unit-20261014T045115Z-upLXrl/` (containing the full `invocation.txt`, logs, raw state, and xcresult) keeps its first-run state and is not rewritten as a success. The replay of the new parser against that JSON is stored in `.occlient/test-runs/schema-replay-eNXcbT/acceptance.tsv`: parsed / Passed, verification passed, acceptance 0. This is an offline acceptance over retained evidence, not a second real runner execution. No UI, full test suite, device deployment, or attachment A/B was run; the live server was not touched.

The main thread then independently ran the same 36-test suite with the corrected script, and all stages and the final acceptance were 0; preflight/build/test/result took 1/10/8/1 seconds, 20 seconds in total. The real evidence is in `.occlient/test-runs/unit-20261014T045436Z-lZEijV/`, stored separately from the first failure record. The independent code/privacy re-check passed with no remaining blockers; this verification did not change the UI attachment policy.

### 2026-10-14 — iOS composer restores a useful activity description

Actual user use showed that when other information was empty the composer was left with only the green light and no readable explanation. Only in the iOS composer, the current activity text is restored: for a trustworthy own execution the running turn / activity tracker text is reused first; when missing, "Processing / Agent working" is shown. When only descendants are executing, "Subagent is running" is shown without a count. Pending, failed, retry, and pending-sync states keep an explicit description, voice states are merged with duplicate fragments removed, and the decorative light is not read aloud again when the text already carries the meaning.

The presentation adds a trustworthy `ownIsActive` to prevent claiming its own stale activity because of a descendant's green light or an expired raw busy state. The list still uses the light plus the branch icon with a number, without restoring the redundant "Execution active / N descendants active". The original background task title navigation stays unchanged. The activity mapping keeps using the existing tracker and adds no tool guessing; unknown tools and a missing message window may only produce a generic fallback, and continuous progress is not guaranteed.

Verification: running the targeted 36/36 via `./scripts/test_unit.sh`, then one full run of 751/751 (87 suites); the main thread's independent full rerun and the device build also passed, and the iPad/iPhone in-place install and launch were completed. Four new tests cover the specific activity, the generic fallback, descendants-only, stale rejection, explicit-state priority, and voice deduplication. The existing UI test selectors were changed to state text to avoid depending on the decorative light that is no longer repeatedly exposed to screen readers; the UI runner was not executed this time. Logs: `tmp/composer_activity/targeted-unit.log`, `full-unit.log`, `device-build.log`.

### 2026-10-14 — Independent review M1–M3 and final presentation convergence

M1: the state source scope is stored per SSE `event.directory`, already-loaded metadata, or the snapshot directory. An unknown active session only blocks blue when it is in the same scope and fresh, and stale busy state across projects no longer pollutes globally. A successful full snapshot covers the loaded IDs, the recorded unknown IDs, and the returned IDs of the current scope; missing items can converge to idle, and per-item revisions preserve SSE that arrives after the request without reloading the whole tree.

M2: on disconnect or a new connection the epoch increments the pending revision and releases the logical slots of both GET kinds, keeping the old pending display while waiting for a new snapshot. Old responses have no write eligibility and old defers cannot clear a new slot; a reconnect to the same host without a current session still syncs as usual. The tests cover the stale GET hang for permission and question respectively, a successful snapshot on a new reconnect, the old result arriving last, and slot ownership while another new request is still in flight.

M3: the visible foreground interface gains an independent lightweight 5-second expiry tick, separated from the network await; it sends no network requests and does not recompute per frame. Under normal main-thread scheduling, a 60-second confirmation becomes unknown on the next tick. The controllable-clock test advances to 61 seconds while the status GET stays hung, confirming that green is withdrawn while yellow/red and the pending-sync hint are kept, and that the network request count stays at 1.

The user's subsequent on-device decision: the light-mode green is unified with the Android value `#167C45`, the dark-mode `#4CBF82`, the iOS 6/8pt sizes, and the 2.6-second 0.40–1.0 range stay unchanged, and the low point is no longer darkened on its own to chase the old 3:1 target. In the list, a normal own execution shows only the light, and descendants are shown with the branch icon plus a number, with 0 not displayed, while screen readers still get the complete localized description. The composer gains no descendant count or duplicate-execution copy and keeps only the light, retry/pending-sync/necessary voice states; the original background task navigation keeps the target title and the tap action. The presentation reads structured fields and does not parse the summary string.

Verification: targeted M1–M3 31/31, then one full run of 746/746; after the final presentation changes added assertions, the targeted run was 32/32. The main thread's final full rerun was 747/747, and the device build plus iPad/iPhone in-place install and launch were completed. The logs are in `tmp/session_indicator_review_fixes/targeted-unit.log`, `full-unit.log`, `targeted-final.log`; the device build log is `device-build-final.log`. The UI runner was not rerun. The latest compact presentation and color scheme still await the user's on-device acceptance; the existing screenshots record the previous version. The issues from before the independent review and the old verification process are retained in the historical records below and are not the current rules.

### 2026-10-14 — Session single light and source-level confirmation (first-round historical record)

The currently effective contract is in the [mini PRD / RFC](features/session_row_indicator/design.md), and the visual sketch is synced to the [mockup](features/session_row_indicator/mockup.html). The historic three-state and independent-ancestor viewing rules have been replaced: first filter the red/blue sources by the source's own lastViewedAt, then roll up. Viewing a child only decrements that source, and viewing a parent does not confirm all descendants. Green takes priority over blue; when yellow or red covers green, a neutral execution summary is kept, and the current session is only exempted from blue.

The trustworthy state is supported by per-item confirmation times and SSE revisions. A snapshot request captures host/project/revision, passes directory explicitly, and only confirms missing items as idle on success within the same scope; an SSE with the same value also prevents an old snapshot from rolling back. On disconnect or after 60 seconds without confirmation the state is neither green nor blue, and yellow/red is kept along with a status-pending-sync display. The visible foreground interface shares a single in-flight state sync that is checked every 30 seconds, avoiding a permanent green after an idle is missed while the heartbeat looks healthy. A reconnect without a current session also syncs both kinds of pending; replies and SSE updates invalidate the old pending snapshot, and switching host discards old responses.

The breathing uses an independent green token and a Core Animation layer sharing a 2.6-second phase. Based on later on-device feedback, the opacity was widened from the initial 0.75–1.0 to **0.40–1.0**; with Reduce Motion it stays constant, and it stops offscreen/backgrounded. The state tree does not take part in per-frame animation. The light `#14733F` / dark `#4CBF82` values are kept and are not the success token. At the new amplitude, the 0.40 low point is about 1.76:1 / 2.21:1 on the light-gray/dark-gray selected backgrounds, and the peak is about 4.80:1 / 6.66:1; it is no longer claimed that the whole breathing cycle meets 3:1.

Further convergence: the light column was moved outside the full-text VStack and is vertically centered as a whole with the title, time, and running subtitle, with no absolute y offset; the original chevron, indentation, and 44pt hit area are preserved. iOS keeps 6/8pt and Android 5/6dp is recorded as a platform optical adaptation difference, with identical semantics and motion. The path where a clean SSE busy→idle automatically clears a committed `failedAt` was removed, so an old failure can only be confirmed through source-level viewing; a real APIClient non-2xx permission reply has been verified to throw and to retain pending/revision.

Scope limits: only the loaded parent chain is guaranteed; an active ID that cannot be attributed conservatively blocks blue. A failure missed entirely while offline cannot yet be recovered from the message history. A REST idle does not clear an old failure, and a proactive abort is not claimed to be a success. No device installation, service restart, or Git write operation was performed.

Verification result: the final full run of `./scripts/test_unit.sh` passed 742/742 (87 suites), including 28 tests for this feature. A targeted UI run once failed because the selector mistook a collapsible row for Other (it is actually a Button); after making it type-agnostic, the two serial light/dark list → composer → disconnected cases all passed their assertions. Two direct serial runs still hung in Xcode's result collection after the tests ended and were terminated by the time limit; there is no fully successful UI xcresult, so it cannot be reported as a runner pass. During the run a status-update warning on entering the existing Chat was also reported and is not yet located, so it is not claimed that the UI is warning-free.

Subsequent final verification: `./scripts/test_unit.sh` passed **743/743**. Only one more serial UI run with a hard 75-second limit: the light and dark cases both passed, and new assertions cover a light-center vs. full-text-block-center deviation of ≤1.5pt for five row types, the light being on the left of the text, and a 44×44pt chevron; the cases ended after about 26 seconds, the runner still did not collect results normally, it was terminated at the limit, and it was not rerun. The logs are `tmp/session_indicator_followup/unit-test.log` and `ui-test.log`; the new screenshots are `light-list.png` and `dark-list.png` in the same directory.

The Chat warning has been located: a short-lived diagnostic log bracketed the `hasMarkedText` binding assignment in the old `ChatComposerTextView.updateMarkedTextState` and captured the SwiftUI warning. The evidence is `tmp/session_indicator_followup/warning-events.log`; the temporary diagnostic code was removed and `ChatComposerTextView.swift` has no diff against HEAD. The new derived state getter does not write to an Observable, and the old bridging system is not modified. The "not yet located" in the paragraph above only reflects the first-round historical state.

The offline visual evidence is in `tmp/session_indicator_evidence/`: `light-list.png`, `dark-list.png`, `light-composer.png`, `dark-composer.png`, `reduce-motion-list.png`, `dark-disconnected.png`. Each was read back, confirming the mixed yellow/red/green/blue, the original chevron/indentation, the selected background, the composer light position, and that a disconnected state has neither green nor blue; there is no user session data. The Reduce Motion image uses a debug fixture to inject the same animation-disabled branch, and the system-settings path has a separate pure-policy test; no physical-device verification was done. The unit test output is retained in `unit-test.log` in the same directory, including the existing toolchain's isolation warnings and the occasional "command exit 0 but no further output" diagnostic, and the final test summary passed.

### 2026-10-08 — Background subagent still runs while the main session is idle, and the UI shows nothing

This section is a historical record; the independent-descendant presentation and state coloring have been superseded by the 2026-10-14 single-light contract.

- **Symptom**: after dispatching a task to a background subagent, the parent session's turn ends and its state becomes `idle`, while the subagent is `busy` in its own child session. The parent row in the session list shows Idle, and the chat page has no sign of anything in progress, making it look like nothing is running.
- **Cause**: the state is stored per session (runner) (`session/status.ts`: removed from the map when `idle`), so the parent runner ending means the parent is idle; a subagent has its own runner. On the client both sides store `sessionStatuses` as a global map, so the child's busy data is available, but the presentation only goes one session deep: the list's parent row reads only `statuses[parent.id]`, and child rows are collapsed by default and nested inside the collapsed section; the chat page's `isBusy` only looks at the current session.
- **Handling**: the client derives "conversation tree aggregate activity" with zero server changes. `descendantBusyCountsBySession` counts busy descendants upward along `parentID` (excluding self), copying the existing attention aggregation mechanism. When the parent row itself is not busy and has no attention, the list shows a heterogeneous secondary signal (branch icon + neutral color + "N subagents running", distinct from the brand blue of its own Running state), and lets such trees float to the top of the list (so they are discoverable even while collapsed). On the chat page, when the session itself is idle and has busy descendants, the status bar gains a separate "Subagents are running" section that shows the child session title for a single one and a count for multiple; tapping reuses `openReferencedSession` to jump to that child session, and it does not occupy the turn stopwatch or interrupt (those belong to the child session's own clock). The copy was drafted by AGY (gemini-3.8-flash-high).
- **Tests**: `SessionTreeTests` gained 6 cases: `descendantBusyCountsRollUpAndExcludeSelf` / `...HandleRetryAndIgnoreIdle` / `...IgnoreBusySelfWhenNoChildren` / `descendantBusySessionsSortAheadOfNewerSessions` / `sessionDescendantBusyCountsReadGlobalStatusMap` / `runningDescendantSessions...`. The Android side `SessionTreeTest` has the corresponding 6 (`./gradlew testDebugUnitTest` green).

### 2026-09-29 — After switching sessions and switching back, the chat area stays in the middle of the conversation

- **Symptom**: after switching to another session and back, the chat area does not scroll to the very bottom of the conversation but stops at some message in the middle, and it takes a long manual scroll down to get back to the latest message.
- **Cause**: the chat `ScrollView` is the same SwiftUI identity reused across sessions, so when `selectSession` replaces `messages` the underlying UIScrollView keeps the old session's `contentOffset` as the starting position for the new content (when the old session's content is long, the landing point is right in the middle of the conversation). The only path back to the bottom is the reactive chain "a `scrollAnchor` change + an `isNearBottom` gate + a 50ms delayed `scrollTo`": on switching, `onChange(currentSessionID)` only optimistically sets `isNearBottom` to true, hoping the next `scrollAnchor` change brings the scroll along. If the one `scrollTo` after the async load lands does not truly reach the bottom (a large amount of content laid out in the same transaction, with the offset clamped to the size known at that moment), the 75ms bottom-marker measurement immediately flips `isNearBottom` to false, after which all automatic scrolling is blocked by the `guard` with no retry, and the view stays pinned to the old offset.
- **Handling**: give each session's scroll view a fresh identity — add `.defaultScrollAnchor(.bottom)` + `.id(state.currentSessionID)` at the end of the `ScrollView` chain. When switching sessions the whole scroll view is rebuilt and the initial position is fixed at the bottom by the default anchor (iOS 17+, deployment target 17.0); the existing reactive follow mechanism (`isNearBottom` + `scrollAnchor`) is kept and continues to handle "follow while the user is at the bottom" during streaming updates. A positive side effect: the identity change triggers `onDisappear`, which cancels leftover pending scroll / visibility tasks on switching and eliminates the cross-session scroll task race.
- **Side effects**: ① when the content is shorter than the screen it is shown flush to the bottom — a short session (1–2 messages) changes from being shown at the top to flush at the bottom (standard chat behavior); the empty state (no session / no messages / busy placeholder) uses a viewport-height frame (`emptySessionStateView(viewportHeight:)`) to keep the original top-aligned look. ② Row-level `@State` (thinking card / tool calls expanded state) resets to collapsed after switching away and back.
- **Tests**: added the offline fixture `UITEST_SESSION_SCROLL_FIXTURE` (`SessionScrollFixture.swift`: a 40-turn long session plus a short session, with an `APIClientProtocol` stub providing the full `selectSession` data path without network access). `SessionScrollAnchorUITests` has 2 cases: the long session's first screen renders at the bottom (a frame assertion that the last user message is on screen and the first is off screen), and after switching to the short session and back to the long session it lands at the bottom (the regression case for this symptom). The existing `ToolCardsUITests` (which relies on the launch-time auto-scroll to the bottom) passed on regression.

### 2026-09-27 — Background subagent receipts rendered as TaskNotificationCard

- **Symptom**: the server injects the background task completion result as a synthetic user message whose body is `<task>` XML. The client did not decode `synthetic`, so this receipt was drawn as raw XML inside a blue user bubble.
- **Handling**: `Part.synthetic` is decoded with `decodeIfPresent`. `TaskNotificationParser` uses range matching to locate the outermost envelope so nested angle brackets are not mis-cut. A successfully parsed synthetic text is rendered as a card: status icon + localized status + the task title with the English prefix removed, and the result goes through the existing markdown path with a default expansion for ≤500 characters. When expanded, the subagent session can be opened by reusing `selectSession`, switching the project directory when the directories differ, and going through `sendError` when the session does not exist. Copying the receipt copies the result body. These messages do not show Edit-from-here.
- **Tests**: `TaskNotificationParserTests` / `TaskNotificationRenderingTests` 16 cases; `UITEST_TASK_NOTIFICATION_FIXTURE` covers expansion and navigation. For a long result the navigation button is off the first screen, so the UI test expands, scrolls up, and then taps.

### 2026-09-26 — Grok does not show the quota pill

- **Symptom**: when `xai/grok-*` is selected, the toolbar has no quota pill, while GPT / GLM / Ollama do.
- **Cause**: the pill's display condition is `primaryQuotaKey != nil`. The mapping only covers `openai` → `codex/5h`, `zai-coding-plan` → `glm/5h`, and `ollama-cloud` → `ollama/5h`. `xai` falls through to the default, returns nil, and the whole button is not rendered. In the dashboard's `/api/v1/quotas` this window is `provider=grok` and `label=Weekly`.
- **Handling**: `xai` is mapped to `grok` / `Weekly`. When the preferred window is not in the snapshot, the window the provider actually has is used instead. It is fetched upon entering Chat, without waiting for a tap. When a number is available the percentage is shown; when there is no number yet only the window name is shown and no `--` is drawn. A successful fetch within an hour is brand blue, while older than an hour or a failed refresh is grey. The details page adds Grok to the provider name. The 60-second deduplication for non-forced refreshes is unchanged.

### 2026-09-21 — Releasing the left-handle drag in the model shortlist does not apply the new order

- **Symptom**: in Settings → Models, the `line.3.horizontal` handle on the left of each row can be lifted, but the order does not change after release.
- **Cause**: the sorting is attached to the `.onDrop` of the `List` row. A drag session internal to the same list never reaches `ShortlistDropDelegate`, so `dropEntered` does not run and `moveShortlist` is never called. The provider type (`public.utf8-plain-text`) and `UTType.plainText` are also inconsistent.
- **Handling**: `onDrag` / `onDrop` were removed. The left handle became a UIKit pan: during the drag only the preview moves and the data does not change; on release the target index is computed from the displacement / row height and `moveShortlist` is called once. Swipe-to-delete is preserved.
- **Tests**: `ShortlistReorderMath` covers the half-row threshold, out-of-bounds clamping, and the destination convention with `moveShortlist`. The on-device drag and drop awaits manual acceptance.

### 2026-09-21 — Delete the dead hardcoded default model list `modelPresets` from production code

- **Background**: since 2026-08-24 the chat picker reads the user-managed `modelShortlist` (persisted locally, `pickerModelPresets` = `modelShortlist.map(asPreset)`), and the settings catalog was changed to fetch live from the `/provider` registry (`catalogModelPresets`). The hardcoded default array `modelPresets` in `AppState.swift` now has zero references in production code and is only used by unit tests as a seed fixture.
- **Handling**: the `modelPresets` array was removed from `AppState.swift` (keeping the `selectedModelIndex` default and all live logic). The test seed was consolidated into the shared fixture `testSeedPresets` in `TestDoubles.swift` (byte-for-byte identical to the original array), and `SessionFlowTests.makeState` and `AIUsageQuotaTests` now use `addModelsToShortlist(testSeedPresets)`.
- **Unit tests**: the 3 obsolete cases testing the "default preset list" behavior (`defaultSelectionUsesGemini37Flash` / `defaultPresetsIncludeDeepSeekLocal` / `defaultPresetsExcludeRemovedGPTVariants`) were deleted; the 3 aging cases (legacy GLM / GPT / Kimi mappings) are kept with the assertions changed from `state.modelPresets[...]` to `state.pickerModelPresets[...]` (equivalent element by element after seeding). The leftover test name `grok46ShortName` → `grok47ShortName` in `ModelsTests` was also fixed (the case body has been 4.7 for a while).
- **Impact**: no runtime behavior change, purely dead code plus test cleanup. `xcodebuild test` must be run serially (shared DerivedData).

### 2026-09-21 — Grok 4.7 model preset upgrade

- xAI released Grok 4.7, handled by the 2026-08-14 4.5→4.6 upgrade precedent: the trailing `Grok 4.6` / `xai/grok-4.6` preset is upgraded to `Grok 4.7` / `grok-4.7` (the `AppState.swift` model list and `ModelPreset.suggestedShortName` are renamed in step, with no canonical legacy mapping added).
- The tests were updated in step: every `grok-4.6` / `Grok 4.6` in `ModelShortlistTests` / `ModelsTests` / `SessionFlowTests` was changed to 4.7, and a targeted `xcodebuild test` for the three suites passed (iOS Simulator).
- The preset order, count, and other model entries are unaffected.

### 2026-09-13 — Documentation archive placement: Markdown Web Preview sub-documents

- **Problem**: `.gitignore` (lines 67–70), the archive index in `docs/README.md`, main PRD §4.3.5, and main RFC §7.5 all point to `docs/archive/2026-06_markdown_web_preview_prd.md` / `_rfc.md`, but the two sub-documents were actually still at the old paths `docs/Markdown_Web_Preview_PRD.md` / `_RFC.md`. The old paths do not match the ignore rules, so they were neither committed to git nor ignored, and hung around the `docs/` root as untracked files for a long time. The 2026-08 round only did "merge into the main PRD/RFC + write the ignore rules + write the documentation note"; the file move was never executed, so `docs/archive/` in fact did not contain those two files.
- **Handling**: the two files were moved to the archive path specified by the docs, with zero changes to the body (the mtime is still 2026-06-14). After the move `git status` is clean and all the references above point to files that really exist.
- **Meaning**: the two files remain untracked + gitignored per the established policy and are **not distributed with the repository**. The canonical decision lives in main PRD §4.3.5 / main RFC §7.5, and the decision process is in the 2026-06-14 entry of this file.

### 2026-09-12 — LLM throughput display (per-message footnote + Context sheet)

- **Motivation**: to see the real generation rate while the LLM works ("y tokens generated in x seconds"). Measured on the live server (4096) to confirm: every assistant message (= one LLM step) already carries `time.created` / `time.completed` / `tokens`. It can be computed purely on the client with zero server changes. ~~The gap between adjacent steps is only 1–3ms, and the per-step duration follows the output token count rather than the tool count — showing that this window is clean LLM generation time (tool execution falls between steps and is not counted)~~ → **This judgement was disproven on 2026-09-13; see the correction section below**.
- **Definition**: the denominator is the step's wall-clock (`completed - created`, including prefill + generation + **tool execution**); the numerator is `output + reasoning` (the tokens the model actually emitted, excluding input/prefill and cache read/write). No number is produced when `completed` is nil (still generating), when the window is 0, or when the token count is 0.
- **Implementation**:
  - `Message.generatedTokens` / `Message.throughput` / `Message.throughputLabel` (`Models/Message.swift`): the core computation; the label is "rounded for ≥10, one decimal for <10".
  - Every assistant message footer (`MessageRowView`): ` | X t/s` is appended after `provider/model`; while generating only the model is shown (no completed timestamp).
  - A new Throughput section at the top of the Context sheet (`ContextUsageView`): the session-level average rate (total tokens / total LLM duration), the generated token count (output+reasoning), and the total generation time.
  - 5 new L10n keys (en/zh).
- **Tests**: 12 new unit tests — `MessageThroughputTests` with 10 (basic / with reasoning / nil while generating / nil for a zero window / nil with no tokens / nil with a missing tokens field / nil for a negative window / integer label / decimal label / nil label) plus `ContextUsageThroughputTests` with 2 (session aggregation excluding in-progress steps / nil when no step has completed) — all passed; the full unit test regression was 427/427 (signed build).
- **Review**: the GLM-5.3 subagent's first pass was approve-with-nits with no correctness issues; based on the review two things were converged: the throughput number formatting was extracted into a single `Message.throughputText` implementation (shared by the footer and the sheet to avoid drift), and the sheet's "Output tokens" label was changed to "Generated tokens" (because the definition is output+reasoning, avoiding confusion with the Output row in the Tokens section).
- **SSE extension: best-effort decoding (added 2026-09-12, converged to decoding-only on 2026-09-13)**:
  - Background: a single general throughput mixes prefill and decode together (the denominator `created→completed` includes prefill). The goal is to split out a pure generation rate.
  - Data source: the server **does not persist the first-token time** (`message-updater` only writes `created`/`completed`), so a pure decode rate cannot be computed for historical messages; however the live SSE stream has per-token `message.part.delta` (`field`/`messageID`, with no server timestamp) and `message.part.updated` (part creation/finalization, step-finish carrying `tokens.output`).
  - **Best-effort definition**: it only asks "was SSE observed". If observed, decoding is given; if not (browsing history / restart / a pure REST load), it is not, and the footer keeps only the general value.
  - **Clock**: all of it uses the client receive time (firstVisible = the first visible token arriving, lastVisible = the last visible token arriving), avoiding server/client clock skew (the SSH remote scenario). decoding = `tokens.output` / (lastVisible - firstVisible); the numerator counts only output, with prefill and reasoning falling before the window and thus excluded, and tool execution falling after the window and thus excluded. The step-finish arrival time does **not** take part in the window (it only arrives after the tool has run) and only provides `tokens.output`; when only one visible token is observed (a window width of 0) no number is produced, and nothing is fabricated.
  - Implementation: `MessageStore.StepTiming` (per assistant messageID, `firstVisibleAt`/`lastVisibleAt`/`outputTokens` plus `decode`/`decodeLabel`); `handleSSEEvent` gains a `message.part.delta` case, `message.updated` creates the step entry, and `message.part.updated` collects the delta and the step-finish; `stepTimings` is **not** cleared by `resetStreaming()` (that fires on every message update, including this step itself) and is instead cleared with a session-scoped clear (`clearCurrentSessionViewState` / `removeTimings(forSession:)`). The footer (`MessageRowView`): `provider/model | <general> t/s | <decode> t/s decoding`, where the last segment appears only when SSE was observed.
  - **TTFT removed (2026-09-13)**: the original design carried `TTFT: 3.2s` in the footer (firstVisible - stepStart). On a real device this almost never appeared (the window between the client seeing the assistant `message.updated` and the first token arriving is unreliable, and it does not affect the "real generation rate" the user wants), so under the "don't keep useless things" principle it was deleted: `StepTiming` drops `stepStart` / `ttft` / `ttftLabel`, the footer drops that segment, and the related unit tests were deleted as well. `recordStepStart` is kept, with its role changed to "mark that this step was observed from the beginning", and it is still a precondition for the decoding window.
  - Tests: three in SessionFlow (SSE stream capture: a reasoning delta does not enter the visible window, a tool-input delta establishes the window while step-finish does not move the window's right edge, non-current sessions are ignored) plus `StepTimingTests` (the decode computation and its label, and the nil boundaries for both window ends / a zero width / a missing token).
  - **Known boundaries**: decoding is only valid for the step whose stream was observed in the current app session; after a restart or for pure history it falls back to general only. To retroactively obtain pure decode from history, the server must be patched to add a first-token timestamp to assistant messages and persist it.
- **Known boundaries**: ~~tool duration is out of scope this time (the user explicitly is not interested); the live SSE carries tool timestamps, but the persisted history's V1 message list does not store the tool `time`, so history cannot retroactively give the tool duration~~ → **Correction on 2026-09-13: the tool part's `state.time` does exist in the persisted payload (all 20,000+ tool parts in the local DB have start/end), and it must be subtracted from the denominator; see the correction section below**.
- **Merge**: PR #165 (branch `feat/llm-throughput`).

#### 2026-09-13 correction: tool execution time is inside the step window and must be subtracted from the denominator

- **Trigger**: on a real device it turned out that "the LLM output a very large write tool call, but the throughput was especially low".
- **Conclusion: the numerator is fine; the tool call's tokens were always being counted.** `output` = the provider's output tokens − reasoning, and the JSON arguments the model generates for a tool call belong to the output tokens. Rechecked against the local OpenCode DB (`~/.local/share/opencode/opencode.db`): of 910 tool parts, 901 have a step `tokens.output` consistent with the tool input size (the remaining 9 are `shell`/synthetic paths whose output is always 0); the largest write-class sample pairs a 5426-character input with 2748 output tokens. So "tool tokens are not counted" was a misdiagnosis.
- **The real cause**: the denominator `created → completed` **includes the tool's execution time**. Both server paths do this: the legacy processor executes the tool inside the stream and writes `completed` only after the tool ends; the V2 runner awaits the tool fibers first and then emits `SessionEvent.Step.Ended`. Measured evidence: the bash tool of `msg_085d6384a001` ran 417,204ms with a step window of 419,309ms and 63 output tokens → showing 0.1 t/s; the write tool of `msg_dbd74d5d0001` ran 48,345ms with a step window of 56,157ms and 529 tokens → showing 9.4 t/s (subtracting the tool time it should be 67.7 t/s).
- **Fix (client, still zero server changes)**:
  - `PartStateBridge` parses `state.time.start/end`, and `Part.toolRunSeconds` / `MessageWithParts.toolRunSeconds` aggregate them; `Message.throughputExcludingToolSeconds` = `generatedTokens / (stepSeconds - toolRunSeconds)` (when the tool time is ≥ the window it falls back to the original window, never producing a negative denominator).
  - The general numbers in the footer and the Context sheet now both use the tool-subtracted definition; the sheet's session average likewise subtracts per step.
  - The right endpoint of the SSE decoding window changed from "the step-finish part arrives" to "the last visible delta arrives" (step-finish only arrives after the tool has run, so using it to close the window is equivalent to adding the tool time back into the decode); at the same time the tool-input delta counts as a visible token, so a step that "only outputs a tool call with no body" can also produce a decoding rate instead of only a general rate polluted by the tool time.
  - `StepTiming.firstTextAt` was renamed `firstVisibleAt`, and `lastVisibleAt` was added; the TTFT-related fields (`stepStart`/`ttft`/`ttftLabel`) were later removed, see the previous section.
- **Remaining boundaries**: the persisted definition still includes prefill (historical data cannot separate the first-token time), and only a step observed over SSE can give a pure decode rate; the Context sheet's session average covers only the currently loaded messages (history outside the pagination is not counted); when the tool time is missing (running, old payload) it falls back to the original window.
- **Tests**: `MessageThroughputTests` +3 (tool subtracted / fallback when the tool time exceeds the window / nil while running), new `MessageToolTimingTests` with 3 cases (state.time aggregation, 0 when the timing is missing, a running tool without an end is not counted), `ContextUsageThroughputTests` +1 (aggregation subtracting the tool), `StepTimingTests` +2 (the decode closes with lastVisibleAt, a tool-only step has a window), `AppStateFlowTests` +1 and one existing case rewritten (a tool-input delta establishes the window, step-finish does not move the window's right edge). **All 29 cases in the 5 focused suites passed** (Xcode 27 beta + iOS 27.0 simulator, `test-without-building`).
- **Test environment pitfall**: `/Applications/Xcode.app` (26.6) lacks the iOS platform component, so all iOS simulator destinations are unavailable; Xcode 27 beta can run, but `AIUsageQuotaTests.swift` is incompatible with beta's default isolation (an actor cannot conform to a protocol inferred as global-actor-isolated), so the file was temporarily moved out during the test run and restored afterwards, with its contents unchanged.

### 2026-09-10 — Swipe right from the left edge to close the iPhone file preview

- In compact-width Chat, the docked `ChatInlineFilePreview` opened by tapping a file tool call can be closed with the standard iOS back gesture in addition to the toolbar `xmark`: start from the physical left edge of the screen and drag right far enough.
- The geometry is shared with the session list open gesture via `EdgeSwipeGeometry` (32pt from the edge, ≥ 72pt horizontal, ≤ 56pt vertical drift), with the two entry points `FilePreviewEdgeSwipeBehavior` / `SessionListEdgeSwipeBehavior`; it is not enabled for the regular/iPad middle-column preview.
- The gesture strip is layered over the preview content area (it does not cover the navigation bar xmark or the bottom composer); the strip itself uses `.ignoresSafeArea(.container, edges: .horizontal)`, intending that in landscape the start is still the physical left edge rather than the content's left edge after the safe-area inset. Portrait has been confirmed on a physical device; landscape is not yet verified, and if it fails a flexible leading frame is added before ignoresSafeArea.
- The `WKWebView` of the Markdown Web Preview swallows the hit-testing of the SwiftUI `Color.clear` overlay, so the left-edge `DragGesture` never receives began. The close strip was changed to a UIKit `UIView` that grabs the left 32pt, and it logs `FilePreviewSwipe` (appear / touchBegan / began / changed / ended+decision / xmark). The close direction is **swipe right from the left edge**, and a left swipe records `swipedWrongDirection`.
- On-device log: `touchBegan x=7` was already within the 32pt strip, but `UIPanGestureRecognizer`'s `.began` fires only after the finger has already moved right to `startX=73`, and using that point for the left-edge test yields `startTooFarFromEdge`. The press coordinate is now used as the origin, with the displacement computed as the current point minus the press point.
- Cost: the leftmost ~32pt is reserved for the close gesture, so horizontal code scrolling / image panning inside that strip is unreachable; this is intentional.
- Tests: `FilePreviewEdgeSwipeBehaviorTests` (a valid right swipe, not from the edge, too much vertical drift, too short a horizontal drag, and a reverse-direction left swipe decision).

### 2026-09-07 — SSH key fail-closed (issue #161)

- **Background**: issue #161 reports that the device's Ed25519 key pair can be silently regenerated: a transient failure reading the private key from the Keychain (`errSecInteractionNotAllowed` while the device is locked) makes `ensureKeyPair()` fail open, burning the old identity and overwriting the public key cache, which invalidates the server's authorized_keys; aggravating factors include `KeychainHelper` not setting `kSecAttrAccessible` (defaulting to WhenUnlocked), save/load ignoring the OSStatus, and hot paths in the connection and view layers calling a function that generates keys.
- **Fix (separating read from create)**: a read-only `getKeyPair()` was added — it never generates, and first derives the public key from the private key to validate the cache's consistency (on a mismatch the cache is repaired from the private key), throwing the new error `SSHError.keyUnavailable` when the Keychain is temporarily unreadable and `.keyNotFound` when the private key genuinely does not exist; `ensureKeyPair()` was narrowed to guidance only, generating solely when the Keychain returns `errSecItemNotFound` (the item is truly missing), and throwing `.keyUnavailable` for other errors without touching the stored key; `rotateKey()` retains the right to generate (explicitly triggered by the user).
- **Call-site rewrite**: `connect()`'s `_ = try? ensureKeyPair()` became an explicit do/catch propagation, and on a key error it disconnects and enters `.error` (fail closed); on the view side `generateOrGetPublicKey()` was renamed `readPublicKey()` and now goes through `getKeyPair()` (the Settings onAppear prefetch, the public key sheet, and the three Copy Public Key spots), and a transient failure reuses the existing error UI to prompt unlocking the device.
- **Keychain hardening**: Keychain entries uniformly set `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (the private key and the password/token share the same write path; readable while locked after the first unlock, supporting background connections after a restart, and not migrating with iCloud Keychain); `KeychainHelper.save/load/delete` all propagate the OSStatus, and `loadData` returns nil only on `errSecItemNotFound` (distinguishing "does not exist" from "read failure"); `save` became update-then-add and writes the UserDefaults public key cache only after the private key write is verified.
- **Rotate hardening (added after review)**: `rotateKey()` no longer deletes before generating; instead it generates a new key and overwrites it in place with the update-then-add `savePrivateKey`, updating the public key cache only after the save succeeds — on a save failure the old identity stays unchanged; the error from the Settings Rotate callback now writes to `publicKeyLoadError` to tell the user instead of being silently swallowed.
- **Test isolation**: `SSHKeyManagerTests` is annotated `@Suite(.serialized)` (consistent with `HostProfileTests` in the same file), avoiding flakes from several tests concurrently modifying the shared Keychain/UserDefaults state.
- **Verification**: the build passed (xcodebuild build with a specified simulator destination); the targeted `SSHKeyManagerTests` run passed 7/7 (2 existing + 5 new: getKeyPair does not mint, bootstrap is idempotent, deriving repairs a stale cache, KeychainHelper update-in-place/delete, and the hasKeyPair lifecycle); of the full 451 tests, 443 passed / 4 failed / 4 were skipped, and all the failures are UI fixture tests (CarMode/AIUsageQuota/SpeechStrategies/ToolCards) that fail the same way when rerun on a clean baseline, i.e. pre-existing flakes in this environment unrelated to this change. Note: running Keychain-related tests on this machine requires removing `CODE_SIGNING_ALLOWED=NO` (an unsigned host app has no Keychain entitlement and reports -34018).

### 2026-08-24 — Local model shortlist (PR #149, related #99 / #144)

- The official picker's visibility persists on the desktop, and both `/provider` and `/config/providers` are the full catalog. iOS keeps the shortlist locally: in Settings → Models you search and add from the connected chat-capable catalog, swipe left to delete, drag the left handle to reorder, and tap a row to change the toolbar short name.
- The chat bar's Model & Agent renders only this list, in the same order. An empty list and "edit it in Settings" both jump to Settings with Models highlighted.
- Connected custom/local providers (such as `ollama`) appear in the catalog; releases no longer depend on hardcoded presets.
- The Add Models page is only responsible for bulk adding (Cancel / Add). Deletion goes back to swiping left on the shortlist.

### 2026-08-24 — Deterministic messageID + inline send-failure banner (supersedes #89, closes #81)

- **Background**: issue #81 reports that OpenCode 1.15 `prompt_async` fails silently with `SQLITE_CONSTRAINT_NOTNULL` because `messageID` is missing. Upstream has fixed it (`input.messageID ?? MessageID.ascending()`, and 1.18.16 was measured accepting the old payload), but two problems remain: reconciling the dual IDs of an optimistic message relies on text/timestamp heuristics; and an asynchronous failure (the turn crashing after the 204) leaves the UI waiting forever with no feedback.
- **cherry-pick PR #89 (guyq1997) with adaptations**: `promptAsync` carries `messageID` plus a `directory` query; `createSession` adds `directory`; `makeServerID(prefix:)` generates `msg_<uuid>`. Deviation from the original PR: `partID` was dropped — the client does not consume part ids, and the `part_` prefix does not match the current server's `PartID` schema (which requires `prt`).
- **Deterministic ID reconciliation**: the optimistic row directly uses the real `msg_` id sent to the server; `loadMessages` drops the text normalization / plugin-prefix hasSuffix / 60-second time window / `keepPending` busy gating (~34 lines) in favor of reconciling purely by ID members in `MessageStore.pendingOptimisticMessageIDs`; once the server persists, the pending entry converges automatically, and a failed row keeps its text for copying and resending.
- **Inline failure banner (no dialog)**: a synchronous failure (an HTTP throw) keeps the optimistic row plus a red inline banner, replacing the old `sendError` dialog path; an asynchronous failure (SSE `session.error`, which previously fell into `default: break` and was silently dropped) that hits the current session marks the pending row as failed and reconciles with `loadMessages`, taking the reason from error.name plus the first non-empty line (truncated to 300 characters). Assistant row-level errors still use the existing inline banner (`errorMessageForDisplay`), complementary and not duplicated.
- **End-to-end verification**: measured against a temporary local server on origin/dev — the persisted id of a payload with a deterministic messageID matches the client's; in the no-API-key scenario the server emits `session.error` (`ProviderAuthError`) and the wire shape matches the decoding.
- **Tests**: 8 new ones (ID dedup/retention, sending with a deterministic ID, the synchronous failure banner, and session.error hitting / other-session filtering / no pending row / undecodable fallback); the 3 tests from the heuristic era were rewritten with ID semantics; the rollback test now uses "keep the row + inline failure" semantics.

### 2026-08-14 — GLM 5.3 + Gemini 3.7 Flash + Grok 4.6 model preset upgrade

- At the top of the model list, `zai-coding-plan`'s GLM is upgraded from `GLM-5.2` / `glm-5.2` to `GLM-5.3` / `glm-5.3`. `models.dev` already lists `glm-5.3` for `zai-coding-plan`, so no server-side injection is needed.
- The `Ollama GLM 5.2` row for `ollama-cloud` stays unchanged, because the `ollama-cloud` upstream does not yet offer `glm-5.3`.
- `canonicalModelPresetID` newly maps both `zai-coding-plan/glm-5.2` and `zai-coding-plan/glm-5.3` to `zai-coding-plan/glm-5.3`, letting sessions that previously selected GLM-5.2 migrate smoothly to the new preset instead of falling back to the default. The existing `glm-5.1` / `glm-5-turbo` legacy mappings also point to `glm-5.3`.
- The same PR also upgraded the default model `Gemini 3.6 Flash` / `google/gemini-3.6-flash` to `Gemini 3.7 Flash` / `gemini-3.7-flash` (already listed on `models.dev`). Following the pattern of the previous 3.5 → 3.6 upgrade, Gemini gets no canonical legacy mapping, and the old saved `gemini-3.6-flash` value keeps the current selection under the default logic.
- The trailing `Grok 4.5` / `xai/grok-4.5` is upgraded to `Grok 4.6` / `grok-4.6` (already listed on `models.dev`). `ModelPreset.shortName`'s `Grok 4.5 -> Grok` is changed in step to `Grok 4.6 -> Grok`, with no canonical legacy mapping added.
- The `GPT-5.6 Sol Fast` preset (`openai/gpt-5.6-sol-fast`) was removed, aligning with the Android client. `canonicalModelPresetID` maps `openai/gpt-5.6-sol-fast` to `openai/gpt-5.6-sol`, so sessions that already selected that model migrate smoothly; the `GPT-F` branch of `ModelPreset.shortName` was deleted. The `gpt-5.6-sol-fast` used by the Car Mode internal protocol (`CarModeProtocol.model`) is unrelated to the selector and stays unchanged.

### 2026-07-31 — GPT Live Transcribe host integration

- New installations default to GPT Live Transcribe without overwriting a valid saved strategy. Chat now renders the Kit's accumulated GPT Live snapshots directly in the composer during recording; GPT Realtime remains finalize-only. The Kit dependency now uses exact release `0.4.0`.
- Settings now persists and displays the third `gptLiveTranscribe` strategy in a menu. Both GPT strategies use realtime transport and expose the custom prompt; existing valid saved values remain unchanged.
- Chat and Car snapshot strategy at Start and pass it into strategy-aware Kit sessions. Preserved retries route through the handle's originating strategy, while file retries keep their captured strategy.
- Realtime audio chunks now pass through one bounded ordered sender per capture; Stop/Cancel drains that worker before commit or preservation. Realtime finalization failures retain recoverable audio.
- Chat pending audio is keyed by its originating OpenCode session, and every start/finalization/retry callback is gated by attempt plus session ownership. A session switch now detaches an in-flight finalization without revoking ownership: success persists the completed transcript to the source session draft while leaving the destination composer unchanged, and failure preserves source-owned audio. The navigation snapshot is synchronous so it cannot overwrite a just-completed source transcript; background/explicit cancellation still aborts and preserves. Car uses a generation gate so New Session invalidates old permission, microphone, transcript, and request continuations without carrying old audio into the new session.
- Car retry state now distinguishes transcription retry from OpenCode request retry, so a transcription failure cannot resend the previous `carLastTranscript`.
- Validation: strict Swift 6 standalone runtime checks pass for source/destination draft routing, session-switch detach versus cancellation preservation, and ordered sender order/capacity/drain. Deterministic app tests cover switch-at-finalize completion and destination-draft isolation. The Xcode package reference now pins exact VoiceFlowKit `0.4.0`.

### 2026-07-31 — Markdown Web Preview native MathML

- Web Preview now bundles Temml 0.13.4 and converts `$...$` / `$$...$$` TeX to MathML inside markdown-it before DOMPurify. Parsing preserves escaped dollars, code spans/fences, and ordinary currency.
- DOMPurify no longer combines `ALLOWED_TAGS` with an overriding broad `USE_PROFILES`; the shell now uses one explicit HTML/SVG/MathML allowlist and sanitizes generated MathML in the same pass as the document.
- Headless verification covers inline/display math, `\\xrightarrow`, fractions, invalid TeX fallback, delimiter edge cases, and removal of undeclared profile-only tags. iOS fixtures add light/dark screenshot coverage for the arrow-heavy formula shape.

### 2026-07-30 — Pin VoiceFlowKit 0.3.0

- The SPM dependency changed from a bare revision to the exact SemVer `0.3.0` (with `Package.resolved` pointing at merge commit `71b9fe6`).
- The iPhone 16 simulator build passed; `SpeechRecognitionDefaultsTests` / `VoiceFlowKitIntegrationTests` / the chat speech tests passed.

### 2026-07-29 — Dual recording strategies: OpenAI Realtime / Grok Batch

- The VoiceFlowKit pin started at `4a04d562965fe041b552570759ef6e419ab3b2d6` and later became the exact `0.3.0`. Settings persists `OpenAI Realtime` / `Grok Batch`; the Grok mode hides the OpenAI-only prompt but keeps its value.
- Chat and Car snapshot the strategy at Start. OpenAI keeps the realtime session, PCM stream, heartbeat, and recovery; Grok only starts local AAC-LC M4A recording, creating no ticket, WebSocket, or heartbeat during recording, and uploads once after Stop.
- Chat preserved-audio and Car failed-state retry both save the strategy in effect when the recording was made; changing Settings after recording does not reinterpret the old file. Leaving the active recording page, going to the background, or cancelling finalization invalidates the in-flight Start/finalization/retry generation, preventing late permission/session/microphone or transcript callbacks from restoring a hidden recording or writing back an old result, and cleans up the temporary files and the realtime session.
- VoiceFlowKit simultaneously fixed the writer, buffer, temporary file, and audio session cleanup for AAC/WAV finalize errors; the 12 package tests passed.
- Verification: the iPhone 16 / iOS 18.4 build passed; 6 new targeted tests covering the strategy persistence/transport contract and the VoiceFlowKit integration passed; the isolated Tool Cards UI rerun passed. The voice-related tests in the full suite passed, but the existing `LayoutConstantsTests.splitViewFractions` exact `CGFloat` comparison failure was still reported; in the same round the Tool Cards fixture failed on the first run and passed on the isolated rerun.

### 2026-07-24 — Text selection across Markdown blocks in Chat

- The root cause was located in MarkdownUI's `BlockSequence`: one Markdown message is split into multiple SwiftUI block views; iOS's `.textSelection(.enabled)` only works within a single selectable view and cannot extend the selection across paragraphs, lists, and code blocks. Chat does not use a WKWebView, and this is not a streaming DOM diff problem.
- The existing MarkdownUI reading rendering is kept to avoid regressing workspace images, tables, code blocks, and links; the user/assistant message menus gain "Select Text" and "Copy Entire Message".
- `Edit from here` is shown only on a user message; `Fork from here` continues to support both user and assistant messages, allowing forking from any turn.
- "Select Text" uses a single read-only `UITextView` sheet that cleans Markdown inline markers line by line while preserving the original line breaks of paragraphs, lists, and code blocks, and then supports native iOS cross-line, cross-paragraph drag selection; "Copy Entire Message" copies the complete original text directly.
- A new test covers concatenating multiple text parts, ensuring that several text parts of one message are joined with blank lines and are no longer affected by Markdown block boundaries.
- Verification: the iPhone 16 / iOS 18.4 build passed; 7 targeted `MessageRenderingHeuristicTests` passed.

### 2026-07-19 — Health Quantification client capability

- The Car Mode action became a tolerant typed union, keeping Maps and adding `health_quantification.export_all`; an unknown future action no longer makes the whole structured speech fail to decode.
- The first call shows a local authorization sheet supporting allow once, always allow, and cancel; Settings can revoke the automatic Health export authorization.
- Before opening the Health App, OpenCode writes a 15-minute Pending entry; a valid callback atomically converges to a 6-hour Outbox. A duplicate, expired, or corrupt callback does not produce a second continuation.
- The callback is accepted locally first and does not depend on a server connection; the continuation uses the recorded Host, Car context, and session, plus a deterministic message ID and query-before-retry, and does not read the current Chat selection.
- The official product, the implementation, and the wire contract are maintained in `docs/features/client_capabilities/prd.md`, `docs/features/client_capabilities/rfc.md`, and `docs/features/client_capabilities/protocol.md` respectively; the canonical agent entry point is `skills/client_capabilities.md`.
- The verification covers the strict parser, the canonical handoff URL, the store lifecycle, allow-once, the original session continuation, callback stop semantics, and the permission fixture UI. The sequential build and the full test against the pinned iPhone simulator `302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8` passed; 352 Swift Testing tests and 37 UI tests passed, and 4 opt-in UI tests were skipped as expected.
- After the on-device E2E acceptance, two UX points were converged: the authorization page's three short buttons became an equal-width horizontal row, with English wrapping to at most two lines inside a button; and the callback continuation enters Car Mode's existing `waitingReply`, showing a red "Stop Response" primary button, and cancelling both aborts the session and deletes the corresponding Outbox so that a background submission does not appear to be a no-op in the foreground.

### 2026-07-15 — Session deep link and Agent search links

- Registered `opencode://session/<session_id>`, using a strict URI parser that rejects unknown hosts, queries, fragments, userinfo, ports, illegal IDs, and multi-level paths.
- Cold/warm URLs and Chat Markdown taps share the AppState router; after the connection is restored, the current Host's `GET /session/:id` validates it, and on success the project/session is switched while on failure the original context is preserved.
- Backgrounding and a Host switch invalidate the old resolve generation, avoiding a lost link before the SSH reconnect or an old Host's response polluting the new Host.
- Refreshing the session list keeps the currently verified session, avoiding a historical target being overwritten after falling outside the 100-item window; the Files tree reloads using the target project directory.
- Added parser/state tests, a Markdown tap fixture, and a cold pending fixture; at the same time the portrait precondition of the UI suites is pinned, eliminating the cross-test contamination caused by the leftover orientation from the launch tests.
- The product behavior and the technical contract have been merged into main PRD §4.2.7 and RFC §4.4 respectively. The workspace private semantic-search overlay specifies the candidate evidence and the `[Open in OpenCode](opencode://session/<id>)` output contract.

### 2026-07-15 — Car session active restore and documentation convergence

- Before sending each Car turn the persisted session is checked; if `time.archived > 0`, the client writes the legacy restore sentinel `-1` and continues using the original session. The behavior does not fork, does not duplicate history, and requires no archive-list server patch.
- iOS distinguishes Active / Archived by `archived > 0`, so a restored session reappears in the iOS Active list. The difference that OpenCode Web only accepts `archived === undefined` is not covered by this feature's guarantees.
- The Car Mode product requirements were merged into `OpenCode_iOS_Client_PRD.md`, and the technical contract plus verification evidence into `OpenCode_iOS_Client_RFC.md`; the standalone `car_mode_design.md` was deleted to avoid drift across three documents.

### 2026-07-14 — Car Mode implementation and server history fixes

- Settings gained an Experimental Features section that centrally holds the AI Usage Dashboard configuration and the Car Mode toggle. Car Mode is off by default; once enabled the iPhone tab order is Chat / Files / Car / Settings, and with it off the Car tab is not shown. The iPad (including the compact window) and Apple Vision Pro show neither Car Mode nor the toggle.
- The Car session is isolated by host UUID + workspace and does not reuse the regular Chat's `currentSessionID`; the session ID, the last processed assistant message ID, and the pending confirmation are persisted.
- Added a synchronous structured prompt API, fixed to `openai/gpt-5.6-sol-fast` + `build`; the client consumes only the schema-validated `assistant.structured`.
- Apple TTS explicitly uses `.playback` + `.spokenAudio`, and the recording audio session is closed before sending, fixing the issue where the UI showed the readout but the sound could remain on the receiver/Bluetooth HFP route.
- The client action allowlist contains only `open_navigation`, and iOS validates the typed destination/waypoints before constructing the Apple Maps URL.
- The regular Chat shows `assistant.structured.speech` when a structured assistant has no text part, and a new UI fixture verifies that the Car history is visible.
- Nested server commit `43a4a0e53` fixed the `info.format` wire schema of structured user messages; the targeted schema/opencode tests and the typecheck passed.
- On live 4096 it was verified that the complete structured history of the target Car session can be read; 14 messages and 3 structured assistants were all preserved.
- Verification: the pinned iPhone simulator `302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8` with `-parallel-testing-enabled NO`; 327 unit tests, three iPhone Car UI tests, one iPad hidden test, and the visionOS simulator build all passed. The iPad test also confirmed that neither the Car page nor the Settings toggle exists.
- On a physical device the TTS was confirmed to produce sound, and the live structured Car history is now readable. The Smart Home, mail, iMessage, and route-duration skills are still not productized nor have completed a real E2E.

### 2026-07-13 — Car Mode feasibility and design

- Completed the Car Mode feasibility design, converging the driving voice entry point into a standalone mode inside OpenCode iOS; the conclusions are now folded into the main PRD/RFC.
- The live OpenCode API was verified: `system + format(json_schema)` can return `assistant.structured`; a second turn in the same session can reuse the previous turn's destination; and a structured final can still be returned after a tool executes.
- A production blocker was found: after a structured user message persists `format`, the message list endpoint reports an `OutputFormatJsonSchema` BadRequest when validating the `info.format` output. The synchronous `/message` can be used for a UI/TTS spike, but the server schema must be fixed before history restore, Chat viewing, and asynchronous exactly-once handling.
- The live `skill` tool currently has no registered Smart Home, mail, iMessage, or map skills for the workspace; productization requires formally registering a Car allowlist or switching to typed tools, and the generic `read + bash` cannot be treated as a stable permission boundary.
- Product boundary: after switching to Maps or another app, continued background interaction is not promised, but the Car session ID isolated per host/workspace is preserved; after switching back, the same session continues to be appended to.

### 2026-06-18 — Image attachments Phase 1/2

- Per this round's decision the scope converges on the first two phases: sending photo library images + rendering historical image/file parts; no Files app, PDF/text attachments, or server-side upload.
- Protocol: `Part` gains `mime` / `filename` / `url` / `source`; `APIClient.promptAsync` supports mixed text/file parts, and images use the Web-isomorphic `data:image/jpeg;base64,...`.
- Composer: a `PhotosPicker` attachment button and a horizontal thumbnail strip were added; after picking, the image is converted to JPEG locally with a 2048px longest edge, quality 0.82, and a 5MB post-compression cap per image; on a send failure the text and attachments are restored.
- Optimistic UI: `appendOptimisticUserMessage` can generate text + file parts, so the user sees the image attachment immediately after sending.
- Rendering: `MessageRowView` has a display path for `type == "file"` on both user and assistant; an image part shows a thumbnail that can be tapped to open the `ImageView` zoom/pan, and a non-image shows a fallback file card.
- Tests: added `filePartDecoding`, `appendOptimisticUserMessageIncludesImageAttachmentPart`, and `sendMessagePassesImageAttachmentsToAPI`.
- Verification: `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'` passed.

### 2026-06-18 — Message revert / Edit from here MVP

- The goal converges on a minimal viable version: only `Edit from here` for user messages, with no restore dock, no `unrevert` UI, and no part-level revert.
- Data protocol: `Session` gains `revert` decoding; `APIClient` gains `POST /session/:id/revert`, handled as the `Session` returned by the current server.
- UI: the `⋯` menu of a user message gains `Edit from here`; it is disabled in a busy session to avoid a revert failing while the server is busy.
- State flow: clicking calls `AppState.editFromMessage`, and on success the original user text parts are written back into the composer draft, the returned session is upserted, and the messages / diff / file status are refreshed.
- Rendering semantics: `ChatTabView` uses `AppState.visibleMessages`, and when `currentSession.revert.messageID` exists it hides the history rows with `message.id >= revert.messageID`, staying consistent with the Web rewind view.
- Tests: added `sessionDecodingWithRevert`, `visibleMessagesHidesRowsAtAndAfterRevertMessageID`, `editFromMessageCallsRevertAndStoresDraft`, and `editFromMessageKeepsDraftUnchangedOnFailure`.
- Verification: `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'` passed.

### 2026-06-14 — Markdown Web Preview on-device acceptance and wrap-up

- **Phase 0/1/2 are all complete and shipped** (see the earlier Markdown Web Preview section); the full serial `xcodebuild test` passed (291 + 11 new = 302 passed, no regression).
- **The default preview mode changed to Web** (PRD §5.1 / RFC §8.2 updated in step).
- **The chip contrast issue exposed by on-device dark-mode acceptance**: the `<style>` card uses a hardcoded light background that washes out in dark mode; the shell now uses a saturated primary color for the dark semantic variables (`--ok-bg=#10b981` and the like, like GitHub's dark issue label); and the chip uses the compound selector `.vx-chip.ok` rather than the bare `.ok` to avoid being overridden by the card's `color:var(--fg)`.
- **Stale content left in the WebView when switching files**: the root cause is that when SwiftUI reuses the same `FileContentView` instance `.onAppear` only fires once; the fix is to actively reset the content and reload in `.onChange(of: filePath)` (`.id(filePath)` was tried, but the cost is rebuilding the whole view, which is not elegant and has been reverted).
- **New regression tests**: the `semantic_chips.md` fixture plus the `testSemanticChipsDarkVisible / Light` UI tests, whose sentinel text assertions guard the two real bugs "the dark chip washes out" and "the bare `.ok` is overridden".
- **The internal-writing skill was upgraded substantially**:
  - "Use theme variables + fallback for CSS colors" (replacing the earlier vague "theme-safe")
  - "Semantic classes must use compound selectors" (a specificity pitfall caught by dogfooding)
  - "**The real metric is the rate of new concept introduction, not word count**" (the fundamental framework for a low cognitive burden)
  - "Writing a status card like an encyclopedia entry" is listed as an anti-pattern, with clear boundaries between cards/tables/`<details>`
- **Document merge**: the final decision state of `Markdown_Web_Preview_PRD.md` / `Markdown_Web_Preview_RFC.md` was merged into main PRD §4.3.5 / main RFC §7.5 (in the form of visual tables + `<details>`, which is itself dogfooding). The two sub-documents stay on disk but `git rm --cached` removes them from tracking and they are added to `.gitignore`; the decision process lives in this WORKING.md (see the 2026-09-13 entry for when they were placed in the archive).

### 2026-06-20 — Ollama Cloud GLM 5.2 model preset

- In the model list, `Ollama Kimi K2.6` (`ollama-cloud/kimi-k2.6`) is replaced by `Ollama GLM 5.2` (`ollama-cloud/glm-5.2`). The OpenCode server's `ollama-cloud` provider registry already has the `glm-5.2` entry injected via the `INJECTIONS` of `scripts/regen_models_local.py` (see `opencode-official/skills/update_models.md`); the model key is `glm-5.2`.
- `ModelPreset.shortName` changed from `Ollama Kimi K2.6 -> Kimi` to `Ollama GLM 5.2 -> OGLM-5.2` (adding the O prefix and the version number to distinguish it from the shortName of the top `GLM-5.2` preset), keeping the narrow-screen model chip short.
- `canonicalModelPresetID` adds `ollama-cloud/kimi-k2.6 -> ollama-cloud/glm-5.2`, letting sessions that previously selected Kimi migrate smoothly to the new preset instead of falling back to the default.

### 2026-06-10 — Ollama Cloud Kimi model preset

- In the model list, `MiniMax M3` (`ollama-cloud/minimax-m3`) is replaced by `Ollama Kimi K2.6` (`ollama-cloud/kimi-k2.6`). The model key exposed by the OpenCode server's `ollama-cloud` provider registry is `kimi-k2.6`; passing the Ollama library tag `kimi-k2.6:cloud` directly makes `prompt_async` return 204 but produces no assistant message in the background.
- `ModelPreset.shortName` gains `Ollama Kimi K2.6 -> Kimi`, keeping the narrow-screen model chip short.

### 2026-06-08 — F3 voice rail composer

- The Chat composer converged from "a microphone attached inside the input field" into a `voice rail + text review field`: the voice rail carries the recording transport, the real waveform, the transcription wait, the stop-wait, and the preserved-audio retry; the text field carries transcription review, corrections, fallback typing, and the fixed send.
- The agent-running state is downgraded to a quiet status row near the composer, and `Interrupt agent` moves into the `⋯` menu so that a low-frequency destructive action does not steal the main voice-steer path.
- The waveform while recording uses the real mic level from `VoiceFlowMicrophone.audioLevel`; a new `VoiceFlowMicrophone` is rebuilt before each new recording, so that the audioLevel stream does not stop producing after the second recording.
- The transcription wait keeps an explicit exit, `Stop transcription wait`, which calls abort-preserving-audio; in the preserved-audio state the left icon button handles `Retry this segment` and the lightweight action on the right handles `Discard audio`, avoiding two retry entry points and giving the post-retry-failure state a clear exit.
- When the partial transcript of voice transcription or a preserved-audio retry is written into the text review field it scrolls to the end automatically, so the user can continuously see the latest transcribed text; ordinary manual input and draft restore do not force scrolling.
- Added `UITEST_F3_TRANSCRIBING_FIXTURE` / `UITEST_F3_RETRY_FIXTURE` with the corresponding UI tests, covering the two key states of transcribing + agent running and preserved-audio retry.

### 2026-06-08 — Chat history load-more diagnostics

- After comparing with Android, the iOS message part `files` decoding compatibility was fixed: old history may contain `files: ["path"]` or objects missing `additions/deletions`; Android already handled these, but iOS previously required complete objects, so enlarging the message limit could silently drop old records.
- `loadMessages` / `loadOlderMessagesForCurrentSession` added logs for the limit, the number of returned records, whether history grew, and fallback decoder dropped records, making it easier to reproduce the "pull-to-load finished but the history did not grow" problem.
- Added regression test coverage for the string form of `files`, and for applying a larger message window after load older expanded from 20 to 40.
- Further confirmed from on-device logs: the chat history limit had been expanded from 20 to 40/60, but the message requests were being cancelled; at the same time the bottom `onAppear` automatic pagination of the session list kept loading from 6500 to 8000 under archived-heavy data. The session list's automatic sentinel was changed to an explicit "Load more sessions" button, avoiding the collapsed archived area triggering endless pagination and preempting the chat history requests.
- The second round of logs confirmed that the automatic session pagination had stopped, but the SSE `session.updated` still repeatedly replaced the same busy session at high frequency, accompanied by the SwiftUI "Modifying state during view update" warning. `Session` / `SessionStatus` were made `Equatable`, skipping no-op upsert/status writes; `loadOlderMessagesForCurrentSession` puts the actual `loadMessages()` into an unstructured main-actor task, so that a `.refreshable` cancellation does not directly cancel the history message network request.
- The third round of on-device logs verified: after `requestedLimit=40/60` the responses returned `returned=40/60` respectively, and the number of history messages grew from 20 to 40/60. An additional regression test covers an identical `session.updated` payload not causing a session list change.

### 2026-05-30 — Speech abort/retry

- The VoiceFlowKit pin was updated to the merged revision `dbbe297ea52e3a3438d227a54001b23c138c47b7`.
- A helper button was added on the left of the Chat composer: while recording/transcribing it shows stop and calls `abortPreservingAudio()` to release the UI immediately; once the audio is preserved it shows retry and calls `transcribe(preservedAudio:)` to re-recognize the previous PCM segment.
- The `cancel()` semantics stay unchanged; only the explicit abort path preserves the audio; the send button is still gated by `isRecording/isTranscribing/isRetryingSpeech` to avoid concurrent writes into the input.

## Default Workflow Conventions

### The default meaning of "build with the latest code"

In this project, that phrase by default does **not** mean taking the latest remote code and building it in place.

The default meaning is:

1. Enter `adhoc_jobs/opencode_ios_client/opencode-official`
2. `fetch origin` to get the latest `origin/dev`
3. Rebase the current local integration branch onto the latest `origin/dev` while **preserving the current local commits**
4. Continue building, testing, and deploying the iOS client / server integration environment with the rebased server code

The goal of this convention is to fix one working meaning: **latest code = the latest upstream `origin/dev` + the current local patch stack**.

Here, "local commits" specifically means the commits that are **already committed** on the current branch but not yet integrated onto the latest `origin/dev`; it **does not include** the uncommitted working tree changes.

Only when the request explicitly says "no local commits, just build the pure upstream latest code" is the rebase skipped and the work done directly on a clean `origin/dev`.

### Why this convention

- The currently verifiable mainline of `opencode-official` is `dev` / `origin/dev`, not `master`
- Locally there is usually a set of patches that have not been upstreamed; building the pure upstream would lose those behavioral differences
- Rebasing before building surfaces conflicts between the upstream changes and the local patches earlier, instead of leaving the problem for later

### Execution boundaries

- This is an integration workflow that **preserves local commits**, not a "force reset to the remote"
- If the rebase conflicts or fails, the default is to pause and confirm how to proceed rather than continuing into the build/deploy phase
- If the work is only read-only research, an API comparison, or regression triage, this workflow is not triggered by default

### Success criteria

- The success criterion is not just "the build produced a binary" but also that the **execution path is correct**
- When OpenCode is started under `knowledge_working`, what runs must be the latest binary produced by this workflow, not an old binary left on disk
- For the current workflow, the closed-loop verification counts as complete only when the command below actually starts the binary obtained from the rebase + build:

```bash
OPENCODE_DB_PATH="$HOME/.local/share/opencode/opencode.db" \
OPENCODE_SERVER_PASSWORD="restart_Web@" \
/Users/grapeot/co/knowledge_working/adhoc_jobs/opencode_ios_client/opencode-official/packages/opencode/dist/opencode-darwin-arm64/bin/opencode web --hostname 0.0.0.0
```

- If that command still points at an old build artifact, or it cannot be proven to correspond to the new binary from this round's rebase, then this "build with the latest code" does not count as complete

### Runtime verification boundaries

- If the user is actively using OpenCode, especially when a server is already serving on port `4096`, **do not** kill, restart, or take over that live process in order to verify a new binary
- In that situation, the runtime verification steps that would interfere with existing use are skipped by default
- If runtime verification is still needed, use a separate temporary process / temporary port, and manage only the verification process you started yourself, without touching the user's existing `4096` process

## In Progress

None. Markdown Web Preview Phase 0/1/2 has been delivered; the records are in "Completed" below.

### Markdown Web Preview (started 2026-06-14, delivered)

> The design is in `docs/archive/2026-06_markdown_web_preview_prd.md` / `docs/archive/2026-06_markdown_web_preview_rfc.md`. This round delivers Phase 0/1/2.
> Decisions: images use data URIs and reuse `MarkdownImageResolver`; Web is not the default mode; the orchestration is in RFC §12.5.
> Build/test constraint: `xcodebuild build` and `xcodebuild test` must run serially (they share `build.db`).
> Key files: `OpenCodeClient/OpenCodeClient/Views/FileContentView.swift` (mode switching), `Utils/MarkdownImageResolver.swift` (data URI reuse).

**Parallel preparation (sub-agent, merged in after the main agent's acceptance)** ✅
- [x] Dependency research + frontend shell: markdown-it 14.2.0 + DOMPurify 3.4.10 (CDN-free, fetched from npm dist and copied out); all 5 shell checks pass in jsdom
- [x] Fixture generation: the nine `.md` files of §9.1 + `images/chart.png` (a real 6.8KB PNG) + `images/diagram.svg`; large_markdown is 70KB, over the 60KB threshold; the security fixture contains 4 payloads + a sentinel

**Phase 0 — Spike (serial, main agent)** ✅
- [x] Added `MarkdownWebPreviewView.swift` (a `UIViewRepresentable` wrapping `WKWebView`)
- [x] Bundle `preview.html/css/js` + markdown-it + purify; **pitfall: syncing a folder flattens its subdirectories**, so the vendor sits next to the html and the src drops the `vendor/` prefix; `loadFileURL(allowingReadAccessTo: bundleDir)`
- [x] The `window.renderMarkdown(payload)` entry point; Swift injects via JSONSerialization through `evaluateJavaScript` (no string concatenation)
- [x] Rendering + DOMPurify + basic CSS + light/dark theming inside the WebView
- [x] Manual simulator acceptance with `html_cards.md` / `dark_theme_cards.md`: the cards form correctly and dark mode has no dark background with dark text
- [x] `xcodebuild build` passed

**Phase 1 — Files MVP (serial, main agent)** ✅
- [x] `FileContentView`'s `showPreview: Bool` changed to the `MarkdownPreviewMode` enum (`native` / `web` / `source`)
- [x] The toolbar's two-state button became a Picker Menu: `Native Preview` / `Web Preview` / `Markdown Source`
- [x] `contentView(text:)` dispatches by mode; the large-file protection is kept (native falls back to source over the threshold; web asks for confirmation via the oversize gate over the threshold)
- [x] `MarkdownWebPreviewContainer` reuses `MarkdownImageResolver.resolveImages(...)` to produce data-URI markdown and then hands it to the WebView
- [x] The three states of loading / render failure / oversize + a one-tap button back to Native/Source
- [x] Added accessibility identifiers to the WebView root node (`markdown-web-preview-webview`) + the mode menu (`markdown-preview-mode-menu`)
- [x] Manual acceptance (simulator screenshots saved to outputs/web_preview_screenshots/): HTML card / dark mode / inline SVG / wide table / security filtering passed
- [x] `xcodebuild build` passed
- [x] UITEST_WEB_PREVIEW_FIXTURE + MarkdownWebPreviewUITests (all 5 tests passed, including the security sentinel assertions)

**Phase 2 — Security and polish (serial, main agent)** ✅
- [x] The DOMPurify allowlist forbids `script`/`iframe`/`form`/`object`/`embed`/`on*`/`javascript:` (shell configuration + a malicious_script fixture UI assertion that the sentinel renders and the script does not execute)
- [x] `WKNavigationDelegate` intercepts non-file/fragment navigation + external-link onOpenExternalURL; workspace relative links are resolved via resolveRelativeReference and land in fileToOpenInFilesTab
- [x] The WebView uses a non-persistent data store
- [x] Theming: the input carries colorScheme, and updateUIView re-renders on an input diff without rebuilding the WebView (the container reads @Environment(\.colorScheme))
- [x] UI tests: a mode round trip web↔source↔native (UITEST_WEB_PREVIEW_MODE_FIXTURE)
- [x] unit tests: 8 image/link path preprocessing cases (same directory / subdirectory / ./ / `../` / deep / workspace absolute / external / nil mdPath)
- [x] `xcodebuild build` + `xcodebuild test` passed serially (291 passed, no regression)

**This round's delivery is complete (Phase 0/1/2)**: Web Preview can be switched to manually from Files, and HTML cards / dark mode /
inline SVG / wide table / security filtering / relative links are all verified. The screenshots are saved to `outputs/web_preview_screenshots/`.
Not done (left for later): Phase 3 `.html` artifact / Mermaid / syntax highlighting / image tap-to-preview;
on-device (non-simulator) acceptance; custom URL scheme large-image optimization (the follow-up path for open issue 1).
Known fixture detail: the per-status colors of html_cards are not fully reproduced (the cards form but the palette leans neutral),
which is non-blocking and can be adjusted later via the fixture CSS selectors or DOMPurify style handling.

- [x] **PR merge** — design-redesign / Web Preview is on master
- [x] **Model list** — no longer maintaining a hardcoded preset table; it now uses the PR #149 shortlist

## Completed (recent)

- [x] **Composer send/stop logic regression fix (2026-05-29)**:
  - [x] Root cause: when the Quiet Tech composer was redone, the primary action was written as `if state.isBusy { stop } else { send }`, so while the AI was running the send button was replaced by stop and the user had to abort before sending a new message — breaking the established product behavior of "one send + one stop, and sending directly while running" (WORKING already recorded: "restore the ability to send messages while the AI is working: send is always visible, and stop/abort are shown at the same time")
  - [x] Fix: the send button is **always rendered** (`canSendNow` has no busy check, so while busy it can send as long as there is text), and stop became a button that appears **in addition** when busy rather than replacing send; the two are **stacked vertically** (send on top, stop below, in a VStack), not side by side
  - [x] Documentation: the composer section of design.md originally described the wrong behavior as "send is replaced in place by stop" and has been corrected to "send is always kept, stop coexists in addition, stacked vertically" — the root cause was a contradiction between the design description and the product behavior
  - [x] Verification: the iPhone build passed
  - **Branch**: `fix-composer-send-while-busy` (off master)

- [x] **Quiet Tech visual design language implementation (2026-05-29)**:
  - [x] Background: the "Quiet Tech" (calm tech) design locked in `docs/design.md` (PR #62) was brought into the SwiftUI code, iterating screen by screen against the four mockups in `docs/design_images/` via simulator screenshots until they matched
  - [x] `DesignTokens`: the Brand primary color → electric blue `#3B82F6`, with gold reserved only for "AI working"; the surface/composer received the design's dark values. The token **names are unchanged** and all Views keep referencing them, avoiding a large-scale change
  - [x] The three-state card language: the information card (tool) uses a neutral surface background, but the **icon/tool name/file path/chevron use electric blue** as a "tappable" hint (the card body is neutral, and the accent is only on interactive elements); the action card (permission) gets a 3pt blue bar on the left + a plain-text button (dropping the green/blue/red solid buttons); the patch card drops orange in favor of a single blue accent
  - [x] Message area: user messages keep a 3pt blue left bar + a muted background (the divider above is removed and spacing separates them instead); AI replies have no container
  - [x] Composer: collapsed into a single pill, the mic moved inside on the left (no border), and the send became a solid blue rounded square flush to the right (replaced by stop when busy)
  - [x] Toolbar: plain glyphs replace the filled circle; the model selector changes from a solid blue capsule → an outlined chip
  - [x] Session row: the selected state's left blue bar is baked into the rounded selection background and clipped inside the corners, no longer poking out or clashing with the expand chevron
  - [x] Settings: Theme changed to a segmented control
  - [x] iPad: the three columns are fully expanded by default (`columnVisibility = .all`); the sidebar's file tree is collapsed by default as a disclosure, and the sidebar mainly acts as a session picker
  - [x] On iPhone the tool/patch cards use a two-column grid (information density), and three columns on iPad
  - [x] Bug fix: messages are additionally loaded when restoring a session on restart (`loadSessions` previously only set `currentSessionID`, and `selectSession` short-circuited because the id already matched and did not fetch messages, so after a restart the last session showed a blank history and the user had to switch away and back)
  - [x] Verification: the iPhone 16 Pro + iPad Pro 11" builds are clean; screenshots against real data from a local server were compared for Chat (empty state + tool/patch/permission cards) / Settings / the iPad three columns
  - **PR**: #63 — feat(design): implement the "Quiet Tech" visual language

- [x] **Realtime speech WebSocket recovery V2 (2026-05-25)**:
  - [x] Product semantics: when the WebSocket drops during a long recording the recording is not interrupted; the client recovers from the local PCM cache instead of only failing after Stop
  - [x] Technical approach: every PCM chunk is written to both a temporary `.pcm` file and the live WebSocket; a heartbeat / send failure triggers a new session, replaying from cache offset 0 to the current end of the file and then resuming live sending once caught up; on Stop, the recovery is awaited to completion before committing/stopping
  - [x] Constraint: the first version accepts replaying from the beginning on every disconnect; ten minutes of PCM16 mono 24kHz is about 30MB, prioritizing reliability, with the performance issue left for later checkpoint optimization
  - [x] Startup experience optimization: after tapping the microphone, `AVAudioEngine` recording starts immediately and writes to the local PCM cache; the AI Builder session POST completes in the background, and once the session is ready the PCM cached during startup is replayed, avoiding a half-transparent recording button that has not captured anything because of the first-packet network wait.

- [x] **Start of the Voiceflow-style single app target migration (2026-05-02)**:
  - [x] Comparing against the Voiceflow configuration in `adhoc_jobs/brainwave_mobile/brainwave_ios` confirms that it is not a standalone visionOS app target but the main app target supporting `iphoneos iphonesimulator xros xrsimulator` at the same time, with `TARGETED_DEVICE_FAMILY = "1,2,7"` and the same bundle id
  - [x] Changed the `OpenCodeClient` main target to support iPhone / iPad / Apple Vision: added `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator xros xrsimulator"`, `TARGETED_DEVICE_FAMILY = "1,2,7"`, `XROS_DEPLOYMENT_TARGET = 26.0`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO`
  - [x] Initially `OpenCodeClientVisionAssets.xcassets` was wired into the main target resources so that the main target's visionOS build could reuse the existing layered app icon; after validation it was converged onto the main asset catalog
  - [x] The `Citadel` / SSH tunnel dependencies stay in the main target but are restricted to iOS-only via the build phase `platformFilters = (ios, )`, so that a native visionOS build no longer pulls in `swift-nio-ssh`; at runtime visionOS still uses the existing `#if os(visionOS)` stub, and SSH Tunnel is hidden in Settings
  - [x] Verification: `xcodebuild -showdestinations -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient"` already shows the native `platform:visionOS` / `platform:visionOS Simulator` destinations; `xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=visionOS Simulator,id=FBB8C85C-5EC8-40CC-B2CF-DAEC86BA530B' CODE_SIGNING_ALLOWED=NO` passed; `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' CODE_SIGNING_ALLOWED=NO` passed

- [x] **Deletion of the old `OpenCodeClientVision` target (2026-05-02)**:
  - [x] Deleted the standalone `OpenCodeClientVision` app target, product, build phases, build settings, and shared scheme; the project keeps only the single `OpenCodeClient` app target
  - [x] Deleted the standalone `OpenCodeClientVisionAssets.xcassets` and moved `AppIcon.solidimagestack` into the main `OpenCodeClient/Assets.xcassets`, so that both the iOS flat icon and the visionOS layered icon belong to the same app target's asset catalog
  - [x] The README build instructions now use a single `OpenCodeClient` scheme: iPhone, iPad, and Apple Vision Pro are all distributed from the same scheme and bundle identifier

- [x] **Keep the partial transcript when speech recognition fails (2026-05-02)**:
  - [x] Root cause: `ChatTabView.toggleRecording()` rolled `inputText` back to the pre-recording `prefix` in the transcription catch path; when the AI Builders realtime WebSocket had already streamed back a partial transcript and then reported an error, the text the user had already seen was overwritten, and in the empty-prefix case the input field appeared cleared
  - [x] Fix: added the thread-safe `SpeechPartialTranscriptBuffer`; the partial callback synchronously records the latest transcript every time; on failure the input field is restored with `prefix + lastPartialTranscript`, and without a partial the original prefix behavior is kept
  - [x] Tests: added `speechFailureInputPreservesLastPartialTranscript()` and `speechFailureInputFallsBackToPrefixWithoutPartialTranscript()`, covering the failure recovery and the no-partial fallback
  - [x] Verification: `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' CODE_SIGNING_ALLOWED=NO` passed; `xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClientVision" -destination 'platform=visionOS Simulator,id=FBB8C85C-5EC8-40CC-B2CF-DAEC86BA530B' CODE_SIGNING_ALLOWED=NO` passed

- [x] **visionOS layered app icon (2026-05-01)**:
  - [x] Generated a three-layer visionOS icon (background / middle / foreground) from the existing `OpenCodeClient/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
  - [x] The final approach programmatically layers by the original image's colors instead of directly using the model's transparent output; that way the composite preview is pixel-identical to the original, avoiding a transparent background being rendered as a checkerboard or green-screen keying leaving colored fringes
  - [x] Added `OpenCodeClientVisionAssets.xcassets/AppIcon.solidimagestack` and added it only to the `OpenCodeClientVision` target's Resources; the shared `OpenCodeClient/Assets.xcassets` continues to keep only the iOS `AppIcon`
  - [x] The visionOS app icon catalog uses the Xcode-generated `.solidimagestack` / `.solidimagestacklayer` structure; each layer's `Content.imageset` uses `idiom: vision` and `scale: 2x` and points at a 1024×1024 PNG
  - [x] Both the `OpenCodeClient` and `OpenCodeClientVision` targets use `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; since the two targets reference different asset catalogs, iOS uses the flat `AppIcon.appiconset` and visionOS uses `AppIcon.solidimagestack`
  - [x] Verification: the `OpenCodeClient` iphonesimulator build passed; the `OpenCodeClientVision` xrsimulator build passed; `assetutil --info` confirmed that the compiled `Assets.car` contains a `SolidImageStack` named `AppIcon` with the three layers Back / Middle / Front

- [x] **visionOS input area interaction sizes and default window size (2026-05-01)**:
  - [x] The recording button's active state changed to a red icon + red tint background/border, avoiding visionOS glass/material compositing washing the original solid red background out to white
  - [x] The three action buttons (mic / send / stop) on the right of the composer were enlarged from 32pt to 48pt on visionOS, and the vertical spacing was relaxed to 12pt to reduce the difficulty of gaze interaction; iPhone/iPad keep the original 32pt size
  - [x] When the AI is busy the stop button changed to the same red icon + tint background/border as the recording active state, instead of a solid red background; this keeps the red semantics more easily under visionOS glass/material
  - [x] The composer bottom container padding was changed to design tokens: visionOS uses 32pt horizontal / 20pt vertical and iPhone/iPad keep 16pt / 10pt, avoiding the bottom-right button sitting close to the Apple Vision Pro window resize handle
  - [x] The composer input field height was changed to a cross-platform token: 48–160pt on visionOS and 32–100pt on iPhone/iPad, avoiding the input area in a large window still being limited to a phone's height
  - [x] The open-file icon on the right of the tool-call header was enlarged on visionOS to a 44pt hit target + a `title3` icon, making it easier to open a patch/edit detail file with eye control or a gesture; iPhone/iPad keep the compact 24pt size
  - [x] The left Workspace / Sessions sidebar width of the visionOS split view was raised to 130% of the iPad default (`1.3 / 6.0`), and the minimum width raised from 10% to 13%
  - [x] The `OpenCodeClientVision` default window size was set to 2304×1080, about 180% of the system default width and 150% of its height, reducing the need to manually enlarge the window after first opening
  - [x] Subsequently, based on the on-device impression, the default window was narrowed and slightly heightened: the width went from 2304 down to 1382 (about 60%) and the height from 1080 up to 1188 (about 110%); the width was then fine-tuned to 1500 with the height kept at 1188
  - [x] Subsequently the default window width was raised to 2000 with the height kept at 1188
  - [x] Verification: the `OpenCodeClientVision` xrsimulator build passed; the `OpenCodeClient` iphonesimulator build passed

- [x] **visionOS native target baseline (2026-04-30)**:
  - [x] Added the `OpenCodeClientVision` application target, with the SDK pointing at `xros`, the device family set to Vision, and the source reusing the existing `OpenCodeClient/` synchronized root group
  - [x] Kept the iPad three-column `NavigationSplitView` as the main visionOS layout; no tab-based top-level navigation is introduced
  - [x] The first visionOS version does not support an SSH tunnel: the SSH Tunnel section is hidden in `Settings`, the launch/foreground-restore flows no longer try to auto-connect the tunnel, and the underlying `SSHTunnelManager` uses a stub on visionOS to avoid linking Citadel / swift-nio-ssh
  - [x] The first visionOS version first uses the system `AttributedString(markdown:)` to verify that the target compiles independently; it has since switched to the locally patched MarkdownUI / NetworkImage
  - [x] visionOS API compatibility: `scrollDismissesKeyboard(.immediately)` is wrapped in a platform-conditional modifier that skips the unavailable modifier under visionOS
  - [x] Verification: `xcodebuild -project "OpenCodeClient.xcodeproj" -target "OpenCodeClientVision" -configuration Debug -sdk xrsimulator CODE_SIGNING_ALLOWED=NO build` passed
  - [x] Follow-up verification: the locally patched MarkdownUI / NetworkImage now lets the visionOS target use `MarkdownUI.Markdown` directly

- [x] **MarkdownUI / NetworkImage visionOS package patch (2026-05-01)**:
  - [x] Initially added the local package sources `third_party/swift-markdown-ui` (2.4.1) and `third_party/NetworkImage` (6.0.1), replacing the remote MarkdownUI reference with an Xcode local package reference
  - [x] Subsequently migrated to GitHub forks: `grapeot/swift-markdown-ui` tag `2.4.1-visionos.1` and `grapeot/NetworkImage` tag `6.0.1-visionos.1`, with the Xcode project using exact version references and no longer vendoring `third_party/`
  - [x] `swift-markdown-ui/Package.swift` was raised to Swift tools 5.9, declares `.visionOS(.v1)`, and points `NetworkImage` at the exact `https://github.com/grapeot/NetworkImage` `6.0.1-visionos.1`
  - [x] `NetworkImage/Package.swift` was raised to Swift tools 5.9 and declares `.visionOS(.v1)`; `NetworkImage.swift` gained visionOS availability and uses a 1x1 transparent `CGImage` as the empty-image placeholder, avoiding the UIKit/AppKit-only empty image initializer
  - [x] `MessageRowView` and `FileContentView` resumed using `MarkdownUI.Markdown` on visionOS, removing the temporary native Markdown fallback
  - [x] Enabled visionOS Markdown embedded image support: `OpenCodeClientVision` explicitly links `NetworkImage`, and `FileContentView` and `MessageRowView` reuse the iOS `WorkspaceMarkdownImageProvider` / `MarkdownImageResolver` paths on visionOS
  - [x] Tapping a Markdown embedded image on visionOS now opens a separate Image Preview window; iPhone/iPad keep using the existing sheet preview
  - [x] Verification: `xcodebuild -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClientVision" -configuration Debug -sdk xrsimulator CODE_SIGNING_ALLOWED=NO build` passed
  - [x] Verification: `xcodebuild -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` passed
  - [x] Follow-up verification: after enabling the visionOS Markdown image gate, both the `OpenCodeClientVision` xrsimulator build and the `OpenCodeClient` iphonesimulator build passed

- [x] **Default model switched to GPT-5.5 (2026-04-28)**:
  - [x] The default sending model changed from DeepSeek to `openai/gpt-5.5`
  - [x] The GPT preset display name and model ID were upgraded from `GPT-5.4` / `gpt-5.4` to `GPT-5.5` / `gpt-5.5`
  - [x] Added a compatibility mapping for sessions with a saved old `openai/gpt-5.4` selection, to avoid the model selector falling back
  - [x] Added tests for the default selection and for migrating an old GPT selection

- [x] **Markdown report image rendering fix (2026-04-15)**:
  - [x] Root cause confirmed: Android can display images inside a report, so it is not a markdown content problem; Android first resolves relative image paths into `data:` URIs before rendering, whereas the iOS chat view originally only did path resolution and did not hook up an image provider capable of rendering `data:` URLs
  - [x] `MessageRowView`: added `WorkspaceMarkdownImageProvider` to the `ResolvedMarkdownView` in the chat so that the `data:` URIs already converted by `MarkdownImageResolver` actually display
  - [x] `WorkspaceMarkdownImageProvider`: added `workspaceDirectory` to the path relativization, so that markdown images in the file preview do not carry an absolute workspace prefix into the wrong `/file/content` API path
  - [x] `FileContentView`: passes `state.currentSession?.directory` into `MarkdownPreviewView` / `WorkspaceMarkdownImageProvider`, keeping the file preview and the chat view consistent in workspace path semantics
  - [x] Test fix: `WorkspaceMarkdownImageProviderTests.decodesBase64DataURL()` now uses the base64 of a real 1x1 PNG instead of the invalid `"hello"` payload; added coverage for absolute-workspace prefix stripping
  - [x] Verification: `xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' build` passed; `test` for the same destination passed
  - **Commit**: `5554fe9` — fix: render markdown report images on ios
  - **Commit**: `45044d4` — test: align markdown image provider data-url coverage

- [x] **Markdown caption image block preview fix (2026-05-03)**:
  - [x] Root cause confirmed: when a caption directly follows `![image](url)` with no blank line in between, MarkdownUI parses the image as an inline image inside the paragraph, bypassing `WorkspaceMarkdownImageProvider`, so a large remote image is displayed at its original size and cannot be tapped to preview.
  - [x] Before rendering, `MarkdownPreviewView` normalizes "an image alone on a line + non-empty text on the next line" into an image block, without changing the original file content; genuine inline images stay unchanged.
  - [x] `WorkspaceMarkdownImageProvider` adds a direct URLSession download path for remote HTTP(S) images, so remote images do not depend on the OpenCode server's base64 file interface.
  - [x] Added normalizer tests and HTTP(S) URL path tests; verified that `xcodebuild test` passes.

- [x] **Visual redesign Phase 2 — Mic button + color unification + interaction fixes (2026-04-01)**:
  - [x] The Mic button moved to the VStack above the send button, with a rounded border (1.5pt brand blue) so it reads as a tappable button
  - [x] The Brand primary changed from deep blue `(0.15, 0.25, 0.55)` to the system blue `(0.0, 0.478, 1.0)`, aligning with the iOS accent
  - [x] The 7 global `.accentColor` occurrences were replaced with `DesignColors.Brand.primary` (4 in ChatToolbarView, 1 in SessionListView, 1 in ContextUsageView, 1 in ToolPartView)
  - [x] The Transcribing state regained visibility (`surfaceLight`/`surfaceDark` backgrounds instead of `Color.clear`)
  - [x] Restored the ability to send messages while the AI is working (the send button is always visible, and stop/abort are shown together below)
  - **Commit**: `122f29c` — fix: mic button to right side with border, unify brand color to system blue
  - **Commit**: `4bf2e12` — fix: restore transcribing visual feedback and send-while-busy

- [x] **Design token test coverage (2026-04-01)**:
  - [x] Added `DesignTokensTests` (9 tests): exact spacing values + monotonic increase, ascending corner radii, the brand primary/gold RGB ranges, the valid opacity range + dark > light, the existence of the animation slots, and the semantic colors being mutually distinct
  - [x] All tests pass, `xcodebuild test` green

- [x] **Visual redesign Phase 1 (2026-04-01)**:
  - [x] `docs/design.md` — the complete design document covering 11 improvement directions
  - [x] `DesignTokens.swift` — the centralized design system (Brand primary deep blue + gold, semantic colors, warm-gray neutrals, a seven-step type scale, spacing, corner radii, animation presets, shadows)
  - [x] 17 view files redesigned: MessageRowView, ChatTabView, ChatToolbarView, ToolPartView, PatchPartView, PermissionCardView, QuestionCardView, SessionListView, ContextUsageView, StreamingReasoningView, TodoListInlineView, FileTreeView, FileContentView, SettingsTabView, SplitSidebarView, ContentView, L10n
  - [x] Message direction B (no bubble + a 4pt color bar on the left); AI messages are plain text with no container
  - [x] Composer redesign (mic embedded on the left, square send/stop buttons on the right, an input field without a border)
  - [x] The toolbar's model+agent merged into a configuration sheet, with Rename demoted to .secondary
  - [x] Unified card language: information cards drop their border, action cards get a color bar on the left
  - [x] The Context ring was shrunk to 18pt + a ≥85% pulse animation
  - [x] All newly added L10n keys (configureTitle/Model/Agent/NoAgents) include Chinese and English translations
  - [x] Fixed Gemini subagent mis-operations (PathNormalizer, restoring APIConstants/StorageKeys, hardcoded strings)
  - **Commit**: `b6ed2ac` — feat: redesign visual design system — design tokens, card language, composer, toolbar
  - **Advanced items not yet implemented** (P1: session summary preview, child session connector lines, session switch fade in/out, permission slide-in animation, message appearance animation; P2: tool card spring expansion, the logo empty-state breathing animation, dark-mode logo assets)

- [x] **Avoid synchronously changing state inside a view update when switching sessions (2026-03-30)**:
  - [x] Changed the draft synchronization and scroll state reset that respond to `currentSessionID` changes in `ChatTabView` to `Task { @MainActor in }`
  - [x] Reduced the probability of the runtime `Modifying state during view update` warning, without changing the existing session switching behavior

- [x] **GLM-5-turbo preset switched to GLM-5.1 (2026-05-03)**:
  - [x] Updated the model preset display name from `GLM-5-turbo` to `GLM-5.1`, and the modelID from `glm-5-turbo` to `glm-5.1`
  - [x] `canonicalModelPresetID` legacy migration: both `glm-5-turbo` and `glm-5.1` map to the new `glm-5.1`
  - [x] Updated the model references in the PRD and RFC documents in step

- [x] **GLM-5.1 preset switched back to GLM-5-turbo (2026-03-30)**:
  - [x] Updated the model preset display name from `GLM-5.1` to `GLM-5-turbo`
  - [x] Updated the underlying model ID from `glm-5.1` to `glm-5-turbo`
  - [x] Added a compatibility mapping for sessions with a saved old `glm-5.1` selection, so the selector does not fall back to another model

- [x] **Chat Composer visual compaction and Return key behavior adjustment (2026-03-28)**:
  - [x] Visual: the composer's minimum height was pushed further down from 44pt to 32pt, and the vertical padding of the input container / bottom bar was tightened to 5pt/6pt, so the input area is closer in height to the round button on the right and no longer wastes bottom space
  - [x] Behavior: modified `ChatComposerTextView` so the Return key (including Enter on an external keyboard) always inserts a newline instead of sending, and changed the keyboard Return key type from `.send` back to `.default`
  - [x] Safety: preserved IME marked-text composition safety so that an input method's commit action does not trigger unintended behavior; sending is triggered only by the round arrow button on the right
  - [x] Tests/docs: updated the `ChatComposerKeyAction` unit tests to match the new behavior and updated the README's notes on iPad keyboard behavior in step

- [x] **Fix premature sending on iPad with a Chinese IME + physical keyboard Enter/Shift+Enter (2026-03-28)**:
  - [x] Root cause: the Chat composer used the `.onSubmit` of `TextField(axis: .vertical)` and additionally attached the send button's `.keyboardShortcut(.return)`; with an external iPad keyboard, both Return paths could fire a send while the Chinese IME was still in marked text/composition
  - [x] Fix: the chat input field was replaced with a local `UITextView` bridge that distinguishes the IME composition state by `markedTextRange` in the delegate; a plain `Enter` sends, `Shift+Enter` inserts a newline, and the bare `Return` keyboard shortcut was removed
  - [x] Tests/docs: added a composer key decision unit test, changed the chat input UI smoke test to the `chat-input` accessibility identifier, and documented the Enter/Shift+Enter semantics for an external iPad keyboard in the README

- [x] **Fix duplicate sidebar entries after creating a session on iPad (2026-03-28)**:
  - [x] Root cause: both the optimistic `sessions.insert(..., at: 0)` in `createSession()` / `forkSession()` and the SSE `session.updated` write path could insert the same `session.id` into the local `sessions` again; the iPad sidebar is always visible, so the duplicate row and the double selection show up immediately; after switching to another session, `refreshSessions()` overwrites everything with the server's canonical list and the local duplicates disappear
  - [x] Fix: added an `upsertSession()` helper in `AppState` that deduplicates by `session.id`, and used it uniformly for `createSession()`, `forkSession()`, and `session.updated`, ensuring the local session state always satisfies single-ID uniqueness
  - [x] Tests: added a regression test for collapsing duplicates on create/fork, plus a state-flow test for `session.updated` converging duplicate sessions; verified that both `xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'generic/platform=iOS Simulator'` and `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'` pass

- [x] **GLM-5-Turbo preset switched to GLM-5.1 (2026-03-27)**:
  - [x] Updated the model preset display name from `GLM-5-Turbo` to `GLM-5.1`
  - [x] Updated the underlying model ID from `glm-5-turbo` to `glm-5.1`

- [x] **GLM-5 preset switched to GLM-5-Turbo (2026-03-20)**:
  - [x] Updated the model preset display name from `GLM-5` to `GLM-5-Turbo`
  - [x] Updated the underlying model ID from `glm-5` to `glm-5-turbo`

- [x] **Default model switched to GPT-5.4 (2026-03-19)**:
  - [x] The default sending model changed from `zai-coding-plan/glm-5` to `openai/gpt-5.4`
  - [x] New sessions and the default sending path with no saved model selection land directly on GPT-5.4

- [x] **oh-my-opencode default agent and Gemini model ID fixes (2026-03-17)**:
  - [x] The global `oh-my-opencode.json` default agent changed from GLM-5 to sisyphus ultraworker (Claude Opus 4.6)
  - [x] Gemini model ID fixes: `google/gemini-3-flash` -> `google/gemini-3-flash-preview`, `google/gemini-3-pro` -> `google/gemini-3.1-pro-preview`

- [x] **Swipe right from the left edge to open the Session List on iPhone (2026-03-19)**:
  - [x] Implementation: added a narrow transparent edge target on the left of `ChatTabView`, enabled only at compact width; dragging right from the left edge past the threshold takes the same `showSessionList = true` path as the toolbar
  - [x] Constraint: the start must hug the left edge, the horizontal displacement must be sufficient, and the vertical drift limited, avoiding misreading an ordinary vertical scroll as opening the session list
  - [x] Tests: added `SessionListEdgeSwipeBehaviorTests`, covering a valid left-edge right swipe, a start away from the edge, and an excessive vertical drag

- [x] **Fix wrong model shown after switching sessions with a Model selection (2026-03-14)**:
  - [x] Root cause: `inferAndStoreModelForCurrentSessionIfMissing()` has the precondition `guard selectedModelIDBySessionID[sessionID] == nil`, so when persistence holds an old value the inference is skipped and `selectedModelIndex` keeps the previous session's value
  - [x] Fix: renamed to `syncModelFromMessageHistory()`, removed the guard that skipped inference whenever persistence was non-empty, and after every message load the actual model is inferred from the message history and the selection updated; `applySavedModelForCurrentSession()` is kept as a fast synchronous path

- [x] **Context ring always visible + keeps its value while the AI is working (2026-03-14)**:
  - [x] Root cause 1: `ChatTabView` injected a `ProgressView` into `.navigationBarTrailing` while `state.isBusy`, visually covering the ring → the ProgressView block was deleted
  - [x] Root cause 2: while the AI is working the server creates a new assistant message with `tokens: {total: 0}`, and the old filter `tokens != nil` matched that empty message, making the ring show 0% → it was changed to `tokens != nil && tokens.total > 0`, skipping empty-token messages
  - [x] Caching: `AppState._cachedContextUsage` (`@ObservationIgnored`) caches the last valid snapshot; while messages are loading or the provider config is missing, the cached value is returned (limited to the same session); the cache is cleared when switching sessions

- [x] **Real-time display of the voice transcription partial transcript (2026-03-11)**:
  - [x] AIBuildersAudioClient: `transcribe` gains an optional `onPartialTranscript` callback, and `streamPCMOverRealtimeWebSocket` accumulates and calls back when it receives `transcript_delta`
  - [x] AppState.transcribeAudio: passes onPartialTranscript through
  - [x] ChatTabView: during transcription the partial is written to the input field in real time and replaced by the final on completion; on failure the prefix is restored

- [x] **Markdown large file / long line crash fix (2026-03-11)**:
  - [x] Root cause: MarkdownUI freezes/crashes on extremely long single lines (such as a transcript paragraph of 3000+ characters) or on large files (GH #426, #396)
  - [x] Fix: FileContentView detects `maxLineLength > 1500` or `totalLength > 60KB` before rendering and, when met, uses RawTextView directly to skip MarkdownUI
  - [x] MarkdownPreviewView keeps a secondary fallback; loadContent and onAppear keep the debug logs

- [x] **Realtime Speech voice transcription fixes (2026-03-11)**:
  - [x] Root cause 1: the API URL was built wrongly — `URL(string: "/v1/...", relativeTo: base)` replaces the base's path, so `https://space.ai-builders.com/backend` requests `/v1/...` instead of `/backend/v1/...`
  - [x] Fix: `buildAPIURL` ensures the base path ends with `/` so the relative path is appended correctly; session creation and testConnection now use that helper
  - [x] Root cause 2: m4a to PCM conversion fails — `AVAudioConverter` has known issues with AAC/m4a and throws `nilError`
  - [x] Fix: switched to the `ExtAudioFile` API for reading and converting, outputting 24kHz 16-bit mono PCM directly
  - [x] Added the `buildAPIURLPreservesMountPath` and `buildAPIURLWithoutMountPath` unit tests
  - [x] Added SpeechProfile debug logs (the session POST url, ws_url, the websocket connect, and the failure details of each step)

- [x] **Session tree hierarchy view (2026-03-03)**:
  - [x] Background: when an agent dispatches a background sub-agent it creates a child session (`Session.parentID` points at the parent session); previously all sessions were displayed at the same level, which cluttered the list
  - [x] Implementation: a `SessionNode` tree structure + the static `AppState.buildSessionTree(from:)` method, building the hierarchy recursively by `parentID`; orphan sessions (whose parentID points at a nonexistent session) are automatically promoted to root nodes
  - [x] UI: child sessions are indented (depth × 24pt), use a smaller font (`.subheadline`), and a lighter color (`.secondary`); the parent session shows a chevron collapse/expand button on the left
  - [x] `expandedSessionIDs: Set<String>` tracks the expanded state (collapsed by default), and `toggleSessionExpanded()` toggles it
  - [x] iPhone (`SessionListView`) and iPad (`SplitSidebarView.SessionsSidebarList`) were updated in step to render the tree recursively
  - [x] Unit tests: 7 tests covering hierarchy construction, orphan handling, ordering, multi-level nesting, empty input, archive filtering, and collapsed-state toggling

- [x] **Session creation limited to Server default (2026-02-25)**:
  - [x] Root cause: `POST /session` does not support passing a directory, so a new session always lands in the server's current project; the iOS Project selector only filters the list and does not change the creation target
  - [x] Implementation: the create button is offered only for Server default; when a specific project is selected the new-session button is greyed out with an info icon pointing to switching on the server side
  - [x] `canCreateSession`, `chatCreateDisabledHint`; ChatToolbarView and SessionListView grey out + info
  - [x] Documentation: lessons §16, RFC §4.3.1, PRD §4.4.3
- [x] **Project selection feature (completed 2026-02-25)**:
  - [x] PRD/RFC update: added the Project (Workspace) design
  - [x] Implemented the `Project` data model, `APIClient.projects()`, and `sessions(directory:limit:)`
  - [x] Updated `AppState`: projects, selectedProjectWorktree, customProjectPath, effectiveProjectDirectory
  - [x] Settings UI: Project Picker (Server default / project list / Custom path)
  - [x] Unit tests: Project decoding and the effectiveProjectDirectory logic; fixed `SessionDeletionSelectionTests.makeSession` missing the archived parameter
  - [x] Fixed the root cause of "the phone can only see sessions from two weeks ago": Web and iOS look at different projects by default; filtering by project is now supported
- [x] **Agent selection feature (completed 2026-02-21)**:
  - [x] RFC/PRD update: added the Agent data model, API, and UI design (v0.2 / RFC-002)
  - [x] Implemented the `AgentInfo` data model (with mode filtering: primary/all are shown, subagent is hidden)
  - [x] Implemented the `APIClient.agents()` method
  - [x] Updated `AppState`: added the agents list (prefilled with 5 default agents), selectedAgentIndex, and loadAgents()
  - [x] Updated the model list: GLM-5 (default) / Opus 4.6 / Sonnet 4.6 / GPT-5.3 Codex / GPT-5.2 / Gemini 3.1 Pro / Gemini 3 Flash
  - [x] Updated `ChatToolbarView`: the chip's horizontal scroll became a dropdown list (Model + Agent)
  - [x] Updated `promptAsync`: pass the selected agent
  - [x] Unit tests: Agent API decoding + mode filtering tests
  - [x] OpenCode-Builder set as the default agent
- [x] **Rendering performance optimization 1/3 (removing the global state subscription at row level)**: `MessageRowView/ToolPartView/PatchPartView` dropped the direct `@Bindable AppState` connection in favor of the minimum necessary data + a file-open callback, reducing the full-page recomputation triggered by unrelated state changes in long sessions
- [x] **Rendering performance optimization 2/3 (lightweight Scroll Anchor)**: `scrollAnchor` changed from "concatenating all message/streaming strings" to an O(1)/small-constant signature based on `messageCount + lastMessageSignature + streaming chars`, avoiding a full traversal on every state change in a long session
- [x] **Rendering performance optimization 3/3 (Markdown fast path)**: plain-text messages render with `Text`, and `MarkdownUI` is used only when Markdown syntax characteristics are detected, reducing the parsing and layout overhead of many ordinary text messages in long sessions
- [x] **Segmented message loading (3 turns)**: by default only the most recent 3 turns (6 messages) are fetched, the chat page shows "pull down to load more history messages" at the top, and each pull extends by 3 turns and refetches
- [x] **SSH Tunnel remote access** (Citadel integration complete):
  - [x] SSHKeyManager: Ed25519 key generation/storage (Keychain)/public key display
  - [x] SSHTunnelManager: connect/disconnect/status
  - [x] SSHTunnelConfig data model
  - [x] Settings UI: SSH Tunnel configuration area
  - [x] AppState integration: SSH connection state
  - [x] Unit tests
  - [x] Added the Citadel dependency (SPM)
  - [x] Implemented the actual SSH connection logic (local 127.0.0.1:4096 → SSH DirectTCPIP → VPS 127.0.0.1:remotePort)
  - [x] Fixed the project deployment target (so the UITests can run on the simulator)
- [x] **UI improvement** (low priority): the busy state uses a spinner instead of a round button
- [x] **Permission request interaction fix**: supports Allow once / Allow always / Reject, and ensures POST `/session/:id/permissions/:permissionID` carries the body `{"response":...}`
- [x] **SSH Public Key UI**: the public key should still be generatable/viewable/copyable when not connected (avoiding an all-grey button inside the sheet)
- [x] **Permission card position**: the permission conversation card should render at the bottom of the message stream (scrolled to the bottom by default) and sit above the activity/thinking row
- [x] **Activity timing persistence**: the timing is derived from the message's `time.created/time.completed`, avoiding a reset to 0 after restarting the app or switching sessions
- [x] **Activity/Busy state flicker**: the session.status polling result does not overwrite recent SSE; the activity copy updates use a 2.5s debounce + a debug log
- [x] **Per-turn Activity row**: a completed activity row (showing the elapsed time) is kept at the end of each user turn; the current in-progress turn shows a running activity row at the bottom
- [x] **Fix for the obvious iPhone heat hotspot (scrolling)**: removed the influence of the running activity's per-second timer on `scrollAnchor`, avoiding a `scrollTo("bottom")` animation firing every second
- [x] **Full Code Review document rewrite (2026-02-13)**: deleted and rewrote `docs/code_review.md`, focusing on the obvious architecture/performance/security issues and their priorities
- [x] **SSH TOFU security baseline**: replaced `acceptAnything`; the first connection trusts the host key, later connections verify it strictly, and resetting the trusted host is supported
- [x] **SSE main channel convergence**: removed the permanent busy polling in favor of a one-time bootstrap sync after an SSE reconnect (messages + permissions)
- [x] **AppState refactor (PermissionController)**: the permission event parsing/writing-back and the pending mapping were extracted from AppState, with behavior tests added
- [x] **AppState refactor (Iteration C - ActivityTracker)**: the activity state derivation/debounce/duration rules were extracted, with behavior tests added
- [x] **Fix for the Activity Row completing too early**: when session.status turns idle but there is still a running/pending tool or streaming, it stays running and the timer does not stop early
- [x] **Complete SSH UX**: Settings gained "Copy Public Key", a setup guide, and a grey hint (after enabling SSH you must tap Test Connection above)
- [x] **Fix for the quick session switching race (full fetch)**: added a requestedSessionID check to `loadMessages/loadSessionDiff` and discarded stale responses, avoiding the old B result overwriting things after A→B→A
- [x] **Fix for the Activity Row completing too early (second pass)**: the `running/completed` decision changed to "the current turn + busy state takes priority" and no longer depends on `completedAt == nil`, avoiding showing completed while it is still running
- [x] **SSH UX fixes**: the default Server Address changed to `127.0.0.1:4096`; after SSH is enabled a configuration change auto-reconnects; View Public Key no longer shows blank in the enabled scenario; the `Set Server Address` CTA became an explicit blue button
- [x] **Settings close button consistency**: the top right of the sheet became the English `Close`, avoiding Chinese text in an English interface
- [x] **Localization plan**: added `docs/features/localization/research.md` (formerly `docs/dev_localization.md`), laying out an en/zh-Hans bilingual roadmap and a phased migration plan
- [x] **Fix for automatic SSH foreground/background recovery**: the SSH/SSE connections are actively closed when entering the background; when returning to the foreground, if the health check fails, the SSH tunnel is forcibly rebuilt once before the refresh
- [x] **SSE reconnect state compensation**: `/session/status` is refetched during the SSE bootstrap and on the `server.connected` event, avoiding a state gap where only the messages are refreshed
- [x] **Fix for a stuck busy state / the feeling that Abort does nothing**: when merging polls, a session that is "missing from the poll result but still busy/retry locally" is downgraded to idle and the streaming is cleaned up in step; after an abort the state and messages are immediately refetched
- [x] **Todo rendering compatibility fix (OpenCode upgrade)**: supports the new and old `TodoItem` fields (`status/priority/id` versus the legacy `completed`), and fixes the parsing of the tool state `metadata.todos`/`output(JSON)`; a non-string `metadata.input` no longer leaves the todo card blank
- [x] **SSH runtime crash protection (NIO channel state)**: fixed the concurrency problem of calling channel/context close across threads in `SSHTunnelManager` (all calls switched back to executing on the NIO eventLoop), avoiding `Sent channel window adjust on channel in invalid state` triggering a fatal error
- [x] **Stronger SSH Public Key interaction (second pass)**: `View Public Key` now always goes through `generateOrGetPublicKey()` (no longer preferring a possibly empty cached value), and `Copy Public Key` + `View Public Key` are merged into a single row of buttons, reducing the Settings area footprint
- [x] **Tailscale / Server Address UX (2026-03-01)**: the ATS exception adds `NSIncludesSubdomains` for `ts.net`; `correctMalformedServerURL` fixes the malformed `host://host:port` format; `ensureServerURLHasScheme` automatically adds `http://` when there is no http/https; the correction timing changed to lose focus (`@FocusState` + `onChange`), avoiding a rewrite on every character; the Server Address keyboard `submitLabel(.done)` shows Done

## Completed

- [x] Session list: the list button on the left of the Chat Tab shows all Sessions under the workspace, supporting switching, creating, and pull-to-refresh
- [x] PRD update (async API, default server, removing large session/push notification/multi-project)
- [x] RFC update (MarkdownUI, native capabilities, Phase 4 not implemented for now)
- [x] Git initialization, .gitignore (including opencode-official), docs moved to docs/
- [x] Initial commit: docs, the OpenCodeClient scaffold
- [x] Phase 1 basics: Models, APIClient, SSEClient, AppState
- [x] Phase 1 UI: Chat Tab, Settings Tab, Files Tab (placeholder)
- [x] Phase 1 completion: SSE event parsing, streaming updates, Part.state compatibility, Markdown rendering, and full-row display of tool calls
- [x] Phase 2: Part rendering (reasoning collapse, step separators, patch cards), manual permission approval, theme switching
- [x] UX simplification: a single-row toolbar (left: new/rename/view session; right: 3 model icons), removing Compact, Import, and Model Presets
- [x] Phase 3: the file tree (recursive expansion, on-demand loading), file content (code line numbers, Markdown Preview toggle), the Files Tab (File Tree only) + file search
- [x] Tool/Patch tap navigation: tools such as write/edit/apply_patch that contain a path can be tapped to "open in File Tree" for a file preview (the path comes from metadata, state.input.path/file_path/filePath, and patchText parsing)
- [x] apply_patch path parsing fix: patchText starts with "*** Begin Patch\n*** Add File: ", so the lookup now uses range(of:)
- [x] The Tool card gained an "Open in File Tree" button (a folder icon next to the label) + a context menu
- [x] Markdown preview: uses the MarkdownUI library (swift-markdown-ui 2.4.1) instead of the custom rendering, fully supporting GFM (tables, headings, code blocks, lists, etc.)
- [x] Unit tests: defaultServerAddress, sessionDecoding, messageDecoding, sseEvent, partDecoding
- [x] UI polish: enlarged the input field (3–8 lines, capsule shape), a gradient model selector capsule, SF Symbols rendering style, improved message bubbles, softened corners on tool/patch/permission cards, and MarkdownUI for chat message rendering
- [x] Chat: AI responses support text selection/copying (including Markdown rendering)
- [x] Chat → file navigation: switched to encoding the query with URLComponents, unified the file path normalization, and added an empty-content warning log
- [x] Tool card: the collapsed reason/title shows at most two lines + an ellipsis, while the expanded state shows the full Reason
- [x] Session Todo (task list): supports fetching `/session/:id/todo` + SSE `todo.updated` updates; the todo is rendered inside the `todowrite` tool card (option B, with no always-on top section)
- [x] Phase 3: Think Streaming delta
- [x] Phase 3: iPad / Vision Pro layout: when `horizontalSizeClass == .regular` it splits left/right (Files on the left, Chat on the right), with Settings as a toolbar button
- [x] iPad / Vision Pro layout upgrade: three columns (NavigationSplitView) — Workspace (Files+Sessions) on the left / Preview in the middle / Chat on the right
- [x] iPad three-column width ratios: Workspace ≈ 1/6; Preview ≈ 5/12; Chat ≈ 5/12
- [x] The iPad three columns are draggable: a default ideal width is set, but the user can drag the dividers to adjust
- [x] Inline iPad file preview: selecting a file on the left, or tapping a file from a Chat tool/patch, updates the middle Preview (no more sheet)
- [x] iPad Preview refresh button: manual refresh in the top right of the middle column (reloading the file content)
- [x] Test coverage: SSE event structure, session filtering, PathNormalizer, path normalization
- [x] iPad message stream density optimization: tool/patch/permission cards fill the iPad three-column grid horizontally; text parts still display full width
- [x] PathNormalizer hardening: percent-encoding decoding, file:// compatibility, the most basic ../ defense, and absolute path → workspace relative path resolution (fixing the class of issues where a tool read preview shows empty content)
- [x] Documentation sync: PRD/RFC gained the iPad three-column grid description; lessons.md gained the "PRD/RFC→code→test→build/test" workflow
- [x] Code review archived
- [x] Voice input (AI Builder Speech Recognition): record (mic permission) → call `/v1/audio/transcriptions` → append the text to the input field
- [x] iPad external keyboard: Enter sends (submitLabel/send + keyboardShortcut Return)
- [x] Network security boundary: http:// is forbidden on the WAN (https:// is enforced); Settings shows the scheme and a hint
- [x] 3.1 apply_patch is displayed as "patch" (ToolPartView.toolDisplayName)
- [x] 3.2 In Settings, the HTTP scheme is orange + an info icon
- [x] 1.1 Detailed AppState planning
- [x] Bug: tool layout — thinking is merged into the last MessageRowView and does not start a new row that would break the grid
- [x] Bug: Diff/file preview — horizontal scrolling, minWidth fill, textSelection
- [x] Bug: Markdown source view width — after switching Markdown/Preview the source view only occupied the left half, causing early wrapping (switched to RawTextView so the text fills the available width)
- [x] Todo 2.4 is not emphasized, following option B
- [x] Latest commit/push: 9b4b842 (tool layout, Diff preview, Settings HTTP info, 1.1 planning, 2.4)
- [x] **GLM-4.7 → GLM5**: the model was updated to `zai-coding-plan` / `glm-5`
- [x] **New model**: added `openai` / `gpt-5.3-codex-spark` (GPT-5.3 Codex Spark)
- [x] **iPhone model short names**: the model chip in the iPhone top bar shows `GPT` / `Spark` / `Opus` / `GLM`, while the iPad shows the full name
- [x] **Tool card color differentiation**: `todowrite` uses a green accent and the other tools use the theme color (accentColor), making it easy to scan
- [x] **Patch card style alignment**: the same light background + thin border as the tool cards, making the information clearer
- [x] **Card visual consistency**: tool/patch/permission/user messages share one light background opacity (0.07) + thin border (0.14) style
- [x] **Automatic session title update**: listens for the SSE `session.updated` event + polls for a refresh after sending, with no manual renaming needed
- [x] **Fix for the Thinking typewriter effect**: when `message.part.updated` (reasoning) is received, `StreamingReasoningView` is shown fixed at the bottom of the message list and no longer depends on the messages already having a reasoning part
- [x] **Validate the AI Builder Token before recording**: when the token is empty / a test is running / the test has not passed, a dialog tells the user to configure it in Settings first
- [x] **Test Connection spinner state**: while the Settings AI Builder connection test runs, "Testing..." + a ProgressView are shown
- [x] **Persistable AI Builder test state**: after a successful Test Connection the OK state survives an app restart; it only auto-invalidates when the token/baseURL changes
- [x] **Send/record buttons stacked vertically**: on both iPhone and iPad they became a VStack layout, with send on top, mic below, and abort (if any) at the very bottom
- [x] **Session list sorted by update time**: uses `sortedSessions` ordered by `time.updated` descending
- [x] **Session row time display uses the update time**: the session list's "xx minutes ago" changed to `time.updated`
- [x] **Remove the blue from the session list**: the list text uses a neutral color (gray) and the current Session is highlighted with a background
- [x] **Session action button order adjusted**: the order of the buttons on the left of the Chat top toolbar changed to Session list → Rename → Compact → New Session
- [x] **Fix the blank bug when switching sessions**: on switching, the messages/parts/streaming state is cleared first and then the new session's data is loaded
- [x] **Server error message display**: when an assistant message carries `error.data.message` it is shown as a red card in the message
- [x] **iPad sidebar split top/bottom**: the left side became Files (File Tree) on top and Sessions below (tapping the list switches the Chat Session on the right)
- [x] **Equal-height Workspace left column**: the iPad Workspace left column's Files/Sessions blocks are 1:1 in height
- [x] **Inline iPad Workspace file preview**: tapping a file in the File Tree on the left of the Workspace updates the middle Preview column
- [x] **todowrite renders only the todo**: the Tool card no longer shows todowrite's raw JSON input/output and keeps only the rendered todo list
- [x] **Context usage ring**: a context usage ring was added between the model and the gear at the top of the Chat; tapping it pops up the token/cost breakdown (a grey empty ring when there is no data)
- [x] **Fix for loading the Context provider config**: the decoding of `GET /config/providers` supports the array/dict variants; tapping the ring triggers the load automatically if it has not been loaded, and shows an error message on failure
- [x] **Context sheet default size optimization**: on the iPad it opens directly at large (avoiding starting small and gradually growing)
- [x] **Input draft persistence**: the unsent input is persisted per sessionID and can be restored when switching sessions; it is cleared after a successful send
- [x] **Model selection remembered per Session**: switching sessions automatically restores the model last selected for that session (avoiding a global override)
- [x] **Fix duplicate sent messages**: in busy/polling scenarios the optimistic temporary user message is deduplicated, avoiding two entries in the UI
- [x] **Busy/Retry session polling enhancement**: `retry` is treated the same as `busy`; while busy it polls and refreshes automatically, and it stops automatically when it exits busy
- [x] **Chat Activity message**: renders "current operation + elapsed time" as the last entry in the message stream (remembered per session); it updates every second while running and, once finished, freezes as Completed and is kept until the next run; the copy follows the web: reasoning is extracted from `**title**` as `Thinking - title`, and tools are mapped by type to "Searching/Making edits/Running…"
- [x] **loadMessages decoding fallback**: supports an empty body / a non-array payload (`messages`/`data`/`result` wrapped, or a single object) so that polling is not interrupted by a parse failure
- [x] **Message visibility during streaming**: the poll merge keeps the temporary user message and the streaming assistant draft (avoiding the UI flashing back or losing them when the busy list is empty)
- [x] **Chat empty state optimization**: no session / busy(retry) / empty messages each show a different hint; the scroll anchor includes the streaming delta length so the scroll does not fail to refresh

## To Do

- [x] **Code Review 1.1**: AppState split (SessionStore/MessageStore/FileStore/TodoStore, keeping the public API unchanged)
- [x] **Code Review 1.2**: SSE research (the API's single-line data is already sufficient, RFC planned, add Accept/Cache-Control headers)
- [x] **Code Review 1.3**: filter SSE message.updated by sessionID
- [x] **Code Review 1.4**: PathNormalizer unifies path normalization (Utils/PathNormalizer.swift)
- [ ] **Phase 4: iPad / Vision Pro layout optimization**: consider (optionally) finer-grained controls for the Preview column such as "pin/close the current file"
- [x] **Model replacement (OpenAI)**: GPT-5.2 is replaced by GPT-5.3 Codex Spark (short name `Spark`), and the iPhone short name of GPT-5.3 Codex changed to `GPT`
- [ ] **iPhone heat investigation and optimization (deferred)**: paused given the current priority, to be revisited later with an Instruments review and further optimization
- [x] **Activity Row per-turn retention check (code review)**: one round of code-level checks is done (per-turn completed + new turn running logic); the on-device interaction regression continues to be followed up
- [x] **Full codebase review document rewrite**: deleted the old `docs/code_review.md` and rewrote it against the current code, focusing on architecture/refactorability and the obvious performance and security issues
- [x] **SSE main channel + one-time bootstrap**: removed the permanent busy polling, keeping the one-time full compensating sync on reconnect/entering a session
- [x] **AppState Refactor Iteration B (PermissionController)**: first add tests, then extract the permission control logic while keeping the external interface unchanged

### Code Review improvements (from code_review.md)

- [x] **4.2 Race Condition**: added `sessionLoadingID` to session switching to prevent a race when switching quickly
- [x] **3.2 Error Presentation**: unified the error handling pattern
- [x] **3.3 Magic Numbers**: extracted the constants (column width ratios, animation durations, etc.)
- [x] **3.4 Test Coverage**: added AppState-level tests
- [x] **3.5 View Decomposition**: split ChatTabView
- [x] **3.1 AppState Size** (partially done - the Store has been extracted, the full Coordinator is still pending): continue extracting the Coordinator
- [x] **4.1 Memory Leaks**: SSE connection deinit handling
- [x] **4.4 Default Server**: changed the default server configuration

## Problems Encountered

1. **Local network prohibited (iOS)**: connecting to `192.168.180.128:4096` reports `Local network prohibited`. Add the following to Info.plist:
   - `NSLocalNetworkUsageDescription`: explains why the local network is needed; the first access pops up a permission dialog
   - `NSAppTransportSecurity` → `NSAllowsLocalNetworking`: allows HTTP access to a local IP
   - The user must tap "Allow" in the dialog before connecting

2. **Stuck after sending**: a failed send gives no feedback, and since the input field was cleared the user does not know it failed. Fix: restore the input on failure, show an error alert, and show a loading state while sending

3. **No real-time updates after sending**: the send succeeds and the web side already has a response, but the iOS side only shows it after a restart. Causes:
   - SSE only connects on `willEnterForegroundNotification`, so it was not connected on first launch
   - Some events (such as `server.connected`) have no `directory` field, so parsing fails
   - Fix: call `connectSSE()` after `refresh()` succeeds; make `SSEEvent.directory` optional; after a successful send, start a 60-second polling (loadMessages every 2 seconds) as a fallback

4. **loadMessages parse failure**: when the LLM outputs a thinking delta, `Part.state` expects a String but the API returns an object (ToolState). The error is: `Expected to decode String but found a dictionary`. Fix: added `PartStateBridge`, which supports state being a String or an object and, for an object, extracts `status`/`title` for the UI display

5. **Unable to simultaneously satisfy constraints**: a constraint conflict involving the keyboard (TUIKeyboardContentView, UIKeyboardImpl). It comes from the system keyboard, not the app code, and usually needs no fix.

6. **Terminology clarification**: Think streaming actually refers to the expand/collapse behavior of Think (ReasoningPartView), not to a Tool.

7. **messages parse noise while polling**: `The data couldn’t be read because it is missing` occasionally occurs during busy/retry (an empty body / an unstable payload shape). Fix: the APIClient gained an empty-body guard + a multi-shape decoding fallback; AppState catches DecodingError and only logs it, avoiding treating a polling problem as a connection failure.

8. **SSH runtime fatal (NIO channel state)**: `Sent channel window adjust on channel in invalid state` occasionally occurs in scenarios such as scrolling the Settings page. It was traced to `SSHTunnelManager` calling NIO `channel.close/context.close` directly from the NW callback thread, causing a state machine race; the fix is to schedule the close uniformly through `eventLoop.execute`.

9. **Simulator SpringBoard crash (not an app process)**: the latest crash log shows `Process: SpringBoard`, with the thread `com.apple.xpc.activity.com.apple.SplashBoard` triggering `dispatch_assert_queue`; this is an abnormality of the simulator's system component, not an `OpenCodeClient` process crash. Conclusion: there is no direct causal link to the current business code changes; troubleshooting should prioritize the "restart/erase the simulator + reinstall the app" path.

10. **View Public Key is still blank in some scenarios**: when SSH is enabled but the connection fails, the old logic first reads the locally cached public key, which risks hitting an empty string and leaving the sheet empty. Fix: when opening the sheet, it is always obtained through `generateOrGetPublicKey()` with a trim + empty guard, and an error dialog is shown on an exception.

11. **Tailscale MagicDNS needs an ATS exception**: company policy requires all hosts to use ATS/HTTPS, but the servers resolved by Tailscale MagicDNS (`*.ts.net`) usually run HTTP. Fix: under `NSAppTransportSecurity` in Info.plist add `NSExceptionDomains` → `ts.net` → `NSExceptionAllowsInsecureHTTPLoads: true` + **`NSIncludesSubdomains: true`** (key point: without it `ts.net` does not match subdomains such as `host.example.ts.net`), exempting only the Tailscale domains from the HTTPS requirement; other domains remain subject to ATS. **Malformed Server Address**: iOS `.textContentType(.URL)` or a paste can produce the `host://host:port` format, causing the request to hit port 80 and get ECONNREFUSED. Fix: `correctMalformedServerURL` corrects the malformed value; `ensureServerURLHasScheme` adds `http://` when there is no http/https; the correction timing is **lose focus** (`@FocusState` + `onChange`), avoiding a rewrite on every character; the keyboard `submitLabel(.done)` shows Done.

## Decision Log

(Records the technical decisions made during implementation)

## API verification (localhost:4096)

- **GET /project**: ✅ returns `Project[]`, containing id/worktree/vcs/time
- **GET /session?directory=&limit=**: ✅ filters sessions by worktree, limit defaults to 100
- **GET /global/health**: ✅ `{ healthy, version }`
- **GET /config/providers**: ✅ returns `providers: array` (not a dict), where each item contains `id`, `name`, `models: { modelID: ModelInfo }`. The iOS parsing has been fixed.
- **GET /agent**: ✅ returns `[AgentInfo]`, containing the name/description/mode/hidden/native fields. The iOS side filters out mode=subagent.
- **Import from Server**: depends on config/providers and should import normally now that the parsing is fixed.

The current model presets (4):
| Display name | providerID | modelID |
|----------|------------|---------|
| GLM-5.1 | `zai-coding-plan` | `glm-5.1` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |
| DeepSeek | `deepseek` | `deepseek-v4-pro` |

Agent prefill (5, OpenCode-Builder by default):
- OpenCode-Builder (mode=all)
- Sisyphus (Ultraworker) (mode=primary)
- Hephaestus (Deep Agent) (mode=primary)
- Prometheus (Plan Builder) (mode=all)
- Atlas (Plan Executor) (mode=primary)

## Diff issues

In practice `GET /session/:id/diff` returns `[]`, even when the session has write operations. GH #10920 and others suggest this may be an OpenCode server-side session_diff tracking issue that the official web client may also hit. Not fixed for now; waiting for a server-side fix.

## Tool card rendering rework (design only, not implemented)

A "Tool Card Rendering Rework" section was added at the end of design.md. **Note: a pixel-art style was explored initially but abandoned — OpenCode does not pixelate as a whole**; what is attractive is that **information organization**, not the pixel texture. **Only the design + mockup are landed, no code changes**; the implementation goes into a later PR.

Three concrete changes:
1. **Distinguish who is speaking**: user messages keep the blue left bar; OpenCode replies **drop the avatar** but gain an "OpenCode" text title + **keep the existing small model text** (unchanged). Separate them clearly with a different visual style.
2. **Two-column grid of file cards**: patch/edit/write/read → a file card (file icon + file name + chevron), arranged in a two-column grid.
3. **Merge into "N tool calls"**: the remaining tools → `▸ 3 tool calls`, expanded to see them one by one.

Arrangement: a layout-first near-chronological order (adjacent same-kind items are aggregated), with no grouping and no section headers. Boundaries: no pixel-art style, the model selector is untouched, no user avatar in the top right, and AI working keeps the existing subtle gold motion.

The mockup is in `docs/design_images/tool_cards_chronological.png` (generated with gpt-image-2).
