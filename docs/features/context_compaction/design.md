# OpenCode iOS Manual Context Compaction Design

Status: proposal only, no implementation

## Bottom Line

`/compact` is a purely client-side command, not a Prompt sent to the model. When the Web client recognizes the command in the composer, it calls the session compaction API and never submits the literal command text as an ordinary user message.

The iOS client has not yet built an equivalent command-parsing layer. `sendMessage` forwards all text from the composer indiscriminately to `/session/:id/prompt_async`, so typing `/compact` sends that string straight to the model. This is the expected behavior of the current client implementation, not a server-side defect.

The recommended product interaction unifies this into a single session-level Action, exposed through two entry points:

1. An obvious `Compact Context` action in the Session action menu (`...`) and in the context usage (context-usage) UI.
2. A `/compact` slash-command (slash-command) shortcut in the composer for keyboard users.

Both entry points call the same strongly typed client Action underneath, and neither produces an ordinary user text message.

## Current Mechanism

### Web Client

The Web client registers a built-in command whose definition contains:

- command ID: `session.compact`
- slash trigger: `compact`
- action: calls `client.session.summarize(...)`

When the user picks the built-in command in the slash-command picker, the composer clears the command text and invokes the command registry dispatch. Custom slash commands take a different path and stay as editable Prompt text.

Relevant source references:

- `opencode-official/packages/app/src/pages/session/use-session-commands.tsx`
- `opencode-official/packages/app/src/components/prompt-input.tsx`

This explains the previously observed Tab key interaction: the Tab key selects a local autocomplete candidate, and selecting it dispatches `session.compact` rather than relying on the model's semantic understanding of `/compact`.

### Current iOS Client

The current execution path of the iOS client is:

```text
composer text
  -> AppState.sendMessage(...)
  -> APIClient.promptAsync(...)
  -> POST /session/:id/prompt_async
  -> normal user message
```

A built-in command registry and a pre-send interception layer are currently missing. Although `Part.type` can decode unknown Part types into strings, the iOS side has no dedicated state-machine transitions or completion-state UI designed for Compaction.

Relevant source references:

- `OpenCodeClient/OpenCodeClient/AppState+Messages.swift`
- `OpenCodeClient/OpenCodeClient/Services/APIClient.swift`
- `OpenCodeClient/OpenCodeClient/Models/Message.swift`

## Backend Contract

The OpenCode server currently has two generations of API specification, and they should not be conflated when designing.

### Legacy API Used By The Current Web Client

```http
POST /session/:sessionID/summarize
Content-Type: application/json

{
  "providerID": "openai",
  "modelID": "gpt-5.6-sol",
  "auto": false
}
```

The endpoint does the following:

1. Clears the currently active Revert state.
2. Derives the currently active Agent from the most recent history messages.
3. Builds and appends a synthetic user message (synthetic user message) containing a `compaction` part.
4. Runs the normal session inference loop with the currently selected model.
5. Generates a structured summary of the earlier conversation history, optionally merging with a previous summary if one exists.
6. Subsequent session turns continue from that compacted representation.

This operation really consumes one model call, rather than being a simple local string-truncation algorithm.

### V2 API Direction

The public V2 design specification is defined as follows:

```http
POST /api/session/:sessionID/compact
Content-Type: application/json

{}
```

The current V2 documentation describes it as an asynchronous admission (asynchronous admission) mechanism: after the server receives a compaction request, it performs the compaction at a safe session-turn boundary and pushes progress and completion notifications through the Session event stream. An optional Request ID supports idempotent retries.

The local checkout from July 14 is in a transitional state: the route already exists, but its core implementation still returns `OperationUnavailableError` directly. So the iOS client should not switch to V2 merely because the route is declared; it should keep using the Legacy protocol of the currently deployed server and migrate later, after a capability check (capability check) is completed or the server is upgraded in coordination.

### What Compaction Changes

Compaction changes the representation of the conversation history that is visible to the model; it does not physically delete the original persisted message records from the underlying storage.

Conceptually:

```text
Durable session history
  = original messages remain available to clients and export

Next model context
  = system context
  + generated checkpoint/summary of older history
  + retained recent turns
  + messages created after compaction
```

This summarization is lossy. Even though the original messages remain fully intact in the session database, exact details from the older conversation may disappear from the context visible to subsequent models.

Automatic compaction (Automatic compaction) is a separate triggering policy on top of the same underlying mechanism. The existing Legacy configuration uses `compaction.auto`, `compaction.prune`, and `compaction.reserved`; V2 gradually evolves toward model-aware headroom (headroom) and retained-turn (retained-tail) configuration. Manual compaction should be triggerable independently, unaffected by the state of the automatic compaction switch.

## Recommended UX

### Primary Entry Point

Add a `Compact Context` action to the Session `...` menu, placed alongside the other session-level actions such as `Interrupt Agent` and rename.

Show a concise explanation in the action row or in a first-run guidance sheet:

> Summarize older conversation to free context space. Full history remains visible, but the agent may lose exact older details.

Compared with forcing users to remember a terminal-style command, this is far more discoverable.

### Context Usage Entry Point

Tapping the existing Context ring progress opens a lightweight detail sheet:

```text
Context used                 78%
Older turns can be summarized to free space.

[Compact Context]
```

When usage exceeds a product-defined threshold, the action can be visually emphasized, but users may still trigger it manually at a lower level. Merely opening the detail sheet must not automatically trigger compaction.

