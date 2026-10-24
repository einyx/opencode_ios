# Session Single-Lamp Status: mini PRD / RFC

Status: current product contract and iOS implementation notes, 2026-10-14. This document supersedes the earlier three-color dot scheme and the composer gold working-lamp rule; the supplemental parent-row blue reminder acknowledgment is described below. Android's implementation and acceptance are maintained independently in its own repository; this change was not synced there in this round.

## Goals And Display Contract

Users can scan a session row at any nesting level and spot requests that need attention, unacknowledged failures, executions that have not finished, and unread updates. The list and the status bar above the current chat composer use the same single-lamp semantics. A lamp expresses a fact known to the client; it does not prove that a task succeeded, keeps producing output, or that every real descendant has stopped.

| Priority | Lamp | Condition |
|---|---|---|
| 0 | none | The row is archived |
| 1 | yellow, solid | Itself or a known descendant has a genuinely pending permission or issue |
| 2 | red, solid | Itself or a known descendant has a source-level unacknowledged failure |
| 3 | green, breathing | Itself or any known descendant has a trustworthy, fresh busy / retry acknowledgment |
| 4 | blue, solid | The entire known subtree is confirmed inactive, and this row has a source-level unread reminder it has not acknowledged yet |
| 5 | none | None of the above signals exist, or the execution status is unknown |

The current session is exempt only from blue, not from yellow, red, or green. A session's own normal execution in the list is expressed by the lamp alone; Execution active / Running is no longer shown. When the list has active descendants, the count of all known active descendants is shown with a neutral `arrow.triangle.branch` icon plus a number; zero is not shown, and N descendants active / subagents running is no longer written. The list count is still preserved when yellow or red overrides green. Own retry keeps "Retrying", and unknown keeps "Status awaiting sync". busy may mean waiting on a tool, on I/O, or on the user, and must not be translated into making continuous progress.

The composer status bar does not add a descendant count, but green must not appear as an isolated lamp with no explanation. On iOS, in a trustworthy own-execution state, `runningTurnActivity.text` is reused first; when there is no turn, the existing activity tracker text that is still running is reused, such as Thinking, Running commands; tool types are never guessed in the new UI. When no activity is available, the fallback is "Agent working". When the session itself is not executing but known descendants are, the display is "Subagent running", without a number. Whether the session itself is currently executing comes from the same presentation's trustworthy `ownIsActive`; it must not rely on raw busy alone or reuse stale activity.

Explicit pending, failure, retry, and awaiting-sync wording takes priority over ordinary activity descriptions; when needed, voice status is merged into the same text and identical fragments are de-duplicated. When an activity description already exists, a second synonymous "running" sentence is no longer appended. When the text already carries status semantics, the composer's decorative lamp is not repeated in the screen-reader label. The existing background-task navigation is kept as a clickable target title, without stacking counts on top of it. The screen-reader name of the list branch count remains the full localized description (for example "2 descendants active").

A useful short activity description is different from the redundant long sentences removed earlier: it explains whether the agent is currently thinking, calling tools, or waiting for a retry; it does not restore Execution active · N descendants active, and it does not change the compact list contract. The iOS composer additions above come from real-device acceptance feedback and do not require changes to the other already-accepted platforms.

Without a trustworthy status, the lamp does not fall back from green to blue: a colorless lamp with a gray "Status awaiting sync" is shown. Yellow and red reminders are still kept, with the sync hint appended. One confirmed active source is enough to light green; when another branch is unknown, the awaiting-sync hint is shown at the same time.

## Content Read State And Parent-Row Reminder Acknowledgment

For the problem where opening parent session P while child session C/D still has unread blue immediately turns the parent row blue again after switching away, a minimal local fix has landed that separates content read state from parent-row reminder acknowledgment. The session source's own `lastViewedAt`, `failedAt`, and the original unread predicate stay unchanged: an unread candidate is produced only when the `updated` time is later than the source's viewed time and the source is idle or its status is missing; a missing status only qualifies as a candidate, and the final display still requires a trustworthy status. The blue-lamp decision filters per source first, then aggregates upward along the known parent chain with cycle protection.

```text
ownFailure[s] = failedAt[s] > lastViewedAt[s]
ownUnread[s]  = updatedAt[s] > lastViewedAt[s], and the source is idle or its status is missing (display still requires a trustworthy status)
ownPending[s] = number of currently unresolved requests belonging to s

First filter the sources, then let valid sources contribute to themselves and to all known ancestors R.
Blue is skipped for R only when R != s and blueAckBySource[R][s] == the current positive updated token.
Keep propagating to higher ancestors; an ancestor's own lastViewedAt does not filter child sources.
```

Each row gains a persisted mapping `blueAckBySource[sourceID]` that records the positive `time.updated` integer token that was accepted at acknowledgment time. A source's blue reminder is suppressed on the current ancestor row only when the value recorded in that mapping is exactly equal to the source's current version; this suppression does not apply to the source itself and does not block the unread signal from propagating to higher ancestor rows. Neither a whole-subtree max nor a local now is used as the ACK threshold. A parent row having no blue no longer means that all descendant content has been read.

