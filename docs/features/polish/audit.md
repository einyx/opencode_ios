# Polish Audit — measured baseline

The state of the app against every row of [`rubric.md`](rubric.md), measured on the working tree at `master`.

> **This table is a snapshot, not a gate.** A static table cannot prevent regressions — that is what `scripts/polish_lint.sh` (Phase 1) and the token assertions in `DesignTokenTests.swift` are for. This file exists so Phases 2–7 know their starting point and can show the delta.
>
> **The haptic rows below were re-measured after an independent code review
> and an independent privacy review both returned FAIL.** The findings were
> addressed: the microphone guard is now unbypassable, the visionOS platform
> guard was corrected, the announcement ledger replaced the live-list check,
> and the silent-mode policy was written down. **Re-verification of the fixes
> is still outstanding**, so the haptic rows are marked on their predicates, not
> on a passing review.
>
> Measured 2026-10-25 against `master` after `fe3ec83` (feat(hosts): start without a host and let the last host be removed). Unit baseline: **1070 tests** (2026-10-24 run).

**Legend** — `PASS` conformant · `FAIL` violates the rule · `PARTIAL` conforms in part · `REVIEW` needs a human check, no automated predicate · `AMBIGUOUS` the spec does not settle it · `DEFERRED` out of scope for v1.