### Slash Command Entry Point

When the composer starts with `/`, show the native command picker, containing:

```text
/compact       Compact context
/summarize     Alias for /compact
```

After picking either command, the strongly typed Action can either be triggered immediately, or be inserted into the composer as a pending Action Chip that the user sends with Send. Triggering it immediately matches the Web behavior and keeps the overall interaction lighter.

Safe parsing rules:

- Only intercept a built-in command explicitly picked from the picker, or a manually typed `/compact` or `/summarize` that, after trimming surrounding whitespace, matches exactly and carries no attachments.
- Never misinterpret `/compact please`, a `/compact` in the middle of a sentence, or a `/compact` with attachments as a compaction action.
- If the input text starts with a reserved built-in command but is syntactically invalid, show a syntax error locally; never silently send it to the model.
- Draft content already in the composer before the slash picker was invoked must be preserved.

### Progress And Completion

UI state should be strictly scoped to the Session:

```text
idle -> requesting -> compacting -> completed
                          |
                          -> failed
```

Recommended visual presentation:

- Requesting and compacting (requesting/compacting): the Context ring shows a calm loading animation, and the menu action label becomes `Compacting Context...`.
- Completed (completed): insert or fade in a restrained divider marker `Context compacted` in the timeline, then refresh the Context usage data.
- Failed (failed): show a retryable error notice, without modifying or discarding the composer draft.
- Unless the backend explicitly supports a cancellation protocol for Compaction, do not show a cancel button.

For the Legacy `summarize`, a successful HTTP response can indicate that execution finished, after which the session history is refreshed via SSE message and Part updates; for V2, HTTP acceptance only means successful admission, and the client must wait for a Compaction event notification or for the session to reach a stable state.

### Busy Session Behavior

In the Legacy MVP stage, manual compaction is disabled while the session is Busy. This avoids concurrency races with the existing Prompt loop and gives users predictable interaction behavior.

Once the V2 safe-boundary admission mechanism is deployed, the action may be triggered while Busy, with the label `Compact after current step`. The server is responsible for queuing and scheduling compaction requests against Prompts and for merging duplicate requests; the iOS client does not need to take on that scheduling role.

### Confirmation Policy

There is no need to show a confirmation dialog on every trigger. Although the operation is lossy for the model's subsequent attention, it does not physically delete the persisted history, and the official clients already expose it as a direct command.

A one-time instructional sheet or a clear action subtitle is enough. Frequent modal confirmations add heavy friction to the interaction.

## Client Architecture

Strictly decouple the command-parsing layer from the API transport layer:

```text
Composer / Session Menu / Context Sheet
                 |
                 v
       AppState.compactCurrentSession()
                 |
                 v
       SessionCompactionClient
          |              |
          v              v
 legacy summarize     V2 compact
```

`AppState.compactCurrentSession()` owns availability validation, session-level progress state, error handling, post-completion state refresh, and duplicate-tap suppression; each UI entry point only triggers the method.

The transport adapter layer should explicitly distinguish API generations. Blindly retrying with a "V2 first, then Legacy" fallback on any error must be avoided, because a timeout may mean the first request was already accepted by the server, which would cause a duplicate model call. The choice of protocol generation should be based on the version/capability metadata returned by the server, or determined by a fixed configuration entry in the Host Profile.

## Delivery Slices

### Slice 1: Current Server MVP

- Wire up the Legacy `summarize` API request.
- Add a single Compaction Action and its state to AppState.
- Add the `Compact Context` action to the Session menu.
- Intercept the `/compact` and `/summarize` commands exactly on the client.
- Gray out and disable the action while the session is Busy or has no user messages yet.
- Automatically refresh the message list and Context usage after success.
- Add unit tests verifying that the command text never leaks through to `prompt_async`.

This stage requires no server changes. It is a medium-to-small iOS feature change whose main risk is the correctness of the state transitions and interaction details, rather than backend complexity.

### Slice 2: Discoverability

- Add a detail sheet for the Context ring indicator.
- Support an autocomplete picker for slash commands, replacing the plain send-time exact-match interception.
- Add the timeline divider indicator and its localized copy.

### Slice 3: V2 Migration

- Automatically select the V2 protocol based on explicit capability contract negotiation.
- Submit Compact requests with idempotency guarantees.
- Listen for and transition through the Admitted, Running, Completed, and Failed events.
- Support queueing for execution after a Busy turn.
- Remove the Legacy transport layer for good only after every supported host has V2 capability.

## Acceptance Criteria

1. Picking `/compact` never produces an ordinary user text message.
2. The menu entry, the Context detail sheet, and the slash command all call the same AppState Action.
3. On failure, the session state and the composer draft stay intact.
4. Repeated taps cannot trigger duplicate Compaction model calls.
5. After compaction completes, the message stream and Context usage refresh automatically.
6. After compaction completes, the previously persisted history messages remain visible as usual.
7. The UI copy clearly states that older conversation details are subject to summarization loss.
8. The completion semantics of Legacy and V2 have separate test coverage.
9. After an uncertain timeout error, the client does not blindly retry through the second-generation API.

## Recommendation

Once implementation is authorized, prioritize delivering Slice 1. It completely fixes the surprising command pass-through behavior on iOS without modifying the server, and provides a highly discoverable session-level action. Treat the V2 interface as a later protocol evolution, not as a prerequisite for shipping this feature.