`selectSession` is the only new acknowledgment entry point: it synchronously captures and submits the known source version snapshot at that moment, and only when the target row actually shows blue and `needsSync == false`. The capture happens before `markViewed`, the current switch, and the async load kickoff. Capture and storage complete in the same MainActor call, with no await in between, so acknowledgment cannot be delayed onto another host; async load callbacks never write ACKs. The persisted mapping does not include self, and a source's own read state still goes through the existing mechanism. For example, after P acknowledges `[C: 100, D: 200]`, when C produces a new version 101, P can still turn blue again, and the parent's own new data is not masked by a child session's ACK.

When a new version of C arrives while P is current, that version is not acknowledged; exiting, `onDisappear`, and reselecting the current row when it shows no blue add no descendant acknowledgment. Yellow, red, green, unknown, and archived non-blue states never acknowledge descendants as a side effect. After viewing a grandchild session, its red/blue source contributions to the parent and grandparent disappear at the same time; sibling sources and the parent's own contributions are kept. Viewing the parent only marks the parent's content as read and acknowledges the blue reminder the parent row was showing at that moment; it does not replace viewing descendants and does not acknowledge the grandparent row. Expanding/collapsing neither acknowledges nor stops execution; cold-start auto-selection does not auto-acknowledge.

At the storage layer, `blueAckBySource` is an optional dictionary that defaults to empty when missing; `lastViewedAt` and `failedAt` in legacy JSON are preserved, and child acknowledgments are not backfilled. Data stays in the device-local host-profile namespace and does not cross devices. Temporarily evicting a row due to list pagination does not clean this mapping; when an existing definitive delete entry removes a row, the references to that source from every row are also cleared, even when the source has no record of its own. Space cost is O(actual acknowledged rows × sources); the derived computation is O(N × depth). No server, message ledger, or new content protocol is required.

Compatibility boundary: this approach keeps the historical local-clock dependency on source-level `updated > lastViewedAt`, so the ACK only fixes the parent-row aggregate reminder and does not guarantee that any new message turns the row blue. Two content changes with the same updated value cannot be distinguished, and a metadata time update may introduce an extra reminder; old snapshot acceptance keeps using the existing sync logic and does not fix clock rollback. This round does not include the self-version migration or stable message revision mechanism from the stronger design proposal.

A failed source is currently still the received `session.error`: it is staged first, then confirmed as failed on idle; subsequent busy/retry can clear a staged error that has not been committed. An already committed `failedAt` is not removed by a later clean busy→idle, retry→idle, repeated idle, or a REST snapshot; a reminder is acknowledged only against the source's own `lastViewedAt`. A received error that has not yet reached idle is preserved across a disconnect on the same host; switching hosts clears it. `AbortError` does not create a new failure and does not clear an old failure through an active stop.

Archiving only hides that row's lamp; it sends no abort and cancels no pending request. An archived source can still affect unarchived ancestors; archiving must not be used to mask a real request.

## Status Trustworthiness And Sync

The live value, the source catalog, and "still trustworthy" are stored separately. Each source's catalog comes from SSE `event.directory`, loaded metadata, or the request directory of a successful snapshot. It is trustworthy when acknowledged within 60 seconds and the connection is valid; heartbeats do not refresh a source's acknowledgment time. A first `nil` is unknown and must not be interpreted as completion. Only a complete status snapshot from the same host and same project can confirm a missing item as idle. Unknown status strings are not treated as idle.

`GET /session/status` explicitly carries the current project directory. The host, directory, and per-item SSE revision are captured when the request starts and re-validated before the response lands. Any SSE for the same item received during the request, including a busy/idle with the same value, increments the revision, and an old snapshot must not overwrite it. The snapshot confirms the loaded IDs of the current directory, the unknown IDs recorded in the same scope, and the returned IDs; the status of other projects is not cleared because of missing items. Only an unknown active source in the same scope and fresh state conservatively blocks blue; an old busy from an external project must not globally veto the current tree. Without a trustworthy directory, no missing-item inference is made, and unknown items without a source directory are not attributed to all projects.

When the list/sidebar/chat is visible and in the foreground, the existing sync entry point requests immediately and then confirms every 30 seconds, with multiple surfaces sharing a single in-flight request and an approximately 30-second dedupe window. A lightweight expiry task that does not depend on a network await advances the evaluation moment every 5 seconds, so even if the status / pending GET stalls, the 60-second acknowledgment becomes unknown at the next tick (at the latest roughly 65 seconds later, depending on main-thread scheduling). This task issues no network requests and does not recompute frame by frame. Moving to the background cancels visible tasks and invalidates old acknowledgments; reconnecting fetches a fresh snapshot. A failure does not write idle and does not update the acknowledgment time.

Reconnecting refreshes the global permissions/questions even when there is no current session. A disconnect or a new connection epoch disqualifies old GETs and releases their logical in-flight slots; already displayed pending items are not cleared until a new snapshot succeeds. The two request types use UUID ownership plus host and revision guards; old responses and old defers must not overwrite new results or clear new slots. An asked/resolved SSE or a successful local reply also invalidates the old snapshot. A non-2xx HTTP response for a permission reply must throw and keep the pending item; the current compatibility interface further requires HTTP 200. Viewing, idling, and closing the request UI never resolve a request.