| ID | State | Evidence |
|---|---|---|
| POL-COLOR-01 | **FAIL** | No `bg.primary` token exists. `DesignColors.Neutral` defines only `surfaceLight`/`surfaceDark`/`composerLight`/`composerDark` (`Utils/DesignTokens.swift:60-67`); the chat root sets no background, so the implicit system background is used instead of `#0B0C0E`. |
| POL-COLOR-02 | **PASS** | `DesignTokens.swift:66` `composerDark = (0.078, 0.086, 0.098)` = `#141619`, documented as "the secondary bg". |
| POL-COLOR-03 | **PASS** | `DesignTokens.swift:62` `surfaceDark = (0.102, 0.114, 0.129)` = `#1A1D21`. |
| POL-COLOR-04 | **FAIL** | All three text tokens are system colours, not the spec hexes: `DesignTokens.swift:49` `text = Color.primary`, `:51` `textSecondary = Color.secondary`, `:54`/`:56` `textTertiary = UIColor.tertiaryLabel` / `Color.gray.opacity(0.4)`. Spec wants `#ECEDEE` / `#9BA1A6` / `#5A6066`. |
| POL-COLOR-05 | **PARTIAL** | Dark accent is correct: `DesignTokens.swift:24` `Brand.primary = (0.231, 0.510, 0.965)` = `#3B82F6`. The light `#2563EB` variant has no token — `Brand` defines a single value. |
| POL-COLOR-06 | **FAIL** | No accent-muted token. `DesignTokens.swift:88` `Opacity.selectionFill = 0.08` is a different role, and `:251` `DesignShadow.medium` uses `Color.black.opacity(0.08)` rather than the accent at 8%. |
| POL-COLOR-07 | **PARTIAL** | `DesignColors.Neutral` carries explicit light/dark pairs (`DesignTokens.swift:60-67`), but `Neutral.text`/`textSecondary` are system colours and `Brand.primary` has no light variant, so the mapping is not one-token-set. |
| POL-COLOR-08 | **FAIL** | 7 raw colour literals: `Views/Car/CarLiveView.swift:442` (`Color.white`), `Views/Chat/ChatTabView.swift:834,839` (`Color.red`), `Views/Chat/QuestionCardView.swift:125,235` (`Color.blue`), `Views/HostProfilesView.swift:305` (`Color.red`/`Color.secondary`), `Views/Support/QRScannerView.swift:27` (`Color.black`). |
| POL-COLOR-09 | **FAIL** | 38 ad-hoc `.opacity(` call sites in Views (`grep -rEn "\.opacity\(" Views --include="*.swift"` → 38). |
| POL-COLOR-10 | **FAIL** | `DesignTokens.swift:36` `Semantic.info = (0.25, 0.47, 0.85)` = `#4078D9` — a second blue, distinct from `Brand.primary` `#3B82F6`. Used at `QuestionCardView.swift:125,235`. |
| POL-COLOR-11 | **FAIL** | `DesignTokens.swift:33` `Semantic.error = Color.red`; used at `MessageRowView.swift:648,651` for the error block that `design.md` §QT-PALETTE says must be accent + explicit text. |
| POL-COLOR-12 | **PARTIAL** | 3 red sites. `ChatTabView.swift:834,839` (recording mic) is sanctioned by §QT-COMPOSER. `HostProfilesView.swift:305` (failed diagnostic) is an error surface, which §QT-PALETTE assigns to accent, not red. |
| POL-COLOR-13 | **REVIEW** | Not machine-checkable. The session-indicator contract (`docs/features/session_row_indicator/design.md`) documents its own exception. Needs a per-screen screenshot review against the §QT-PALETTE status table. |
| POL-COLOR-14 | **FAIL** | `DesignTokens.swift:34` `Semantic.success` is green, and `Semantic.success`/`Semantic.warning` are referenced at 12 sites across the target. §QT-PALETTE requires a `text.secondary` checkmark with no green. |
| POL-COLOR-15 | **FAIL** | `DesignTokens.swift:35` `Semantic.warning = Color.orange`; §QT-PALETTE requires gold text with an explanation and no orange block. |
| POL-COLOR-16 | **PASS** | `DesignTokens.swift:27` `Brand.gold = (0.851, 0.651, 0.129)` = `#D9A621`, used at 4 sites, all in the session-indicator / permission-pending path. |
| POL-COLOR-17 | **PASS** | 0 matches for `\.linearGradient\|\.radialGradient\|Gradient\(` across the target. |
| POL-COLOR-18 | **PASS** | `DesignTokens.swift:211,213,215` = 6 / 12 / 16, exactly the spec's three radii. |
| POL-COLOR-19 | **FAIL** | 57 hardcoded numeric spacing values in Views (`grep -rEn "\.(padding\|spacing)\([^)]*[0-9]" Views \| grep -v DesignSpacing` → 57). |
| POL-TYPE-01 | **FAIL** | `DesignTypography` resolves to {20, 17, 17, 16, 12, 11, 11} pt — seven distinct sizes across six roles, with no 22 and no 13. The spec's four-step scale 22/16/13/12 is not implemented. |
| POL-TYPE-02 | **FAIL** | `DesignTokens.swift:121` `display = .title3.weight(.bold)` → 20 pt; spec wants 22 pt. |
| POL-TYPE-03 | **FAIL** | `DesignTokens.swift:127` `body = .body` → 17 pt; spec wants 16 pt. |
| POL-TYPE-04 | **PARTIAL** | `DesignTokens.swift:130` `bodyProminent = .callout` → 16 pt ✓ size, but the weight is regular; §QT-TYPE specifies Medium. |
| POL-TYPE-05 | **FAIL** | `DesignTokens.swift:133` `meta = .caption` → 12 pt; spec wants 13 pt. |
| POL-TYPE-06 | **FAIL** | `DesignTokens.swift:136` `micro = .caption2` → 11 pt and `:139` `microMono = .system(.caption2, design: .monospaced)` → 11 pt; spec wants 12 pt. |
| POL-TYPE-07 | **FAIL** | 11 literal `.system(size:)` sites: `CarLiveView.swift:722`, `ChatTabView.swift:964,1771,1794`, `MessageRowView.swift:664`, `SettingsTabView.swift:243`, `SessionListView.swift:35,48`, `ContentView.swift:232,305`, `FileContentReuseFixture.swift:110`, `FileSearchFixture.swift:239,245`. |
| POL-TYPE-08 | **FAIL** | 103 semantic system-font call sites vs 70 `DesignTypography.*` uses. |
| POL-TYPE-09 | **PASS** | No third-party font registration in the target; the only `.custom(` match is `SSHTunnelManager.swift:446`, an unrelated key-validator type. |
| POL-TYPE-10 | **FAIL** | The tokens use semantic system fonts, which scale, but they do not resolve to the mandated nominal sizes. Implementing an exact 22/16/13/12 scale *while* keeping Dynamic Type requires the D1 `Font.custom(..., relativeTo:)` form, which is not implemented (and per PRY-22 must be validated on a device first). |
| POL-TYPE-11 | **FAIL** | **The title is deliberately absent.** `MessageRowView.swift:687` reads `// No "OpenCode" speaker title — the user's blue left-bar vs the`. §QT-SPEAKER requires an `OpenCode` text title and no avatar, so the code contradicts the written spec — see Open Questions. |
| POL-TYPE-12 | **PASS** | The model caption is retained at the foot of each AI reply (`MessageRowView.swift` reply footer block). |
| POL-TYPE-13 | **FAIL** | 7 `.font(.system(size: 1))` probe hacks (`ChatTabView.swift:964`, `MessageRowView.swift:664`, `ContentView.swift:232,305`, `FileContentReuseFixture.swift:110`, `FileSearchFixture.swift:239,245`) and no `Utils/AccessibilityProbe.swift`. |
| POL-CARD-01 | **PASS** | All 8 `.stroke(` sites are on controls and rings, not on information cards: `ChatToolbarView.swift:125`, `ContextUsageView.swift:128,132`, `AIUsageQuotaView.swift:78`, `CarLiveMicrophoneMeter.swift:233-240`. |
| POL-CARD-02 | **REVIEW** | Needs per-element review of the tool card's icon / name / path / chevron against `Brand.primary`. Not machine-checkable today. |
| POL-CARD-03 | **PARTIAL** | `PermissionCardView.swift:22` stripe is 3 pt ✓, but `QuestionCardView.swift:43` is 4 pt ✗. §QT-CARD requires 3 pt on both action cards. |
| POL-CARD-04 | **REVIEW** | Turn-activity rows render as plain `text.secondary` lines with no container — confirmed by reading the status-row block; kept as a review row because there is no automated predicate. |
| POL-CARD-05 | **PASS** | Tool and patch cards use `DesignCorners.medium` (12 pt) at `MessageRowView.swift:769,955,999`. |
| POL-CARD-06 | **PASS** | `Views/Chat/ToolCardClassifier.swift:17` routes exactly `apply_patch, edit_file, write_file, read_file` (plus historical aliases at `:29`). |
| POL-CARD-07 | **PASS** | `MessageRowView.swift:31-32` builds `cardGridColumns` from `cardGridColumnCount`; the grid is used at `:703` with the documented 2-up / 3-up split. |
| POL-CARD-08 | **PASS** | The merged tile and its label exist: `Support/L10n.swift:918-919` (`"%d tool call"` / `"%d tool calls"`), rendered from `ToolPartView.swift`. |
| POL-CARD-09 | **PASS** | `MessageRowView.swift:782` documents the tile width as coming from the grid column; the tile is a grid child at `:703` and never stretches. |
| POL-CARD-10 | **PASS** | Text and attachment blocks sit outside the grid and render full width after it (`MessageRowView.swift:703` grid, then the full-width text blocks). |
| POL-CARD-11 | **PASS** | No `Files updated` / `Actions` category heading exists in the target. |
| POL-CARD-12 | **PASS** | No sprite or texture assets in the card layer; the implementation uses SF Symbols and vector shapes only. |
| POL-MESSAGE-01 | **FAIL** | `MessageRowView.swift:617-619` — `Rectangle().fill(DesignColors.Brand.primary).frame(width: 4)`. §QT-MESSAGE specifies 3 pt, and no `DesignSpacing.accentStripe` token exists. |
| POL-MESSAGE-02 | **PARTIAL** | The fill uses `DesignColors.Opacity.userMessageFill` (0.10 light / 0.14 dark, `DesignTokens.swift:82,84`), not the spec's `accent.muted` (accent at 8%). |
| POL-MESSAGE-03 | **PASS** | The AI reply body renders on `bg.primary` with no container, no fill and no stripe; the leading stripe appears only in the user-message branch (`MessageRowView.swift:615-619`). |
| POL-MESSAGE-04 | **PARTIAL** | `DesignTokens.swift:160` `messageVertical = 20` ✓ for iPhone; there is no 28 pt large-screen variant. |
| POL-MESSAGE-05 | **FAIL** | `DesignTokens.swift:162` `cardPadding = 12`; §QT-MESSAGE specifies 14 pt (iPhone) / 18 pt (iPad). |
| POL-MESSAGE-06 | **FAIL** | No horizontal-margin token; margins are among the 57 hardcoded spacing values. |
| POL-MESSAGE-07 | **FAIL** | No 720 pt content cap: every content block uses `.frame(maxWidth: .infinity, alignment: .leading)` (`MessageRowView.swift:568,634,648,692,731`). |
| POL-COMPOSER-01 | **PASS** | `ChatTabView.swift:1233` fills the field with `DesignColors.Neutral.composerDark`/`composerLight` and applies no stroke. |
| POL-COMPOSER-02 | **REVIEW** | Send is a solid accent rounded-rectangle hugging the field's bottom-right; confirmed visually in the existing fixture screenshots, but no automated predicate exists. |
| POL-COMPOSER-03 | **REVIEW** | The mic renders inside the field's leading edge in `text.secondary`; visual confirmation only. |
| POL-COMPOSER-04 | **PASS** | The send button is never removed by the running state — `stop` is added as an additional button above it in the same right-hand VStack. |
| POL-COMPOSER-05 | **PASS** | Send and stop are stacked in the right-hand VStack with send in the bottom slot and stop above it (`ChatTabView` composer action stack). |
| POL-COMPOSER-06 | **PASS** | Stop uses red for interrupt semantics (`ChatTabView.swift:834,839` use `Color.red` for the recording/stop affordance). |
| POL-COMPOSER-07 | **PASS** | The mic keeps a fixed bottom-left slot across voice states; the retry and discard actions occupy the same slot without moving send. |
| POL-COMPOSER-08 | **PASS** | During transcription and retry the transcript appends and the field auto-scrolls to the end; the manual-edit path keeps the system default. |
| POL-COMPOSER-09 | **PASS** | The forced scroll is applied only on the voice/retry path; the draft-restore and manual-edit paths do not force it. |
| POL-COMPOSER-10 | **FAIL** | `PermissionCardView.swift:42-69` and `QuestionCardView.swift` use `.buttonStyle(.plain)` text buttons with no 44 pt target. The precedent exists — `Utils/EffectiveLayout.swift:230` `minimum = 44` — but is not applied to these cards. |
| POL-MOTION-01 | **FAIL** | No entrance transition on a user message: `grep -rnE "transition\(\|\.transition" MessageRowView.swift` → 0 matches. |
| POL-MOTION-02 | **FAIL** | The system `DisclosureGroup` is still used at `ToolPartView.swift:90` and `TaskNotificationCardView.swift:29`. §QT-MOTION requires a custom spring (response 0.32, damping 0.82). |
| POL-MOTION-03 | **FAIL** | No slide-in entrance on the permission/question cards; no `transition` modifier on either card. |
| POL-MOTION-04 | **FAIL** | No session-switch crossfade on the message list. |
| POL-MOTION-05 | **PASS** | The streaming text path applies no entrance animation — streaming text renders directly. |
| POL-MOTION-06 | **PASS** | The process-tile header toggles without an animation; the grid reflows (`MessageRowView.swift:826` tile block). |
| POL-MOTION-07 | **FAIL** | `DesignTokens.swift:234` `gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)` — response 0.4 exceeds the 0.35 ceiling. |
| POL-MOTION-08 | **PASS** | No splash or launch animation in the app entry. |
| POL-MOTION-09 | **FAIL** | There is no `DesignMotion` layer at all (`grep -rn "DesignMotion"` → 0). Raw durations are used at `ChatTabView.swift:1616` (0.2), `SettingsTabView.swift:403` (0.28) and `:409` (0.25), `FileContentView.swift:494` (0.2) and `:521` (0.3), `ContextUsageView.swift:139`, `CarLiveMicrophoneMeter.swift:196`. |
| POL-MOTION-10 | **PARTIAL** | Reduce Motion is honoured at 13 sites (including the session indicator and the microphone meter), but none of the four missing motions exist yet, so the coverage cannot be complete. |
| POL-HAPTIC-01 | **PASS** | `Views/Chat/ChatTabView.swift` `sendCurrentInput()` fires `.messageSent` on the success branch of `state.sendMessage(...)`, passing `state.isMicrophoneCaptureActive`. |
| POL-HAPTIC-02 | **PASS** | `.permissionArrived` fires from `AppState.announcePermissionArrival(_:)`, reached from `AppState+SSE.swift` (`permission.asked`) and `AppState+Permissions.swift` (`refreshPendingPermissions`). Signature: `softImpact`. |
| POL-HAPTIC-03 | **PASS** | `.questionArrived` fires from `AppState.announceQuestionArrival(_:)`, reached from `AppState+SSE.swift` (`question.asked`) and `AppState+Permissions.swift` (`refreshPendingQuestions`). Signature: `mediumImpact`. |
| POL-HAPTIC-04 | **PASS** | `.sendFailed` fires in `Views/Chat/ChatTabView.swift` after the draft is restored. Signature: `errorNotification`. |
| POL-HAPTIC-05 | **PASS** | `.destructiveConfirmed` fires in `Views/SessionListView.swift` **after** the delete succeeds, so a failed delete does not feel like a success. Signature: `warningNotification`. |
| POL-HAPTIC-06 | **PASS** | `.selectionChanged` fires in `Views/SessionListView.swift` `selectSession(_:)`. Signature: `selectionChange`. |
| POL-HAPTIC-07 | **PASS** | `.recordingStarted` fires in `Views/Chat/ChatTabView+VoiceInput.swift` **before** the microphone opens, so the click lands ahead of the capture window; `.recordingStopped` fires after `stoppingMicrophone.stop()` completes, so the engine is already closed. Both pass the capture state as it is *outside* their own capture, so a simultaneous Ambient capture still suppresses them. The three other `isRecording = false` sites are cleanup resets and deliberately do not fire. Signatures: `rigidImpact` / `heavyImpact`. |
| POL-HAPTIC-08 | **PASS** | `DesignHapticEvent.isAllowed(reduceMotion:microphoneOpen:)` suppresses **every** event while the microphone is open — there is no blanket exemption. The guard cannot be bypassed: `DesignHaptics.fire(_:microphoneOpen:)` has **no default** for the flag, so every call site must state the capture state, and all of them pass the single authoritative `AppState.isMicrophoneCaptureActive` — which covers the Ambient/Car live-voice capture (`CarLiveController.isMicrophoneCaptureActiveForPolicy`, including the `captureStartPending` window that spans the `startCapture` await) and the chat composer capture (`AppState.chatSpeechCaptureActive`). Asserted by `DesignHapticsTests.microphoneGuardSuppressesEveryEvent`. |
| POL-HAPTIC-09 | **PASS** | The policy is written in `docs/design.md` §QT-HAPTIC: Reduce Motion drops confirming events and keeps alerting ones; silent mode affects nothing because the generators emit no audio. Asserted by `DesignHapticsTests.silentModeDoesNotAffectAnyEvent` and .reduceMotionKeepsAlertingEventsAndDropsConfirmingOnes`. |
| POL-STATE-01 | **PARTIAL** | The empty session list shows brand copy rather than "No sessions", but `docs/design.md` §QT-EMPTY asks for the **dark logo** asset and only `logo_light.png` ships. |
| POL-STATE-02 | **PASS** | `DesignTokens.swift:239` `breathing = Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)` — 3 s cycle ✓; the 1.0→1.02→1.0 amplitude is applied at the call site. |
| POL-STATE-03 | **PASS** | The empty chat shows centred guidance text with no icon. |
| POL-STATE-04 | **REVIEW** | A per-surface checklist, not a single predicate. Completed by the Phase 0 per-surface acceptance list in `rubric.md`. |
| POL-STATE-05 | **REVIEW** | Per-surface; the host-profile and composer surfaces already distinguish the failure path, the chat stream needs a check. |
| POL-STATE-06 | **PASS** | The pending-sync caption and the green/blue withholding rule are implemented and covered by `SessionIndicatorTests` / `SessionReadStateStoreTests` (43 targeted tests, `.occlient/test-runs/unit-20261014T045918Z-6I7UDt`). |
| POL-STATE-07 | **REVIEW** | The host-profile surface has an explicit disconnected state; the session list needs a check. |
| POL-ERROR-01 | **FAIL** | 2 user-facing sites surface a raw `localizedDescription`: `ChatTabView.swift:1730` (`attachmentError = error.localizedDescription`) and `ChatTabView+VoiceInput.swift:428` (`speechError = error.localizedDescription`). The other 31 occurrences are logger calls, which are fine. |
| POL-ERROR-02 | **PASS** | `docs/design.md` §QT-MOCKUP specifies the Basic Auth guidance copy, and the host-profile diagnostic path renders a mapped message rather than the raw error. |
| POL-ERROR-03 | **REVIEW** | Copy review per error surface; the user-message error block still uses a red background (see POL-COLOR-11) and so does not yet meet the two-part what-happened / what-next shape. |
| POL-ERROR-04 | **REVIEW** | Enforced by the mandatory privacy review at merge, not by an automated check. |
| POL-ERROR-05 | **REVIEW** | A process gate, evidenced by the independent code/privacy review records cited in `docs/WORKING.md`. |
| POL-A11Y-01 | **PASS** | Accessibility API usage is broad (239 occurrences across Views), and the accessibility-probe pattern at `MessageRowView.swift:664` shows labels are attached deliberately rather than incidentally. |
| POL-A11Y-02 | **PASS** | The composer activity text was restored specifically so the decorative light is not announced twice (`docs/WORKING.md`, 2026-10-14 entry). |
| POL-A11Y-03 | **PASS** | Covered by the UI assertions for the five row types with a ≤ 1.5 pt deviation (`docs/WORKING.md`, 2026-10-14 session-indicator follow-up). |
| POL-A11Y-04 | **PASS** | `DesignTokens.swift:170-175` define the 12→18 pt indicator column, the 6→9 pt gold/red and green/blue dots, and the hierarchy; the 44 pt chevron hit area is asserted in the UI tests. |
| POL-A11Y-05 | **REVIEW** | A manual on-device check at `accessibility3`, applied per surface by the per-surface acceptance list. |
| POL-A11Y-06 | **REVIEW** | A manual `zh-Hans` check per surface. Known risk: `SessionListView.swift:29` uses a fixed `width: 88` close button. |
| POL-A11Y-07 | **FAIL** | `SessionListView.swift:29` still uses a fixed `width: 88`. |
| POL-PREVIEW-01 | **FAIL** | Exactly one file in the target has a `#Preview` (`ContentView.swift:921`) against 16+ screen views. |
| POL-PREVIEW-02 | **FAIL** | Follows from POL-PREVIEW-01 — with one preview there is no suite isolation to audit. The isolation pattern is documented in `docs/tests.md`. |
| POL-PREVIEW-03 | **REVIEW** | The `Views/Support/` fixture set is credential-free by construction; each new preview must be checked against it at review time. |

## Counts

| State | Rows |
|---|---|
| PASS | 44 |
| PARTIAL | 9 |
| FAIL | 35 |
| REVIEW | 14 |
| **Total** | **102** |

| Family | PASS | PARTIAL | FAIL | REVIEW | Total |
|---|---|---|---|---|---|
| Family POL-COLOR | 5 | 3 | 10 | 1 | 19 |
| Family POL-TYPE | 2 | 1 | 10 | 0 | 13 |
| Family POL-CARD | 9 | 1 | 0 | 2 | 12 |
| Family POL-MESSAGE | 1 | 2 | 4 | 0 | 7 |
| Family POL-COMPOSER | 7 | 0 | 1 | 2 | 10 |
| Family POL-MOTION | 3 | 1 | 6 | 0 | 10 |
| Family POL-HAPTIC | 9 | 0 | 0 | 0 | 9 |
| Family POL-STATE | 3 | 1 | 0 | 3 | 7 |
| Family POL-ERROR | 1 | 0 | 1 | 3 | 5 |
| Family POL-A11Y | 4 | 0 | 1 | 2 | 7 |
| Family POL-PREVIEW | 0 | 0 | 2 | 1 | 3 |
| **All families** | 44 | 9 | 35 | 14 | **102** |

