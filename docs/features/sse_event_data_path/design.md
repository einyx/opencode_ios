# SSE Event Data Path Design (SSE as the data path for message state)

Status: implementation ready (step 2 investigation done, all file:line based on master `3c603dc` and opencode-official `71927c2d05`, ready to start)

## 1. Bottom Line

The iOS client currently "uses SSE as a doorbell and relies on REST to tell the truth": every message-related SSE event throws away the full data carried in its payload and instead triggers a full REST refetch (`loadMessages` + `loadSessionDiff`), and those `await`s queue up inside the same serial event loop. For an ordinary turn with N=3 steps and M=2 tools per step, the static count is **42 REST pairs (84 fetches) serially blocking the event loop** (formula `N×(8+3M)`, verified line by line against the source — see the end of "Current Client Inventory"). The perceived result: while a tool is running, the UI does not move until the REST snapshot comes back.

The server puts the data inside the event payload (verified both from the native OpenCode server source and by live measurement): `message.part.updated` carries the complete part (the tool's `state.status/input/output/time`), `message.updated` carries the complete message info, `message.part.delta` carries streaming text deltas, `server.heartbeat` fires one frame every 10s.

The design has three parts:

1. SSE as the data path: event payloads are upserted straight into MessageStore, zero RTT, rendering happens as soon as the event arrives. Payload completeness gate: when fields are missing (e.g. the thin part shape of the dsh shim), fall back to the current REST path so behavior stays identical to today.
2. REST demoted to reconciliation: per-event REST goes to zero; fetching happens only on bootstrap (reconnect), at turn end (`session.status -> idle`), on manual refresh/switch, or when the watchdog fires. REST per turn drops from 42 pairs to 1-2.
3. Heartbeat watchdog: `server.heartbeat` is a 10s frame guaranteed to exist on `/global/event` (it is also sent during long tools, verified in the source). The client checks the silence duration every 5s; >20s (two missed heartbeats) triggers one reconciliation. This replaces polling-based silent-death recovery; on compatible hosts without heartbeats it degrades to a 20s low-frequency reconciliation, with no degradation in behavior.

* **Explicitly out of scope**: 2s busy polling (a user pain point, not introduced), optimistic busy on send (sub-second cosmetic, skipped), tile visual upgrade (separate P2), server-side changes (zero).

## 2. User-Visible Problem and Root Cause

Observation: on Android you can see the running tool plus a timer; on iOS the UI does not update while a tool runs, and everything shows up at once when it finishes.

Root cause chain (all with file line numbers, master):

1. **SSE used as a doorbell**: the `message.part.updated` handler (`AppState+SSE.swift:132-155`) calls `messageStore.applyMessagePartUpdate` (`MessageStore.swift:154-169`), which only does a `recordPartType` tally, **never touches the payload**, and returns `.finalized` directly → `await loadMessages() + await loadSessionDiff()` (:149-155). The fully parsed part object is thrown away.
2. **Serial event loop + head-of-line blocking**: inside the `for try await` loop of `connectSSE` (`AppState+SSE.swift:9-39`), `await handleSSEEvent(event)` (:28), and the message event handler internally `await`s REST round-trips — one slow REST call stalls every subsequent event.
3. **No silent-death recovery**: backoff reconnect (`min(30, 2^attempt)`, 2s→4s→8s→16s→30s cap, :33-36; after a successful reconnect it runs `bootstrapSyncCurrentSession` :26) only handles "the connection dropped". When the connection is alive but no frames arrive (proxy buffering drops frames), the UI stays frozen at its last state. (Note: iOS currently has **no** busy polling and no other recovery path.)

4. **UI-layer gap** (independent of the data path): **the current UI still cannot surface a tool's running state** — the tool card lives in a collapsed `ToolCallsRowView` (`MessageRowView.swift:754-796`), with no per-tool running visual inside the row (no header spinner, no explicit running marker); the composer status line text depends on `session.status`'s `status.message` and an ActivityTracker derivation (`ActivityTracker.swift:74-97`), so its quality depends on the server's wording. The data path is therefore a **necessary but not sufficient** condition for "the user can see the tool running": this feature solves data timeliness, while the visual presentation of the running state must be filled in by the P2 tile feature (5.7). Before P2 lands, the improved experience = the composer line appears promptly (busy) and the collapsed tool row updates promptly, but there is still no explicit running indication inside the row.

* Android comparison (see the Android-side plan): same doorbell architecture + 400ms debounce + 2s busy polling + in-memory streaming text. This design swaps the data source for the payload itself and replaces polling with a watchdog; the same design is ported on the Android side with polling removed.

## 3. Server Event Contract (native OpenCode server)

Source: `opencode-official` (upstream dev `7945de2089` + 1 private commit `71927c2d05`; the private patch only changes the runner scope of run-state and two schema definitions, and **does not affect any of the contracts below**). Live measurement timeline: taken from the probe of the `session_status_bar` feature (`tmp/status_bar_probe.py`, 4096 live server, 2026-09-30; that feature's docs live in the opencode_ios_client main checkout and did not enter this branch — the timeline is inlined below, so this document is self-sufficient).

### SSE Endpoints

The server mounts `/event` (instance level, filtered by directory), `/global/event` (global, unfiltered), and `/api/event` (the V2 surface, 256-capacity dropping queue) at the same time. **iOS subscribes to `/global/event`** (hardcoded in `SSEClient.swift:57-58`; `APIConstants.sseEndpoint` is a dead constant).

- `/event`, `/global/event`: one `server.heartbeat` every ~10s (an independent `Stream.tick("10 seconds")` inside the handler, `handlers/event.ts:63-66`, `handlers/global.ts:35-38`; **it does not depend on any session/instance state**, so it keeps firing while idle or during long tools); the first frame of a new connection is `server.connected` (`properties: {}`); the unbounded queue never drops frames; events of the same session keep FIFO order (single-process serial notify + the same session comes from the same runLoop fiber).
- `/api/event`: the heartbeat is a 15s SSE comment frame (not a `server.heartbeat` event); encoding v1 live events (`session.status`/`message.part.delta`) fails (measured with a schema encoding probe), and a pure `cli serve` process mounts only this endpoint. **The iOS client does not subscribe to this endpoint and it is out of scope for this design**; if a host only has `/api/event` (pure `cli serve`), the current client already cannot connect, so that is out of scope.
- dsh shim host: iOS can connect to the shim from multiple hosts (usable today ⇒ the shim provides a working `/global/event`); whether the shim sends `server.heartbeat` is **unverified** — the watchdog degrades to a 20s low-frequency reconciliation on hosts without heartbeats (see 5.6), with no degradation in behavior.

### Event Table (client-relevant, payload shapes verified)

| Event | properties | Key facts |
|---|---|---|
| `session.status` | `{sessionID, status: {type: busy\|idle\|retry, ...}}` | Within one turn there are roughly `2N+1` busy frames (loop head + one process head per step, `prompt.ts:1089`, `processor.ts:653`); **`idle` is sent only once, at the end of the whole turn** (Runner.onIdle, `run-state.ts:48-51`), and does not alternate in the gaps between steps ⇒ `busy→idle` can serve as the turn-end signal |
| `message.updated` | `{sessionID, info: <complete message info>}` | Each step's new assistant message gets a new `msg_` id (`prompt.ts:1190-1201`): one frame at step start + one frame at step end (`processor.ts:470`, with no `time.completed` at that point). Whether a turn-level final completion frame exists is unverified (pending live measurement; it does not affect the design — reconciliation is the backstop) |
| `message.part.updated` | `{sessionID, part: <complete part>}` (published by `updatePart`, `session.ts:637`, a full `structuredClone`) | tool state machine: `tool-input-start` creates pending → `tool-call` (arguments complete) switches to running and writes `time.start` → `tool-result` switches to completed and writes `time.end` (`processor.ts:216-253, 331-351, 160-184`). Each step has a fixed 6 frames + 3 frames per tool (step-start/reasoning×2/text×2/step-finish; tool pending/running/completed) |
| `message.part.delta` | `{sessionID, messageID, partID, field: "text", delta}` | Emitted in only two places, text (`processor.ts:513-524`) and reasoning (`:294-306`), and `field` is always `"text"`; **the order start (a part.updated with empty text) → delta* → end (a part.updated with complete text) is guaranteed**; a delta is a live, non-durable event; the end frame is an idempotent convergence frame (dropped deltas can be backstopped by the end frame, but there is no explicit drop signal) |
| `message.part.removed` | **only `{sessionID, messageID, partID}`, no part object** | Trigger points: revert cleanup (`revert.ts:101-124`, before prompt/shell/summarize) + the `DELETE` message/part HTTP endpoints. An edit does not emit removed |
| `message.removed` | `{sessionID, messageID}` | Same as above |
| `session.updated` | `{sessionID, info: <complete session including cumulative tokens/cost>}` | `Session.touch()` on every step completion; iOS already upserts it locally today and triggers no REST |
| `server.connected` / `server.heartbeat` | `properties: {}` | Ordinary data frames on `/global/event`; the current iOS handler only handles connected (`AppState+SSE.swift:55-56`), and heartbeat falls into `default: break` (:193) and is dropped |
| subagent | — | Child session events carry the **child sessionID** and share the same bus as the parent events (the client splits by sessionID); task part events of the parent session carry the parent sessionID, stay `running` during execution, and `state.metadata.sessionId` already points at the child session (`task.ts:185-195`). iOS today only handles events for currentSessionID — keep as is |

Live timeline (facts verified by session_status_bar; cited again instead of re-running the probe):

```text
t+0.0s  session.status=busy
t+1.2s  message.part.updated tool=bash status=pending→running→completed (three frames pushed independently)
t+1.3s  step-finish part carries tokens; session.updated pushes the cumulative total
t+2.5s  session.updated; session.status=idle
```

## 4. Current Client Inventory (iOS, master `3c603dc`, all file:line re-verified)

| Location | Current state |
|---|---|
| `AppState+SSE.swift:9-39` | `connectSSE`: reconnect loop + backoff (2s start, 30s cap) + `bootstrapSyncCurrentSession` after reconnect; serial `for try await` + `await handleSSEEvent` |
| `AppState+SSE.swift:57-76` | `session.status` handler: busy/idle/retry only update `sessionStatuses` + `updateSessionActivity`, **no REST is triggered** (a unit test asserts `messagesCallCount == 0`) |
| `AppState+SSE.swift:107-118` | `message.updated` → `await loadMessages() + await loadSessionDiff()` |
| `AppState+SSE.swift:119-131` | `message.part.delta` → only `recordVisibleToken` (throughput), does not update the text |
| `AppState+SSE.swift:132-155` | `message.part.updated` → `applyMessagePartUpdate` (always `.finalized`) → `await loadMessages() + await loadSessionDiff()` |
| `AppState+SSE.swift:193` | `default: break` (`server.heartbeat` is dropped here) |
| `AppState+SSE.swift:393-395` | `applySSEEventForTesting`: thin pass-through to `handleSSEEvent` (test entry point) |
| `MessageStore.swift:9-17` | `@Observable final class MessageStore`: `messages: [MessageWithParts]` (only a wholesale replacement path), `partsByMessage: [String: [Part]]` (**written but never read on the app side**, only read by tests) |
| `MessageStore.swift:11-14, 154-169` | `MessagePartUpdateOutcome { .ignored, .finalized }`; `applyMessagePartUpdate` only does a `recordPartType` tally |
| `MessageStore.swift:21` | `pendingOptimisticMessageIDs` (reconciliation of optimistic user rows is pure id membership) |
| `Models/Message.swift:254-264` | `MessageWithParts { info: Message, parts: [Part] }`, neither Equatable nor Identifiable; `Part` is Identifiable by `id` |
| `AppState+Messages.swift:22-90` | `loadMessages`: `GET /session/{id}/message?limit=20` + stale guard + optimistic merge (id membership, keep-latest = the server version overwrites the temp parts) + rebuild of `partsByMessage` + `refreshSessionActivityText` while busy (2.5s debounce) |
| `AppState+Messages.swift:152, 209-211` | optimistic user row: deterministic `msg_<uuid>` (`makeServerID`, the reconciliation basis since commit c9c0be8), sent to the server along with the prompt |
| `AppState+Messages.swift:213-269` | `appendOptimisticUserMessage`: temp text part id `temp-part-<messageID>` + temp file parts |
| `AppState+Messages.swift:119-135` | `loadSessionDiff`: `GET /session/{id}/diff` |
| `AppState.swift:878-888` | `shouldProcessMessageEvent` (event entry guard, lets through events without a sessionID) / `shouldApplySessionScopedResult` (stale guard for REST results). `message.part.updated/delta` use an inline `sessionID == currentSessionID` (SSE:124,134) plus one more layer inside `applyMessagePartUpdate` |
| `SSEClient.swift:52-137` | subscribes to `baseURL + /global/event`; parses byte by byte into lines, drops `:` comment frames, decodes `data:` frames as JSON into `SSEEvent{directory, payload{type, properties}}`; heartbeat/connected are ordinary data frames (the parsing layer does not special-case them) |
| `ChatTabView.swift:563-588` | the message list is not lazy (ScrollView+VStack+ForEach), identity = group id (`assistant-<joined msg ids>`); today a single part change can only propagate through a wholesale replacement of `messages` |
| `SessionFlowTests.swift:1339-1697` | all SSE unit tests live in `AppStateFlowTests`; harness = `makeSSEEvent(JSON)` + `applySSEEventForTesting`; **REST count assertions already exist** (`MockAPIClient.messagesCallCount`/`sessionDiffCallCount`, TestDoubles.swift:98/116) |

Static REST count per turn (per-event trigger points checked line by line):

```
loadMessages calls per turn ≈ N × ( 2(message.updated) + 6(step-start + reasoning×2 + text×2 + step-finish) + 3M )
                        = N × (8 + 3M)   (loadMessages and loadSessionDiff each contribute this much, all serially awaited)
Example: N=3, M=2 → 42 pairs (84 fetches). The dsh shim host is worse: during a streaming tool input it pushes one part.updated frame per chunk, adding one pair each.
```

## 5. Design

### 5.1 Event → apply Specification

| Event | Current | After the change |
|---|---|---|
| `message.part.updated` | full REST | decode `properties.part` → `MessageStore.upsertPart` (in place, zero RTT); **if the gate does not pass → fall back to the current REST path** (see 5.2). Keep the `recordVisibleToken`/`recordStepFinish`/`recordPartType` tallies |
| `message.updated` | full REST | decode `properties.info` → `MessageStore.upsertMessageInfo` (upsert by id, keeps local parts); keep `recordStepStart`; user message confirmation → `untrackPendingOptimisticMessage` |
| `message.part.delta` | throughput only | append to the local part.text by partID (in-memory streaming); throughput is kept |
| `message.part.removed` | `default: break` | delete the part by `{sessionID, messageID, partID}` |
| `message.removed` | `default: break` | delete the row by `{sessionID, messageID}` |
| `session.status` | local status update, no REST | unchanged; **`idle` additionally triggers one reconciliation** (`loadMessages` + `loadSessionDiff`, new behavior) |
| `session.updated` / `permission.*` / `question.*` / `todo.updated` / `session.error` | light events | unchanged |
| `server.connected` | bootstrap poll | unchanged |
| `server.heartbeat` | dropped by `default: break` | explicit case, no action (the timestamp is refreshed uniformly at the `handleSSEEvent` entry, see 5.6) |

General rules:

- **sessionID gating unchanged**: message-level events only handle `currentSessionID` (the existing `shouldProcessMessageEvent` / inline comparison positions stay put).
- **Idempotency**: upsert by ID, safe under duplicates and out-of-order delivery (a part arriving before its message → shell row, see 5.3; the server keeps FIFO order for events of the same session).
- **stale guard**: events are processed synchronously (no "sent → returned" window), so the existing inline `== currentSessionID` check acts as the guard; nothing new is needed.

### 5.2 `MessageStore` upsert Implementation Specification

New methods (all in `MessageStore.swift`, near `applyMessagePartUpdate`):

```swift
// Returns .applied (updated in place) / .needsReconcile (gate not passed, caller falls back to REST) / .ignored (sessionID mismatch, etc.)
enum PartUpsertOutcome { case applied, needsReconcile, ignored }

func upsertPart(_ part: Part) -> PartUpsertOutcome // the shell row's time uses local time (5.3)
func upsertMessageInfo(_ info: Message)            // keeps local parts; creates a shell row if the row does not exist
func removePart(messageID: String, partID: String)
func removeMessageRow(messageID: String)           // also clears the matching partsByMessage key in sync
```

Handler-side skeleton — the `message.part.updated` branch (`AppState+SSE.swift:132-155`):
the existing sessionID gate + tally block (:133-148, `recordVisibleToken`/`recordStepFinish`) is kept as is;
the `applyMessagePartUpdate` switch at :149-155 is replaced with the following. Note that today's switch sits **outside** the gate block (`applyMessagePartUpdate` does its own sessionID check internally), while the new code makes `part.sessionID == currentSessionID` an explicit gate:

```swift
if let partObj = props["part"]?.value as? [String: Any],
   let data = try? JSONSerialization.data(withJSONObject: partObj),
   let part = try? JSONDecoder().decode(Part.self, from: data),
   part.sessionID == currentSessionID {
    switch messageStore.upsertPart(part) {
    case .applied:
        break // zero REST
    case .needsReconcile:
        await loadMessages()
        await loadSessionDiff() // gate fallback = current path
    case .ignored:
        break
    }
} else {
    // part missing / decode failure: today's precondition for .finalized is "partObj has messageID+id and sessionID matches",
    // a decode failure means the id may be missing, and today's behavior is .ignored (no REST); doing a REST here is a slightly stricter, safe direction
    await loadMessages()
    await loadSessionDiff()
}
```

**Also delete** the `applyMessagePartUpdate` method and the `MessagePartUpdateOutcome` enum (`MessageStore.swift:11-14, 154-169`). Its internal `recordPartType` tally moves into the handler tally block — call the existing method `messageStore.recordPartType(sessionID:partID:type:)` (`MessageStore.swift:107-112`) directly; first write wins, and the delta's partType determination depends on it.

Handler-side skeleton — the `message.updated` branch (reworked from `AppState+SSE.swift:107-118`):

```swift
case "message.updated":
    let eventSessionID = props["sessionID"]?.value as? String
    if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
        if let infoObj = props["info"]?.value as? [String: Any],
           infoObj["role"] as? String == "assistant",
           let assistantID = infoObj["id"] as? String,
           let sessionID = eventSessionID {
            messageStore.recordStepStart(assistantID, sessionID: sessionID) // kept
        }
        if let infoObj = props["info"]?.value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: infoObj),
           let info = try? JSONDecoder().decode(Message.self, from: data) {
            messageStore.upsertMessageInfo(info) // 5.2 semantics (including user message untrack)
        } else {
            await loadMessages()
            await loadSessionDiff() // info missing / decode failure = current path
        }
    }
```

* `upsertPart` semantics:

1. **Gate (payload completeness)**: a tool part must carry a decodable `state` (the dual shape of `PartStateBridge` is already supported); a text/reasoning part must carry a `text` field. If that is not satisfied (e.g. the thin part of the dsh shim + a top-level delta) → return `.needsReconcile` and the handler falls back to the current `await loadMessages() + await loadSessionDiff()`. The gate makes multi-host compatibility automatic: the shim takes the old path, the native server takes the data path.
2. **Row lookup**: find the `messages` row by `part.messageID`.
   - Row exists: replace-or-insert by `part.id` inside `parts` (a replacement keeps the original position — the server pushing the same part id multiple times is a state update, not a new part; an insertion appends at the end).
   - Row does not exist: decide by the part type (see the shell row rules in 5.3).
3. **Optimistic temp-part deduplication** (key edge case): the row is a pending optimistic one (id ∈ `pendingOptimisticMessageIDs`) and the incoming part id does not have the `temp-` prefix → first remove all `temp-` prefixed parts of that row, then insert the incoming part. This avoids showing a server user part event side by side with an optimistic temp part.
4. **Rebuild `partsByMessage` in sync** for that row (the app side writes but never reads it, but both `removeMessage`/`appendOptimisticUserMessage` maintain it, so keep it consistent; tests read it too).

* Decoding: use the existing example (`AppState+SSE.swift:58-61`) to convert `properties["part"]?.value` to JSON → `JSONSerialization.data(withJSONObject:)` → `JSONDecoder().decode(Part.self)`. On failure → `.needsReconcile`.

The meaning of `upsertMessageInfo` is: if the message already exists, replace it with the new `info` (note: the `parts` field is not updated here, because `message.updated` carries no `parts` information — `parts` come from the `part` events and from reconciliation); if the message does not exist, insert a shell row (empty `parts`). For a user message that is currently in the `pending optimistic` state, replace the `info` and run `untrackPendingOptimisticMessage(id)` (consistent with the id membership semantics in `loadMessages`: when the server confirms the message with that id, it is added to the `pending` set, but `parts` still stays at the temp version until reconciliation completes — see the known trade-off in 5.8).

### 5.3 Shell Row Rules (a part arrives before its message)

**Note**: in the normal flow there is never a case where "the server sends `message.updated` first for each step (creating the assistant message, `prompt.ts:1201`) and only then the part events", and the same session is FIFO. If this happens, it means either a reconnect missed the `message.updated`, or the messages arrived out of order. Rules:

- part type ∈ {`tool`, `reasoning`, `step-finish`, `patch`} (assistant only) → create an empty row: `Message(id: part.messageID, sessionID, role: "assistant", time: local time, all other fields null)`, and append the part at the end. The empty row must be able to be naturally overwritten by a later `upsertMessageInfo` / `loadMessages`.
- part type ∈ {`text`, `file`} (may be sent by the user or the assistant) → **do not create an empty row, ignore this part** (wait for `message.updated` or reconciliation). Prefer not showing anything temporarily rather than creating an empty row with an unclear role.
- The part of a `message.part.delta` does not exist locally → ignore it (the start frame guarantees the part already exists; if a reconnect drops the start frame, the end frame / reconciliation converges).

### 5.4 `message.part.delta` Handling

Handler (reworked from `AppState+SSE.swift:119-131`). The existing guard chain is `sessionID == currentSessionID && field == "text" && delta non-empty && messageID/partID parseable && partType(for: partID) == "text"` (the last one uses the `partTypes` first-write-wins index, `MessageStore.swift:39,107-112`, written by the start frame of part.updated) — **all of it is kept**, and the newly added text append hangs inside the same guard:

1. Locate the local part (partID inside the current session row) → `part.text += delta` (modifies `messages` in place). Part does not exist → ignore it (5.3).
2. **Reasoning does not stream**: the guard only lets text parts through; reasoning text lands in the local part only via the end frame (the complete `part.updated`) — consistent with today (today's iOS reasoning is not rendered from deltas either), so the change surface does not grow.
3. Once the end frame (a `part.updated` with complete text) arrives, `upsertPart` replaces that part as a whole → natural convergence (the delta concatenation matches the complete frame; even if deltas were lost, the end frame overwrites them).

### 5.5 REST Demoted to Reconciliation

- Delete all per-event trigger points of `loadMessages` and `loadSessionDiff`; the remaining trigger moments are:

| Moment | Current | After the change |
|---|---|---|
| SSE (re)connect bootstrap (`bootstrapSyncCurrentSession`) | yes | kept |
| `session.status → idle` | no (only a local status update, the unit test asserts 0 REST) | **new**: `await loadMessages() + await loadSessionDiff()` (turn terminal reconciliation, including `time.completed`/tokens; once per turn) |
| manual refresh / session switch / loadOlder / revert / edit / abort / recover / refresh | yes | kept (the list of non-per-event `loadMessages` call sites is below, all unchanged) |
| watchdog trigger | no | new (5.6) |
| `session.error` | `await loadMessages` (no diff) | kept unchanged (the error path stays as today, the change surface does not grow) |

* Expected: REST per turn drops from `N×(8+3M)` pairs to 1 (idle reconciliation) + 0–1 (bootstrap, only on reconnect). The frequency of heavyweight message list fetches drops significantly — satisfying the hard constraint "the number of fetch actions must not grow" (the background section of `session_status_bar/design.md`); this is a contraction, not an amplification.

**Code position of the idle reconciliation**: appended inside the `session.status` handler (`AppState+SSE.swift:57-76`), after `sessionStatuses[sessionID] = decoded`:

```swift
if decoded.type == "idle", sessionID == currentSessionID {
    await loadMessages()
    await loadSessionDiff()
}
```

* Mind the gating: the existing handler updates the status for every session (no currentSession filter, `sessionStatuses` is a global map), so the idle reconciliation action must explicitly carry `sessionID == currentSessionID`. The busy/retry branches stay untouched.

* **List of non-per-event `loadMessages` call sites** (all kept; `loadSessionDiff` likewise, the main items are listed):

- `AppState+Sessions.swift`: `selectSession` :285, `loadSessions` restore hydrate :174, `forkSession` :364, `deleteSession` :395, `abortSession` :482, `bootstrapSyncCurrentSession` :441
- `AppState.swift`: `refresh()` :900
- `AppState+Messages.swift`: `loadOlderMessagesForCurrentSession` :111, `editFromMessage`/revert :191
- `AppState+SSE.swift`: `recoverFromMissingCurrentSessionIfNeeded` :359, `handleRemoteSessionDeleted` :380, `session.error` handler :191 (this path is kept, see the table above)

### 5.6 Heartbeat Watchdog

- **Timestamp**: `sseLastFrameAt = Date()` is set uniformly at the `handleSSEEvent` entry (any frame, including heartbeats).
- **Check**: a 5s periodic Task (launched when the stream starts in `connectSSE`, cancelled on disconnect/cancel; AppState is `@MainActor`, so there is no race with the event loop):

```swift
func checkSSEWatchdog() {
    guard let last = sseLastFrameAt, currentSessionID != nil else { return }
    guard Date().timeIntervalSince(last) > Self.sseSilenceThreshold else { return } // 20s
    sseLastFrameAt = Date()
    Task { await loadMessages(); await loadSessionDiff(); await syncSessionStatusesFromPoll() }
}
```

- **Threshold 20s** = 2 heartbeat periods (the server hardcodes 10s). Worst-case recovery delay 25s (20s threshold + 5s check period). Constants: add `sseWatchdogCheckInterval: TimeInterval = 5` and `sseSilenceThreshold: TimeInterval = 20` to the static let constant area of `AppState` (`AppState.swift:165-186`).
- **Wiring (exact landing points)**:
  - New `AppState` member (stored property area, next to `sseTask`, around `AppState.swift:667-668`): `var sseLastFrameAt: Date?` (**internal, without `private`** — unit tests preset it directly through `@testable`; the existing pattern in the test target is to read internal state directly, e.g. `state.messageStore...`); `private var sseWatchdogTask: Task<Void, Never>?` (not touched by tests).
  - `connectSSE` (`AppState+SSE.swift:9-39`): `sseWatchdogTask?.cancel()` first at the function entry; after the `bootstrapSyncCurrentSession` call (semantically between :25-26 and :26, i.e. before the stream is consumed) set `sseLastFrameAt = Date()` and launch the watchdog Task:

```swift
sseWatchdogTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Self.sseWatchdogCheckInterval))
        await self?.checkSSEWatchdog()
    }
}
```

- `handleSSEEvent` entry (before the `switch`): `sseLastFrameAt = Date()`.
  - `checkSSEWatchdog()`: a new `@MainActor` internal method, placed in `AppState+SSE.swift` (the pseudocode above); `syncSessionStatusesFromPoll` already exists (`AppState+Sessions.swift:464-468`), reuse it directly.
  - Cancel the watchdog Task when AppState is deallocated / `connectSSE` re-enters (same lifecycle as `sseTask`, the cancel pattern at :10-11).
- **Not polling**: there is no fixed-period fetch; under normal conditions (one heartbeat frame every 10s + business events during a turn) the check is a constant no-op.
- **Division of labor with the backoff reconnect**: the reconnect handles "the connection dropped" (a bootstrap reconciliation already exists after a reconnect); the watchdog handles "the connection is alive but no frames arrive". Together they cover silent death.
- **Degraded behavior on hosts without heartbeats** (dsh shim / hypothetical compatible hosts): one reconciliation is triggered every 20–25s during silence = low-frequency polling, far below the current Android busy polling (2s), no regression. If it is later confirmed that the shim has no heartbeat and users care, an adaptive rule could raise the threshold to 60s after K consecutive heartbeat misses — not done in this phase.
- **Background scenario**: the Task may be suspended while the app is in the background; SSE (URLSession) most likely disconnects in the background → the reconnect bootstrap already covers the catch-up; on returning to the foreground the first timer tick or the next frame converges. Known trade-off, no dedicated handling.
- Unit test path: `sseLastFrameAt` and `checkSSEWatchdog()` are exposed as internal (or accessed directly via `@testable`); in the test set `sseLastFrameAt` to 30s ago → call `checkSSEWatchdog()` → assert `messagesCallCount == 1`.

### 5.7 Explicitly Out of Scope

- **2s busy polling**: not introduced. Silent death is covered by 5.6; data timeliness is covered by the direct payload supply in 5.1.
- **Optimistic busy on send**: the gap in the composer line between `sendMessage` and the `session.status=busy` frame (sub-second) is accepted.
- **tile / FileCard visual upgrade**: this is not mere experience polish, it is the **necessary complement** for surfacing the tool running state (see the "UI-layer gap"): the existing collapsed tool row has no per-tool running indication, and the composer line text depends on the server's `status.message`. The P2 feature must explicitly surface the running tool inside the row (tool name + elapsed time) — the experience Android already has today, and the target iOS must eventually align with. The existing running state of `ToolPartView` (`ToolPartView.swift:31, 191-198`) takes effect directly once the data lands, as the transitional form before P2.
- **Subagent event handling**: unchanged (only currentSessionID is handled); state changes of the parent session's task parts travel through the normal part event path (parent sessionID) and are naturally visible in the UI.
- **Cleaning up the dead constant `APIConstants.sseEndpoint`**: optional (a ConnectionTests assertion references it), not blocking.
- **Server-side changes**: zero.

### 5.8 Boundaries and Consistency

- **Idempotency / out-of-order**: upsert by ID; shell rows are overwritten by later events; the end frame converges the delta concatenation.
- **Optimistic user row**: the user `message.updated` pushed back by the server overwrites the info + untracks; **transient display is accepted at the parts level** — the server may rewrite the user text (e.g. the analyze-mode prefix; the existing unit test `loadMessagesReplacesOptimisticRowWhenServerConfirmsSameMessageID` asserts that the server text wins), and in the in-place path that rewrite only converges at the reconciliation (idle). Showing the original text during a turn is a cosmetic trade-off and is acceptable; if the server sends part events for user messages, the temp-part deduplication in 5.2-3 guarantees no duplicate display.
- **Revert**: after a revert the client already forces `loadMessages` (the current path is kept); the `message.removed`/`part.removed` events (emitted by revert cleanup) now delete the local row/part directly, which is more timely than today (waiting for REST).
- **Session switch**: the inline `== currentSessionID` guard drops stale events; the switch triggers the bootstrap reconciliation (current behavior).
- **Large sessions**: upsert only affects the already loaded window (limit 20 pages), it does not grow memory.
- **State modifications that bypass the event bus**: none exist (the server routes all modifications through the bus).
- **Compaction**: history parts are neither deleted nor modified (`tail_start_id` mechanism, verified fact 6 of session_status_bar), no special handling.
- **Rendering granularity**: `MessageWithParts` is an array of structs, not a lazy list, so the Observation trigger surface of an in-place change to `messages[i].parts[j]` is the same as a wholesale replacement (ChatTabView body level). **The benefit of this feature is eliminating per-event REST and the event queue blocking, not the rendering granularity**; per-part observation is a later optimization (the data model is an array of structs, so incremental observation is impossible without switching to reference types — out of scope here).

## 6. Relationship with the session_status_bar Feature

* **Clarification**: be careful to distinguish the two in naming — its "data path" refers to the source of some session-level counters (rounds, tool calls, tokens); this feature's "data path" refers to the real-time reflection of the message and message/part state in the chat UI.

- **What it already does** (observed 2026-09-29, not yet committed on the main checkout): `statsStore.observeUserMessage` (user role) was added in message.updated, `statsStore.observeToolPart` was added in message.part.updated, both before the `await` REST.
- **Compatibility promise**: this feature only removes the per-event `await loadMessages/loadSessionDiff`; the `statsStore.observe*` call sites are kept as is (they are all synchronous local bookkeeping and do not depend on REST). Its reconciliation dependency — "reconcile the window after loadMessages completes" — still happens during the idle/bootstrap reconciliation (with a lower frequency; the counters are dominated by SSE increments and are unaffected).
- Shared live evidence: the event timeline cited in this document comes from its verified facts (probe `tmp/status_bar_probe.py`).
- Implementation order: mutually independent. Whichever merges first, the other is based on the master that follows it; the branch state depends on the actual situation at implementation time.

## 7. Implementation Order (verify step by step)

1. **MessageStore data layer**: add `upsertPart`/`upsertMessageInfo`/`removePart`/`removeMessageRow` + the shell row / optimistic deduplication logic (5.2/5.3). Purely local logic, no SSE wiring.
   - Verification: add MessageStore unit tests (upsert replace/insert/shell row/temp deduplication/gate `.needsReconcile`).
2. **SSE handler rework** (`AppState+SSE.swift`): rework event by event following the table in 5.1; explicit `server.heartbeat` case; idle triggers reconciliation.
   - Verification: SSE unit tests (see the test specification), run the full `SessionFlowTests` regression.
3. **Watchdog**: `sseLastFrameAt` + timer + `checkSSEWatchdog` (5.6).
   - Verification: watchdog unit test (time injection).
4. **Live acceptance** (scratch server, see below) + UI automation screenshots.

## 8. Test Specification

**Rewrites of existing tests** (`SessionFlowTests.swift`, harness unchanged: `makeSSEEvent` + `applySSEEventForTesting` + `MockAPIClient` counts):

| Existing test case (line) | Current assertion | After the change |
|---|---|---|
| `messagePartUpdatedReloadsCurrentSession` (:1522) | `messagesCallCount == 1` | `== 0` + local part state assertion (the upsert took effect) |
| `messagePartUpdatedWithDeltaStillReloads` (:1541) | `== 1` | gate made explicit: complete part → 0 REST + upsert; shim thin part + top-level delta → keep 1 REST (regression assertion) |
| `messageUpdatedForCurrentSessionReloads` (:1407) | `== 1` | `== 0` + info upsert assertion |
| `sessionStatusIdleRecordsIdleForCurrentSession` (:1574) | `messagesCallCount == 0` | `== 1` (idle reconciliation, new behavior) |

* **New test cases** (same file, same harness):

- part upsert three states: the three frames of tool `pending→running→completed` each change the local state, with 0 REST throughout.
- delta streaming: `part.updated` (empty text start) → 3×`message.part.delta` → `part.updated` (complete end): `part.text` grows segment by segment in between, and after the end frame it equals the complete text.
- shell row: an assistant-only part (tool) arrives first for an unknown messageID → a shell row is created; a text part arrives first → no row is created.
- out-of-order: a part arrives before `message.updated` → the shell row is completed by the info.
- idempotency: replaying the same frame does not duplicate anything.
- removed: `message.part.removed` (`{sessionID,messageID,partID}`) deletes the part; `message.removed` deletes the row.
- optimistic: a server part (non-temp id) for a pending row arrives → temp parts are cleared and the server part is displayed; a user `message.updated` → untrack.
- events for a non-current session are all ignored (0 REST, 0 state changes).
- gate: a shim-shaped payload → falls back to REST (`messagesCallCount == 1`).
- watchdog: `sseLastFrameAt` set to 30s ago + `checkSSEWatchdog()` → 1 reconciliation; a fresh timestamp → no-op.

## 9. Live Acceptance

- Environment: a scratch server on a temporary port (**do not reuse the 4096/4097 live server**); use a long tool such as `bash sleep 6` for the prompt.
- Acceptance points:
  1. After sending, the `session.status=busy` frame arrives → the composer line appears + the timer runs (sub-second, event driven).
  2. The tool running frame arrives → the tile state updates immediately, the activity text shows `Running commands - <cmd>`, and the elapsed time ticks by seconds (event driven, no REST dependency). Mind the boundary of the current UI form (see the UI-layer gap): what you see is a collapsed row state update + the composer line text; the explicit running indication inside the row is filled in by the P2 tile feature, and it is not treated as a failure item during acceptance.
  3. Cut the SSE (or have the proxy simulate silence) → within ≤25s the watchdog triggers one reconciliation and the state recovers.
  4. REST count comparison: during a turn the number of message fetches in the network panel/logs = 1 (idle reconciliation), compared with the current 42 pairs (the N=3, M=2 formula).
- UI acceptance: the existing iOS UI automation (screenshots to check the composer line and the tool tile state).

## 10. Risks and Rollback

- **State drift** (event parsing failures / dropped frames cause local and server state to diverge): three reconciliation paths (bootstrap/idle/watchdog) + the gate fallback as a backstop. Add diff logging during debugging: a DEBUG switch (the pattern = the `isCarModeEnabled` trio, `AppState.swift:182/243/396`, wrapped in `#if DEBUG`), comparing local vs REST during reconciliation and `Logger.debug`-ing the result.
- **iOS endpoint assumptions**: the design depends on the heartbeat and FIFO order of `/global/event` (verified in the source); the heartbeat of the shim host is unverified, and the degraded behavior causes no regression (5.6).
- **Rendering performance**: in-place updates do not change the trigger surface (5.8), no new risk; streaming deltas are frequent (one frame per token), and the `messages` array changes on every delta → the ChatTabView body recomputation frequency goes from 0 (today's iOS does not render deltas) to token level. **Live observation of scrolling/input jank is required**; if it janks, the mitigation = batch the delta appends over 50–100ms (`lastDeltaAt` throttling, with the lost intermediate states converged by the end frame) — reserve that switch position during implementation, off by default.
- **Rollback**: no data migration, no protocol/server changes. Reverting the commit restores the current state.

## 11. Effort Estimate

| Item | Estimate |
|---|---|
| MessageStore upsert layer + unit tests | 0.5 day |
| SSE handler rework + test rewrites/new tests | 1 day |
| Watchdog + unit tests | 0.5 day |
| Live acceptance + UI automation | 0.5 day |

## 12. Remaining Open Items (do not block kickoff)

1. **Whether a turn-level `final completion` message frame** (including `time.completed`) exists — pending live measurement; its absence does not affect the design (the idle reconciliation converges).
2. **Whether the dsh shim host sends `server.heartbeat`** — unverified; the degraded behavior is designed (5.6).
3. **Whether the server sends `part.updated` events for the parts of user messages** — unverified; both cases are covered by 5.2-3 / 5.8.
4. **Whether the delta throttling switch is needed** — decided after live acceptance (see "10. Risks and Rollback").