## Visual And Accessibility

The lamp column sits beside the full text block (a VStack of title, time, and runtime sub-text) and is vertically centered by layout — not aligned only to the title row, and without absolute y offsets. The collapse chevron, the 44pt touch target, indentation, and hierarchy markers are preserved, and no second lamp position is added. The composer lamp lives inside the existing status bar above the input field, and the stop menu still controls only the current session instead of expanding to stop a whole tree.

| Role | Default diameter / Dynamic Type cap | Color value |
|---|---|---|
| running | 6 / 9pt | dedicated token: light `#167C45`, dark `#4CBF82` |
| unread | 6 / 9pt | brand blue `#3B82F6` |
| needs-you / failed | 8 / 12pt | gold `#D9A621` / dedicated failure red `#E5484D` |

Platforms may adopt different optical sizes: iOS keeps green and blue at 6pt and yellow and red at 8pt; Android's current product spec is green and blue at 5dp and yellow and red at 6dp. Semantics, whole-block text centering, breathing amplitude, and period are consistent, and Android's smaller sizes must not be mechanically applied to iOS.

The green lamp's full cycle is 2.6 seconds, with opacity varying smoothly between **0.40–1.0**; it does not blink off, scale, move, or get a glow. This amplitude replaces the initial 0.75–1.0. The phase is aligned to a shared clock, and the Core Animation layer handles per-frame drawing without driving SwiftUI to re-aggregate the tree. It is destroyed offscreen and paused in the background; with Reduce Motion it is 100% solid. Yellow, red, and blue have no looping animation.

The light green is unified to `#167C45` according to the user's preference from on-device comparison, replacing the deliberately darker `#14733F` of the first version; it is no longer darkened on its own to chase the old 3:1 trough target. The 0.40 breathing trough cannot be claimed to meet 3:1 across the full cycle; the confirmed amplitude is kept, along with the text and full screen-reader semantics. The lamp gains no new tap target or focus; the entire row is merged for screen readers. Status must not be conveyed by red/green difference alone.

## Implementation Touchpoints And Complexity

`AppState.sessionIndicatorPresentations` computes source acknowledgments, descendant execution counts, the unknown aggregate, and the final lamp/summary dictionary at each rendering boundary, then passes them to all rows. It rolls up along the loaded parent chain with cycle protection, with a complexity of O(sessions × known depth); re-walking all sessions per row is not allowed. The iPhone list, the iPad sidebar, and the composer share this derived logic and `SessionIndicatorDot`.

Status and concurrency guards are centralized in `AppState+SSE.swift`, `AppState+Sessions.swift`, and `AppState+Permissions.swift`; switching hosts cleans up acknowledgment times, revisions, request ownership, and abort markers at the existing reset boundary. No server-side state framework was added.

## Acceptance And Scope Limits

Unit tests cover source-level parent/child, multi-level, and sibling relationships plus the parent's own acknowledgment, the summary when yellow/red overrides green, the last descendant finishing, the current session's blue exemption, unknown→snapshot confirmation, disconnect/expiry, same-value SSE and old snapshots, late responses across hosts, reconnect with pending and no current session, an old snapshot after resolve, and the breathing/Reduce Motion/offscreen policies. The UI uses `UITEST_SESSION_INDICATOR_FIXTURE`, containing only synthetic sessions; screenshots use real rows and the real composer.

The parent-row acknowledgment regression is verified through the real `selectSession`: P opened → switching away does not repeat blue, the child is still unread, only P is acknowledged and not the grandparent/child, viewing a source clears each ancestor's contribution, a sibling's out-of-order new token, reloading after pagination and fetching a new child, the parent's own new data, exiting during a current session without swallowing a new version, and non-blue states not acknowledging. Storage tests cover legacy JSON, host isolation, and deleting references. See this round's record in `docs/WORKING.md` for the concrete run results; device deployment acceptance was not replaced by unit tests.

The composer activity text has separate targeted tests: reusing a concrete activity, the no-activity fallback, descendants-only execution, rejecting stale activity, retry/pending/failure taking priority, and voice merging. A tool with no ActivityTracker mapping can only show the existing tracker fallback or Agent working; the activity text is a currently observed signal, not a guarantee of continuous progress or task success.

The known parent chain comes from loaded session metadata. When an unknown active ID in the same scope and fresh state cannot be attributed, blue is conservatively blocked and a sync hint is shown, which converges when a later complete snapshot reports it missing; descendants that are missing, were never loaded, or have an unknown source scope cannot be guaranteed to be fully covered. Neither the absence of a lamp nor blue means global server-side success. No request is sent per row, and no new full ancestor backfill was added.

Failures that were completely missed while offline cannot be recovered from status alone; historical Message.error or task receipt errors have not yet been added to the failure table. A pending snapshot may be discarded repeatedly during sustained high-frequency events, and only the next successful stable snapshot converges fully. Visual screenshots cannot prove a human's subjective sense of a 15-row dynamic load; on-device acceptance and device deployment are separate follow-up steps.
