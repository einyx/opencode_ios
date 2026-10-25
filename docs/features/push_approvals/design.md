# Push Notifications and Lock-Screen Approval — Design

> Last reviewed: 2026-10-25 · checked against the current OpenCodeClient implementation
> (`OpenCodeClient/OpenCodeClient`, `master` @ `b0141b7`).
> Companion documents: `../push_notifications/research.md` (the "can we push at all" study),
> `../client_capabilities/protocol.md` (the wire-contract conventions this document follows),
> `../../v2_server_compatibility.md` (the V2 route and event contract).

## Conclusion

The app has **no push support today** — there is no `UNUserNotificationCenter` usage anywhere under
`OpenCodeClient/`, no `aps-environment` entitlement, and no background task scheduling (the only
declared background mode is `audio`, which exists for the Ambient/Car voice capture). While the app
is foregrounded it learns about a blocked agent over SSE; the moment it is backgrounded the SSE stream
and the SSH tunnel are torn down (`AppState+BackgroundVoice.swift:157-175`) and the phone is deaf.
Permission requests and question cards are exactly the moments where the agent blocks on a human, so
this is the gap worth closing.

**Recommended mechanism: a relay that owns the APNs provider key, fed by the user's own OpenCode
server (or a plugin running beside it), with the client's push endpoint being configurable exactly
like the server URL.** The relay holds the APNs provider key and the device-token table; the OpenCode
server holds only an opaque `registration_id` and never sees an APNs credential; the reply — the part
that actually grants a tool permission — travels on the **existing direct client→server channel** and
never touches the relay. That last property is the security core of this design: the relay can say
"there is something pending at this id" and nothing else; it can never approve anything on the user's
behalf. A first-party relay is the default deployment, but a self-hosted relay (holding the user's
own APNs key) is the same protocol, so a user who wants no third party in the loop runs the same
binary themselves. App-side polling is not a competitor here — it is the fallback for badge
reconciliation, and it is not a delivery mechanism.

```text
   iPhone (this app)
     │  1. register: {device_token, registration_id, environment, app_version}
     │  2. reply:    POST <host>/…/permission/:id/reply  (existing client→server auth)
     ▼
  Push relay  ── owns the APNs provider key + the device-token table,
     ▲          renders the APNs payload from a fixed template
     │  3. envelope: {registration_id, event, session_id, request_id, api, action_class}
     │
  OpenCode server (or a plugin beside it)  ← never sees an APNs credential
```

## Scope

In scope:

- Reaching the phone when the app is backgrounded and the agent is blocked.
- Approving a **permission request** from the lock screen, for a narrow, explicitly-enumerated class of
  requests, with a reply that is re-validated against the user's own server before it is sent.
- Tapping a notification to land on the right session (this reuses `opencode://session/<id>`).

Out of scope (explicit):

- **Answering a question from the lock screen.** A question's options are agent-authored content; putting
  them in the payload breaks the "no content in a push" rule, and on V2 the reply additionally needs the
  option *value* table the client can only obtain from `GET /api/session/:id/form`. See §3.5.
- **"Allow always" from the lock screen.** A durable grant whose scope the user never saw is exactly the
  over-broad grant the in-app card is designed to prevent (`PermissionCardView.swift:42-53`).
- Live Activities, PushKit, background modes, badge counts, and the watchOS/visionOS targets.
- Replacing SSE. SSE stays the foreground data path; push only *wakes* the app.

---

## 1. Mechanism options

### 1.1 Comparison

| | (a) Server sends APNs directly | (b) First-party relay owns the provider key | (c) App-side polling |
|---|---|---|---|
| **Client must** | Register its APNs device token with its own server; store it per host; re-register on token rotation | Register the token with the relay + tell the server the opaque `registration_id`; store both per host | Register a `BGAppRefreshTask`; poll `GET /permission` / `GET /question` on wake |
| **Server must** | Hold the APNs provider key (`.p8`); implement token registration + APNs HTTP/2 client | Nothing APNs-related; only needs to emit an envelope to the relay | Nothing |
| **Offline phone** | Push is queued by APNs and delivered when the device reconnects; the *reply* still fails | Identical | The poll simply does not run; nothing is queued; the agent stays blocked |
| **Privacy cost** | Provider key on a user machine; the server learns the device token | Relay sees `registration_id`, `session_id`, `request_id`, event class — no content, no host URL, no credentials | None (nothing leaves the device), but nothing arrives either |
| **Key blast radius** | One leaked `.p8` ⇒ full push spoofing for **every** user of the app | One leaked `.p8` ⇒ same, but the key sits in one audited service | n/a |
| **Works without the app's server being internet-reachable** | Yes (the server is the pusher) | Yes, with the plugin model: the plugin dials out | No |
| **Fit with this app's model** | Bad: it makes every user's server a push operator | Good: the client is still a remote control for *the user's* server; the relay is a dumb pipe | Bad as a primary; fine as reconciliation |

### 1.2 (a) Server sends APNs directly — rejected as the default

The client side is trivial (register the token with the host it already talks to, over the existing
authenticated channel). The fatal problem is key distribution: the APNs provider key belongs to the app
developer, so the only way for a user's server to send APNs is for the developer to hand every user's
server a copy of the same `.p8`. One compromised home server, one leaked backup, one accidental paste
into a chat window — and anyone holding that key can push arbitrary notifications to every user of the
app, in the app's name, on any device. The user's server would also have to grow a provider-token
implementation, an APNs HTTP/2 client, token invalidation handling, and APNs-specific logging.

This remains acceptable in exactly one case: **a self-hosted deployment where the user owns the Apple
Developer account and therefore the key**. That is the "your own relay, your own key" variant, and it is
why the design below keeps the endpoint pluggable rather than hard-wired to a first-party host.

### 1.3 (b) Relay owns the provider key — recommended

The relay is a deliberately dumb component with three jobs:

1. Hold the APNs provider key and the `registration_id → device_token` table.
2. **Render the APNs payload from a fixed template.** It accepts a structured envelope, not a blob of
   text. The server cannot put arbitrary strings in a notification body — the body is a lookup in a
   closed table keyed by `event` and `action_class`. This makes "never put message content in a push
   payload" an enforced property rather than a convention.
3. Forward envelopes to APNs, and drop registrations on APNs invalid-token responses.

The OpenCode side is a **plugin** (the mechanism already researched in
`../push_notifications/research.md`): a small JS/TS plugin loaded from `~/.config/opencode/plugins/`
that consumes the public `Hooks.event` interface and POSTs a minimal envelope. The plugin holds no
credential beyond the relay's shared secret and never blocks the agent's turn (the server dispatches
plugin hooks fire-and-forget).

The alternative "watcher" topology — a relay-side process holding an SSE connection to each user host —
is strictly worse on privacy, because the relay would need the host URL *and* the host's basic-auth
credentials. It is acceptable only for internet-reachable hosts, and it is a fallback for hosts where
the plugin cannot run.

**Where the APNs provider key lives is a first-class decision, not an implementation detail.** This
design assumes it lives in a relay process that is *not* the OpenCode server. The client treats the
push endpoint as a configurable URL with an optional bearer token, mirroring how the host URL and its
Keychain-stored password are configured today. A user who wants no first-party service in the loop
runs the same relay (or a plugin pointed at their own) and configures their own endpoint.

### 1.4 (c) App-side polling — fallback only

`BGAppRefreshTask` wakes the app at a schedule the OS chooses; the window is short and the schedule is
not guaranteed. For a *direct*-transport host it is adequate to keep a badge count roughly fresh and
to reconcile pending approvals after a missed push. For an *SSH-tunnel* host it is not adequate at all:
the tunnel is closed when the app backgrounds, and re-handshaking SSH inside a background window is
unreliable. Polling cannot deliver "the agent is blocked right now" with any latency guarantee, which
is the entire reason this feature exists.

**Decision:** polling is not the mechanism. It is at most a reconciliation pass that runs when the app
next foregrounds, and the existing `refreshPendingPermissions()` / `refreshPendingQuestions()` already
do exactly that.

### 1.5 Minimal payload (the privacy contract)

The APNs payload carries **locators and closed enums only**. Nothing that a user typed, a model wrote,
or the filesystem contains.

```json
{
  "aps": {
    "alert": { "title": "Approval needed", "body": "OpenCode wants to read files." },
    "sound": "default",
    "category": "opencode.permission",
    "thread-id": "ses_abc123",
    "interruption-level": "active"
  },
  "schema_version": 1,
  "event": "permission.asked",
  "api": "v2",
  "registration_id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
  "session_id": "ses_abc123",
  "request_id": "per_7",
  "action_class": "read",
  "occurred_at": 1793000000
}
```

Rules:

- `alert.title` / `alert.body` are **fixed strings** selected by the relay from a table keyed by
  (`event`, `action_class`). There is no interpolation of any field from the envelope. The only
  variable part of the body is the `action_class` phrase, which is one of five fixed strings.
- `action_class` is a **client-defined closed enum**: `read | edit | exec | network | other`. The relay
  maps the server's permission action onto it and sends the *class*, never the raw action name. An
  unrecognised server action maps to `other`.
- `session_id` and `request_id` are opaque server identifiers. They are metadata, not content, but they
  are stable identifiers of the user's work — the relay must not log them beyond what is needed to
  deliver, and registrations must expire.
- **Never in the payload:** prompt text, assistant text, tool arguments, file paths, permission
  patterns, question text, option labels, session titles, host URLs, usernames, tokens.
- The payload size limit is 4 KB; the envelope above is ~250 bytes.

---

## 2. Server-side protocol delta

### 2.1 What the existing event vocabulary already covers

The app translates server events into a small internal vocabulary, and the provider (plugin or watcher)
can reuse **the same server-side events** — no new bus events are required for delivery.

| Semantic | V1 server event | V2 server event | App-internal translation |
|---|---|---|---|
| Permission requested | `permission.asked` | `permission.asked` | `permission.asked` → `PermissionController.parseAskedEvent` |
| Permission resolved | `permission.replied` | `permission.replied` | `permission.replied` → `PermissionController.applyRepliedEvent` |
| Question created | `question.asked` | `form.created` | `question.asked` → `QuestionController.parseAskedEvent` |
| Question resolved | `question.replied` / `question.rejected` | `form.replied` / `form.cancelled` | `question.rejected` → `QuestionController.applyResolvedEvent` |
| Task failed | `session.error` | `session.execution.failed` | `session.error` → `pendingSessionErrorAt` |
| Task finished | *no discrete event* — only a `session.status` transition to `idle` | `session.idle` (discrete) | `session.status` with `status.type == "idle"` |

Sources: `Services/V2EventTranslator.swift:97-124` (V2→V1 name mapping), `AppState+SSE.swift:411-430`
(the handlers), `docs/v2_server_compatibility.md:56-57, 319-322` (the measured V2 contract).

**Coverage verdict:** permission ✅, question ✅, failure ✅, completion ⚠️.

Two gaps in the vocabulary matter for push:

1. **Completion is derived on V1.** V1 emits `session.status` with `type: "idle"`; there is no
   "task finished" event. A provider on V1 must watch the busy→idle transition of a session and emit
   `session.completed` itself. On V2 the discrete `session.idle` event exists. The client already
   treats idle as the turn-end signal (`AppState+SSE.swift:242-244`).
2. **A user-initiated abort must not be pushed as a failure.** The client distinguishes the two:
   `error?["name"] != "AbortError"` (`AppState+SSE.swift:446`). The provider must apply the same rule,
   otherwise tapping "Stop" in the app produces a "task failed" push on the user's own lock screen.

### 2.2 What is missing: three new routes, all on the relay, one on the server

**Missing on the OpenCode server — one route.** The server must know which opaque `registration_id`
belongs to which device so it can name the device in the envelope. It never receives a push credential.

| Route | Body | Response | Notes |
|---|---|---|---|
| `POST /push/device` (V1) · `POST /api/push/device` (V2) | `{"registration_id": "<uuid>"}` | `204` | Idempotent. The server stores the id against the authenticated client/session so it can include it in envelopes. |
| `DELETE /push/device/:registration_id` | — | `204` | Revocation; the client also calls this when the user disables push or deletes the host. |

The server's reply to a push is therefore: *here is an opaque id, put it in the envelope*. Nothing else.

**Missing on the relay — three routes.**

| Route | Body | Response |
|---|---|---|
| `POST /registrations` | `{"device_token", "registration_id", "environment", "app_version", "platform"}` | `201 {"registration_id"}` (the client supplies the id; the relay echoes it) |
| `DELETE /registrations/:registration_id` | — | `204` |
| `POST /envelopes` | the envelope of §1.5 | `202` (accepted) or `202 {"delivered": false}` if the registration is unknown/expired |

**Missing on the provider (plugin) — the envelope emitter.** It watches the server's own event bus,
maps the events of §2.1 onto envelope `event` values, resolves the permission action onto
`action_class`, deduplicates on `(registration_id, event, request_id)`, and POSTs to the relay.

### 2.3 Envelope contract (the wire format)

Following the conventions in `../client_capabilities/protocol.md` (snake_case wire fields, an explicit
`schema_version`, strict parsing, a closed enum for every variable field):

```json
{
  "schema_version": 1,
  "event": "permission.asked | question.asked | session.completed | session.failed",
  "api": "v1 | v2",
  "registration_id": "<uuid v4>",
  "session_id": "ses_...",
  "request_id": "per_... | frm_...",
  "action_class": "read | edit | exec | network | other",
  "occurred_at": 1793000000
}
```

- `schema_version` is mandatory and must be `1`. The relay rejects anything else and logs it; the
  client never parses a relay-originated body, so a version bump only affects the plugin↔relay hop.
- `registration_id` is a **client-generated UUID v4**, one per (device, host profile) pair. It is the
  only device identifier the OpenCode server ever sees. It survives APNs token rotation.
- `session_id` and `request_id` are the server's own ids and are already the parameters of the reply
  routes (§2.4), so no new id space is introduced.
- `action_class` is `other` for every event that is not a permission. The relay renders the body from
  (`event`, `action_class`) only.
- `occurred_at` is epoch seconds, informational. The client does not use it to decide anything — it
  re-reads the truth from the server (§3.3).

### 2.4 The reply routes the lock screen depends on

The approval must be deliverable by a background task that knows only `session_id` and `request_id`.
Both generations already have routes addressable by exactly those two ids:

| | V1 (as the client calls it today) | V2 |
|---|---|---|
| Reply to a permission | `POST /session/:sessionID/permissions/:permissionID`, body `{"response": "once" \| "always" \| "reject"}`, expect `200` | `POST /api/session/:sessionID/permission/:permissionID/reply`, body `{"decision": "once" \| "always" \| "reject"}`, expect `204` |
| Reply to a question | `POST /question/:requestID/reply`, body `{"answers": [["..."]]}` | `POST /api/session/:sessionID/form/:formID/reply`, body `{"answer": {"<key>": "<value>"}}` |
| Cancel a question | `POST /question/:requestID/reject` | `DELETE /api/session/:sessionID/form/:formID` |
| List pending | `GET /permission` | `GET /api/session/:sessionID/permission` |

Sources: `Services/APIClient.swift:921-1037` (the client's actual calls), `docs/v2_server_compatibility.md:34-38, 169-173`,
`docs/OpenCode_Web_API.md:175, 239-248`.

Three consequences:

1. **The permission reply needs no extra state.** Both routes are addressable by `(sessionID, requestID)`
   alone. ✅
2. **The question reply needs state the app may not have.** On V2, `APIClient.replyQuestion` looks the
   form up in an in-memory `formReplyTable` and throws `404` when it is missing
   (`Services/APIClient.swift:988-990`); the table is filled only by `pendingQuestions()`. A cold-started
   background reply has an empty table. This is the second, independent reason question answering from
   the lock screen is out of scope (§3.5).
3. **The V1 permission reply route is deprecated.** `docs/OpenCode_Web_API.md:175` marks
   `POST /session/:sessionID/permissions/:permissionID` deprecated in favour of
   `POST /permission/:requestID/reply` with body `{"reply", "message?"}`, while the client still calls
   the deprecated route with a `{"response": ...}` body. A background reply that hard-codes one of them
   will break when the server drops it. **This must be settled before slice S6** (open question Q2).

### 2.5 Server-side dedup and reconciliation

The provider (plugin) is the dedup point, not the server and not the relay:

- **Dedup key:** `(registration_id, event, request_id)` — the same recommendation as
  `../push_notifications/research.md:149`. A dropped SSE connection followed by a REST reconciliation
  must not produce a second push for a request the user already saw.
- **Reconciliation:** after an SSE reconnect the provider re-reads `GET /permission` / `GET /question`
  and pushes only the requests that are still pending *and* were never pushed.
- **Revocation races:** the client may revoke a registration while an envelope is in flight. The relay
  answers `202 {"delivered": false}` and the provider drops it. Nothing is queued for a revoked device.

---

## 3. Lock-screen approval UX

### 3.1 Categories and actions

Two categories, one with actions. Action identifiers are namespaced so a stale notification cannot
trigger an unintended handler.

```text
category "opencode.permission"
  ├── action "opencode.permission.allow_once"   (background, .authenticationRequired)
  ├── action "opencode.permission.reject"       (background, .destructive, .authenticationRequired)
  └── default tap → open the session in the app

category "opencode.question"
  └── default tap → open the session in the app      (no actions)

category "opencode.session"
  └── default tap → open the session in the app      (no actions)
```

- **Both actions are background actions** (no `.foreground` option): the system runs the app in the
  background and calls the response handler. A `.foreground` action would defeat the purpose.
- **`.authenticationRequired`** on both: the device must be unlocked for the action to be delivered.
  This is the platform's own answer to "a locked phone must not grant permissions" and it costs
  nothing to opt into.
- **No "Allow always" action.** See §3.3.
- **No actions on questions.** See §3.5.
- `thread-id` = `session_id`, so notifications for one session group in Notification Center.
- `interruption-level`: `active` for permission/question (a blocked agent should interrupt),
  `passive` for `session.completed` / `session.failed` (a finished task should not buzz).

### 3.2 How a lock-screen reply maps onto the existing reply path

The real method names in this codebase (verified, not guessed):

| Layer | Permission | Question |
|---|---|---|
| `AppState` | `respondPermission(_ perm: PendingPermission, response: APIClient.PermissionResponse)` (`AppState+Permissions.swift:16`) | `respondQuestion(_ request: QuestionRequest, answers: [[String]]) -> Bool` (`:56`), `rejectQuestion(_ request: QuestionRequest)` (`:71`) |
| `APIClient` | `respondPermission(sessionID:permissionID:response:)` (`Services/APIClient.swift:936`) | `replyQuestion(requestID:answers:)` (`:985`), `rejectQuestion(requestID:)` (`:1020`) |

Note the asymmetry the brief assumed away: **`replyQuestion` is the `APIClient`-level name;
`AppState` exposes it as `respondQuestion`.** Both exist; the app-level entry point is
`respondQuestion`.

`AppState.respondPermission` **cannot** be used from a notification action, for three concrete reasons:

1. It takes a `PendingPermission` value, which only exists if the app is running and has already
   parsed the request. A background action has only ids.
2. It guards every step with `captureHostRequestSnapshot()` / `isCurrentHostRequest(host)`
   (`AppState+Permissions.swift:17, 20`), which discards the result when the current host changed.
   The notification's host is frequently **not** the current host — the app is connected to one host at
   a time (`currentHostProfileID`), and the pending request may belong to another.
3. The shared `apiClient` is bound to the *current* host. Replying to another host through it would send
   the reply to the wrong server.

So the lock-screen path needs a **separate, self-contained responder**:

```text
PushApprovalService.respond(to envelope, decision)
  1. resolve host:  registration_id → local PushRegistration → HostProfile
  2. resolve creds: HostProfile.basicAuth → Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
  3. build a short-lived APIClient for THAT host (its own URL, generation, credentials)
  4. re-read the truth:  GET /permission   (V1)
                     or  GET /api/session/:sessionID/permission  (V2)
  5. validate:  the request id is still pending
                AND its action maps to the same action_class as the envelope
  6. reply:     POST … reply with decision "once" only
  7. outcome:   approved | alreadyHandled | gone | classMismatch | unauthorized | offline
```

Steps 4–5 are what make the lock-screen approval safe rather than convenient; §3.3 explains why.

`APIClient.PermissionResponse` already has exactly the three values needed: `.once`, `.always`,
`.reject` (`Services/APIClient.swift:895-899`). The responder passes **`.once`** only.

### 3.3 Why a lock-screen approve is *not* just "open the app"

It is "open the app" for everything that cannot be approved in one tap — and that is most things.
The lock-screen approve exists for a narrow class, and it is deliberately a **weaker** affordance than
the in-app approve.

**Why it is not merely a convenience.** The in-app card treats the granted scope as part of the
decision: the patterns are rendered and never clipped, because "approving a pattern you cannot fully
read is how over-broad grants happen" (`PermissionCardView.swift:42-53`). A lock-screen notification
cannot render the patterns — the payload does not carry them, and must not. So the lock-screen approve
is approving *something the user has not seen*. That is only defensible if:

1. **The action set is narrower than the in-app one.** `.once` only; never `.always`; never a
   question; never a custom answer. A durable grant created from a lock screen would encode a scope
   the user never read, and it would outlive the notification.
2. **The decision is re-validated against the user's own server, not against the payload.** The
   envelope travelled through the relay and APNs and may be stale, forged, or mis-classified. The
   responder re-reads the pending request from the server and confirms (a) the id is still pending and
   (b) the action maps to the same `action_class` the envelope advertised. A mismatch aborts the reply
   and tells the user to open the app. **The payload can locate a request; it can never describe one.**
3. **It fails closed.** No Keychain access (device not unlocked since boot, or the credential is gone),
   no connectivity, the request already answered, the session deleted, a class mismatch — in every one
   of these cases **no reply is sent** and the request stays pending on the server. There is no local
   queue of "approvals to send later": a deferred approval would apply to a request that may have
   changed in the meantime, which is exactly what step 2 exists to prevent.
4. **The relay has no power to approve anything.** The approval travels on the existing direct
   client→server channel, authenticated with the host's own credentials. The relay holds the APNs
   provider key and a device token; it can deliver a locator and nothing more. A compromised relay can
   spam the user with notifications; it cannot grant a `bash` permission on their server.
5. **The reply is scoped to exactly one request id.** Two permission requests can be pending at once
   (`pendingPermissions` is a list). "Approve" must target the request the notification named, not the
   head of a queue. The envelope's `request_id` is that target, and step 4 re-checks it.

**Why it is worth having at all (the availability argument).** When the agent blocks, the user's server
sits idle, and the task does not finish. "Open the app" costs at least four interactions — unlock,
launch, find the session, find the card, tap Allow — and only works if the user is at the phone and
willing to navigate. A single "Allow once" on the lock screen, for a request class whose risk does not
depend on the pattern list, is the difference between a task that completes tonight and a task that
hangs until morning. That is the entire value proposition; everything else in this section exists to
keep the affordance honest.

**What `action_class` may be offered.** The client offers the `allow_once` action **only** for classes
in a local allowlist. The starting allowlist is `read` only; `edit`, `exec`, `network`, and `other`
get "Open in OpenCode" and nothing else. Widening it is a product/security decision, not an
engineering detail (open question Q3).

### 3.4 Foreground suppression — and the multi-host hole

The app already handles a permission/question natively: the SSE event appends the card, and
`announcePermissionArrival` / `announceQuestionArrival` fire a haptic
(`AppState.swift:1295-1310`, `AppState+SSE.swift:411-427`). Showing a banner for the same event on top
of that is noise.

**Rule:** suppress the banner when the app is in the foreground **and** the push's host is the current
host. The second condition is not optional: the app is connected to exactly one host at a time, so a
push for a non-current host produces **no** in-app card and **no** haptic — suppressing it would lose
the event entirely. A push for a foreign host must be shown even while the app is active.

`UNUserNotificationCenterDelegate.willPresent` is the hook; the delegate returns `[]` (no options) to
suppress.

### 3.5 Questions, and what happens when the session is gone

**Questions get no actions.** Two independent reasons:

- The options are agent-authored content. Answering from the lock screen requires the option labels in
  the payload, which breaks the no-content rule. (The option *values* are not the problem — the labels
  are what the user reads.)
- On V2 the reply needs the option-value table the client can only build from
  `GET /api/session/:id/form` (`Services/APIClient.swift:988-990`), so a cold-start background reply
  cannot even address the form.

A question notification is therefore informational: *"OpenCode asked a question"* → tap → open the
session → answer in the app where the options are visible.

**When the session is gone.** The re-read in step 4 of §3.2 is the first place this surfaces:

| Condition | What the responder does | What the user sees |
|---|---|---|
| Request id no longer pending (answered elsewhere, or the agent moved on) | No reply | The notification is dismissed; nothing is reported — the state is already settled |
| `GET` returns `404` (session deleted) | No reply | "That session is no longer available" (the same copy as the existing deep-link failure, `AppState+DeepLinks.swift:82-86`) |
| The reply returns `404` (raced with another client) | Treated as **already handled**, not as an error | Nothing |
| The reply returns `401`/`403` | No retry | "Sign in again to approve" |

The background responder cannot touch `AppState` (the app may have been launched purely to deliver the
response, and `AppState` is a `@State` object owned by `ContentView`). Outcomes that the user should
see are written to a small on-disk outbox — the same "write a temp file + atomic move" pattern the
`ClientCapabilityCallbackStore` already uses — and drained on the next foreground, where they surface
as the app's normal error banner.

### 3.6 Notification tap → the right session

The default tap action is "open the session". The existing deep link `opencode://session/<id>` is
strictly parsed (`OpenCodeDeepLink.swift:37-58`: `ses_` prefix, 5–256 chars, `[A-Za-z0-9_-]`, no query,
no fragment, no port), and `AppState+DeepLinks.swift:38-88` already resolves it into a selected
session. A notification is not a URL, so the tap needs a parallel entry point:

```text
UNNotificationResponse (default action)
  → AppState.pendingPushTarget = (registration_id, session_id)
  → after the connection restores: processPendingPushTargetIfPossible()
      → resolve registration_id → HostProfile
      → if it is not the current host: switchHostProfile(to:)   (AppState+HostProfiles.swift:382)
      → selectSession(session)  or  applyProjectDirectory + upsertSession
```

`switchHostProfile` already persists the outgoing host's runtime and re-runs the connection flow, so
the host switch is handled. The target mirrors the existing `pendingDeepLink` / `pendingDeepLink`
-resolution pattern rather than inventing a second mechanism.

### 3.7 The Keychain constraint that makes (or breaks) background replies

`KeychainHelper` stores every item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(`Utils/KeychainHelper.swift:46, 55`). That is the property that makes a background lock-screen reply
possible: the host password is readable in the background **after the device has been unlocked once
since boot**, which is the normal state when a notification is sitting on the lock screen.

If the app ever moves its credentials to `kSecAttrAccessibleWhenUnlocked`, every background reply
fails on a locked device and the whole lock-screen approve feature dies silently. That is a constraint
on the credential store, not just on the push code, and it belongs in the ADR for this feature.

`ThisDeviceOnly` also means the device token does not migrate into a restored backup — a restored
device re-registers. That is the desired behaviour.

---

## 4. Device token registration and revocation

### 4.1 What is stored, and where

The repo's rule is already written down: **host identity lives in `UserDefaults`, credentials live in
the Keychain.** `HostProfile` is a `Codable` blob in `UserDefaults` under `hostProfiles.v1`
(`AppState.swift:212`), while the basic-auth password lives in the Keychain under
`hostProfile.<uuid>.password` (`AppState+HostProfiles.swift:595-597`) and is referenced from the
profile by `BasicAuthConfig.keychainPasswordID` (`Models/HostProfile.swift:65-69`).

The APNs device token is a **push credential**: it authorises delivery to this device and must die with
the host. It therefore belongs in the Keychain, in the same shape as the password:

```text
Keychain item (kSecClassGenericPassword, service = bundle id)
  account: "hostProfile.<hostProfileUUID>.pushRegistration"
  value:   JSON  PushRegistration
  accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   (matches KeychainHelper)
```

```swift
struct PushRegistration: Codable, Equatable {
    var registrationID: UUID      // client-generated; the only id the server ever learns
    var deviceToken: String        // APNs hex token
    var environment: String        // "sandbox" | "production"
    var endpoint: URL              // which push endpoint this registration belongs to
    var appVersion: String
    var createdAt: Date
}
```

Why the Keychain and not the `HostProfiles` blob:

- **Revocation is atomic with the host.** `deleteHostProfile(_:)` already deletes the host's password
  from the Keychain (`AppState+HostProfiles.swift:404-431`); the push registration is deleted in the
  same place, so a removed host cannot keep receiving pushes.
- **It is a device identifier.** A per-device push token in a `UserDefaults` blob that is exported,
  shared, or written into a diagnostics dump is a needless leak. `ThisDeviceOnly` keeps it out of
  backups and out of other devices.
- **It is readable in the background.** Required for the lock-screen reply (§3.7).

`registrationID` is a client-generated UUID v4, **one per (device, host profile) pair**. It is stable
across APNs token rotations and is what the OpenCode server stores. `duplicateHostProfile(_:)`
(`AppState+HostProfiles.swift:433`) must **not** copy the registration: a duplicated profile is a
distinct host identity with its own credentials, and it gets its own registration on its first push.

### 4.2 Registration lifecycle

| Trigger | Action |
|---|---|
| APNs token delivered (`didRegisterForRemoteNotificationsWithDeviceToken`) | Store the hex token against the current host's registration record; register with the endpoint if the `registration_id` is new |
| Host profile connected | Register if no record exists, if the token changed, or if the record is older than the max age (30 days) |
| Token rotated by APNs | Re-register with the **same** `registration_id` and the new token; the endpoint replaces the mapping rather than appending |
| Push enabled in Settings, or a host is added | Create the record, obtain the authorization prompt, register |
| Push disabled in Settings | `DELETE /registrations/:registration_id`, then delete the Keychain record |
| Host profile deleted | `DELETE /registrations/:registration_id` (best effort), then delete the Keychain record |
| Endpoint answers `404`/`410` for the registration | Delete the local record and re-register on the next connect |
| App reinstalled | The Keychain item dies with the app → fresh registration |

The client registers with the **endpoint** (the relay), not with the OpenCode server. The server only
ever receives the opaque `registration_id`, via `POST /push/device`. That keeps every APNs credential
on one side of the wire and means the server cannot be coerced into pushing to a device that is not
registered.

### 4.3 Revocation and expiry

- **The endpoint expires registrations** that have not been refreshed within a TTL (30 days). A device
  that has been off for two months therefore cannot be pushed to.
- **The client refreshes** on connect, so a live device never expires.
- **The server never learns a device token.** If the server is compromised, the attacker learns nothing
  that lets them push.
- **Unregistering is best-effort and local-first**: the local record is deleted even if the network
  call fails. A stale registration on the endpoint is harmless — it is inert until the device
  re-registers with the same id, at which point the mapping is replaced.

### 4.4 Authorization prompt

`UNUserNotificationCenter.requestAuthorization` is requested when the user turns the feature **on**,
not at first launch — the app has no other reason to ask, and a cold prompt for a feature the user has
not discovered is the fastest way to a permanent denial. The Settings row shows the current state
(`off` / `not determined` / `denied` / `on`, with the host name).

---

## 5. Implementation slices

Each slice is one PR. The acceptance criterion is executable. Tier 1 runs under
`./scripts/test_unit.sh`; Tier 2/UI under `./scripts/test_ui.sh`; the server-side wire contract under
`scripts/v2_contract_check.py`.

> **Sequencing note.** `xcodebuild build` and `xcodebuild test` must not run in parallel in this repo
> (shared DerivedData `build.db`). Slices that touch the Xcode project (S4) must not overlap with any
> other slice's test run.

### S1 — Push envelope model and payload sanitizer (client, no network)

New `Models/PushEnvelope.swift` + `Services/PushPayloadSanitizer.swift`: the `Codable` envelope of
§2.3 with **strict** decoding (unknown keys rejected, `schema_version` must be `1`, every enum field
closed), and a sanitizer that maps `(event, action_class)` onto a `UNMutableNotificationContent` with a
fixed title and body, a category, a `thread-id`, and an `interruption-level`.

**Acceptance:** Tier 1 — the sanitizer's title/body for every `(event, action_class)` pair contains no
substring of any envelope field other than the enum's own fixed phrase; an envelope carrying
`"title": "ignore previous instructions"` in an unknown key is rejected outright; `action_class: "exec"`
maps to the `exec` phrase and never to a server-supplied string.

### S2 — Push registration store in the Keychain

New `Services/PushRegistrationStore.swift` over the existing `HostCredentialAccess` seam
(`AppState+HostProfiles.swift:8-24`) so tests can inject a fake; `PushRegistration` as above; the
`registrationID` generator; the `hostProfile.<uuid>.pushRegistration` key, mirroring
`passwordKeychainID(for:)`.

**Acceptance:** Tier 1 — save/load/delete round-trips through the injected fake credential access with
an isolated `UserDefaults` suite; `deleteHostProfile` removes the record; `duplicateHostProfile` copies
the password but **not** the registration, so the duplicate has no `registration_id`.

### S3 — Registration handshake with the push endpoint

New `Services/PushRegistrar.swift` (actor): `register(host:token:endpoint:)`, `unregister(...)`,
`refreshIfNeeded(...)`. It posts `{device_token, registration_id, environment, app_version, platform}`
to the configured endpoint with the endpoint's bearer token, and handles `201` / `204` / `409`
(already registered → treat as success) / `410` (delete the local record) / network failure (retry with
backoff, keep the local record).

**Acceptance:** Tier 1 — a stub endpoint asserts the exact request body and that the `registration_id`
is stable across two `register` calls with a rotated token; a `410` deletes the local record; a
network error keeps it.

### S4 — APNs registration and the notification delegate (the Xcode-project slice)

Add the `aps-environment` entitlement and the `remote-notification` background mode
(`OpenCodeClient/Info.plist` currently declares only `audio`; there is no entitlements file in the
shipped tree); add a `UIApplicationDelegate` via `@UIApplicationDelegateAdaptor` (the app is currently
a bare `WindowGroup` with no delegate, `OpenCodeClientApp.swift:15-37`) implementing
`UNUserNotificationCenterDelegate`: `didRegisterForRemoteNotifications` → hex token → S2/S3;
`willPresent` → the suppression rule of §3.4; `didReceive` → route to the responder (S6) or the tap
target (S7).

**Acceptance:** Tier 2 — a launch-argument fixture injects a fake APNs token and asserts the Keychain
record contains the lowercased hex token and the right environment; a simulated `willPresent` for the
**current** host returns "suppressed" and for a **foreign** host returns "shown".

### S5 — Server side: the push-device route and the envelope emitter

Lives outside this repo — in `opencode-official/` (a `POST /push/device` + `DELETE /push/device/:id`
route) or in a plugin beside the server (the envelope emitter). The plugin is preferred: it needs no
core patch and survives server upgrades.

**Acceptance:** a contract check (same shape as `scripts/v2_contract_check.py`) asserts
`POST /api/push/device` with a body returns `204` and that `DELETE /api/push/device/:id` returns `204`;
the plugin's emitter, driven by a fixture event stream, produces exactly one envelope per
`permission.asked` containing `registration_id`, `event`, `session_id`, `request_id`, `api`,
`action_class`, `occurred_at` — and **no** field carrying the permission's patterns, the request's
description, the session title, or any message text. A `session.error` whose `error.name` is
`AbortError` produces **no** envelope.

### S6 — Lock-screen approval for permissions (the background responder)

New `Services/PushApprovalService.swift` implementing §3.2 steps 1–7, plus
`Models/PushApprovalOutcome.swift`. It builds its own short-lived `APIClient` for the envelope's host
(never the shared `AppState.apiClient`), reads the Keychain credential, re-reads the pending
permissions, validates, and replies `.once` only.

**Acceptance:** Tier 1 — given a fixture pending list containing the request, exactly one POST is sent
and its body carries `"once"`; given a list without it, **no** POST is sent and the outcome is
`alreadyHandled`; given a request whose action maps to a different `action_class`, **no** POST is sent
and the outcome is `classMismatch`; given a credential-access failure, **no** POST is sent and the
outcome is `unauthorized`; given a `404` on the reply, the outcome is `alreadyHandled` and not an
error.

### S7 — Notification tap routes to the session

`AppState.pendingPushTarget` + `processPendingPushTargetIfPossible()`, mirroring the
`pendingDeepLink` pattern (`AppState+DeepLinks.swift:38-88`); the tap resolves
`registration_id → HostProfile`, switches host when needed (`switchHostProfile`), and selects the
session; a `404` surfaces the existing "session unavailable" error.

**Acceptance:** Tier 2 — a fixture push for a session on the current host opens that session after the
connect completes; a fixture push for a session on a **different** host switches to that host first;
a fixture push for a deleted session shows the existing error and leaves no half-open session.

### S8 — Settings surface

A Settings section: push state for the current host, an enable/disable switch (which drives
`requestAuthorization`, S3's register, and S3's unregister), and a per-host indicator. New copy goes
through `L10n` in both `en` and `zh-Hans`.

**Acceptance:** Tier 2 — the row renders the current registration state for the current host; turning
it off calls unregister and removes the Keychain record; turning it on with the authorization denied
renders the "denied" state and registers nothing.

### S9 — End-to-end spike on a real device (not a PR)

Manual validation: a relay with a sandbox APNs key, one host, one device. Push a `permission.asked`
envelope; the notification arrives; the lock-screen `allow_once` action replies; the agent resumes.
The simulator can drive the same loop without a relay via
`xcrun simctl push <device> <bundle-id> <payload>.apns`, which is the cheapest way to iterate on the
notification's look and on the tap routing.

**Acceptance:** a recording of the four steps (push arrives, lock-screen approve, agent resumes,
in-app card gone on next foreground) plus the raw APNs response code.

### Ordering

```text
S1 ──▶ S2 ──▶ S3 ──▶ S4 ─┬─▶ S6 ──▶ S7 ──▶ S8
                        └─▶ S5 (server side; runs in parallel, no code dependency)
S9 runs last, after S5 + S6 + S7.
```

S1–S3 are pure client logic with no Xcode-project changes, so they can be landed in parallel with the
server work. **S4 is the only slice that touches the Xcode project** (entitlements, background modes,
the app delegate) and it is the slice most likely to collide with a concurrent `xcodebuild` run.

---

## 6. Risks and open questions

### Open questions

| # | Question | Decision it blocks |
|---|---|---|
| **Q1** | Where does the APNs provider key live in the shipping topology — a first-party relay, a self-hosted relay the user runs, or both? Does the client ship with a default endpoint, or require the user to configure one? | S3's endpoint model, S8's Settings copy, and whether the feature is usable at all for a self-hosting user. **Recommendation:** configurable endpoint, first-party default, self-hosted supported. |
| **Q2** | Which V1 permission-reply route is canonical — the deprecated `POST /session/:sid/permissions/:pid` the client calls today, or `POST /permission/:requestID/reply` with `{reply, message?}`? And is the decision vocabulary (`response` vs `reply`) stable? | S6. The background responder must hard-code one route and one body shape; the wrong guess is a 404 at the worst possible moment. |
| **Q3** | Which `action_class` values may carry a lock-screen `allow_once`? The recommendation is `read` only. `exec` clearly not; `edit` and `network` are judgement calls. | S6's allowlist, the `opencode.permission` category's action set, and the fixed notification copy. This is a product/security decision, not an engineering one. |
| **Q4** | Is a question ever answerable from the lock screen? Currently excluded (§3.5) for two independent reasons. | The `opencode.question` category design. If yes, the server needs a reply route that takes an option *index* rather than a value, so the client does not need the form table. |
| **Q5** | What should happen when the lock-screen approve fails because the phone has no network? Recommendation: fail closed, report "no connection", and do **not** queue the decision. | S6's outcome mapping and S8's copy. |
| **Q6** | Is a lock-screen approve supported for an **SSH-tunnel** host? The tunnel is torn down on background (`AppState+BackgroundVoice.swift:157-175`), so a background reply would have to re-handshake SSH inside a ~30 s window. Recommendation: SSH hosts get "Open in OpenCode" only. | S6's host filter, and whether the feature is honest about what it supports. |
| **Q7** | Registration TTL and refresh policy: 30 days? Refresh on every connect, or only on token change? | S2/S3's expiry logic and the endpoint's garbage collection. |
| **Q8** | Should the app badge reflect pending approvals across hosts (the app already computes `sessionAttentionCounts`, `AppState.swift:771`)? | The badge policy. Deferred out of scope for v1; it interacts with `UNUserNotificationCenter.setBadgeCount`. |

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **The push payload becomes a covert channel.** A compromised server (or plugin) could push text into the user's lock screen. | Privacy: content leaks to the lock screen and to APNs. | The relay renders the body from a fixed table only. The server cannot supply text. The client's envelope decoder rejects unknown keys. |
| **A mis-classified `action_class` causes a blind approval of a `bash` request.** | Privilege escalation: the user grants command execution believing they granted a read. | The responder re-reads the request and compares the class (§3.3 step 2); a mismatch aborts. The allowlist is `read` only. "Allow always" is unreachable from the lock screen. |
| **The background reply runs in a narrow, OS-controlled window.** | The action silently fails. | The responder must complete inside the window and call the completion handler; failures are reported as a notification update and drained on the next foreground. **The exact window duration is unverified — needs check** against the current iOS documentation. |
| **The Keychain accessibility class is changed later** (e.g. to `WhenUnlocked` for extra safety). | Every background reply dies on a locked device, silently. | Record the constraint in an ADR (§3.7); add a Tier 1 test that asserts the credential-accessibility constant, so a change breaks a test rather than the feature. |
| **A stale notification approves the wrong thing.** | Wrong request approved. | The responder re-reads and confirms the exact `request_id` is still pending before replying; a mismatch aborts. |
| **The APNs provider key leaks from the relay.** | Full push spoofing for every user. | The key lives in exactly one audited service; it is never distributed to user machines (§1.2); the relay holds no user content; the blast radius is bounded by the relay's own access control. |
| **Token churn** (rotation, reinstall, restore-from-backup) leaves stale registrations on the endpoint. | Pushes to a device that no longer uses them. | TTL expiry on the endpoint; re-registration replaces rather than appends; `410` deletes the local record. |
| **The V1 event vocabulary has no discrete "task finished" event.** | A completion push is derived from a status transition and may be missed across a reconnect. | The provider reconciles via `GET /session/status` after a reconnect, with the same dedup key. Accepted as a known imprecision for V1. |
| **The server's `permission.asked` payload shape is not pinned for V1.** The client's parser is defensive (`PermissionController.parseAskedEvent` falls back across `request`/top-level and `permissionID`/`id`). | A provider that trusts a specific field could mis-target a push. | The provider reads the same defensive way; the client's re-read in §3.2 is the real guard. **The exact V1 payload shape is unverified — needs check** against a live V1 server. |
| **The V2 plugin API parity with the V1 plugin API is unverified.** The research doc verified the plugin `Hooks.event` interface against V1 sources; `opencode-official/` is not checked out in this workspace now. | The envelope emitter may need a different hook on V2. | Verified in S5 against the live server before the emitter is written. **Unverified — needs check.** |

---

## Appendix A — Evidence index

Every claim in this document that is about *this codebase* is traceable to one of these.

| Claim | Where |
|---|---|
| No `UNUserNotificationCenter` / push / background-task code exists | grep over `OpenCodeClient/` for `UNUserNotificationCenter\|UserNotifications\|registerForRemoteNotifications\|aps-environment\|BGTaskScheduler` → no matches |
| Only `audio` is a declared background mode; no entitlements file exists | `OpenCodeClient/Info.plist` (`UIBackgroundModes`), `project.pbxproj` (no `CODE_SIGN_ENTITLEMENTS`) |
| The app is a bare SwiftUI `WindowGroup` with no app delegate | `OpenCodeClientApp.swift:15-37` |
| SSE is torn down and the SSH tunnel closed on background | `AppState+BackgroundVoice.swift:157-175` |
| V1/V2 event vocabulary and the translation table | `Services/V2EventTranslator.swift:97-124`; `AppState+SSE.swift:411-430`; `docs/v2_server_compatibility.md:56-57, 319-322` |
| "Completed" is a status transition on V1, a discrete event on V2 | `AppState+SSE.swift:242-244`; `V2EventTranslator.swift:36-43` |
| A user abort is distinguished from a real failure | `AppState+SSE.swift:446` |
| The real reply method names | `AppState+Permissions.swift:16, 56, 71`; `Services/APIClient.swift:936, 985, 1020` |
| `PermissionResponse` = `once / always / reject` | `Services/APIClient.swift:895-899` |
| The V2 form reply needs the in-memory `formReplyTable` | `Services/APIClient.swift:988-996, 40` |
| The reply routes per generation | `Services/APIClient.swift:921-1037`; `docs/v2_server_compatibility.md:34-38, 169-173`; `docs/OpenCode_Web_API.md:175, 239-248` |
| The V1 permission reply route is deprecated | `docs/OpenCode_Web_API.md:175` |
| The in-app card renders the granted scope and never clips it | `PermissionCardView.swift:42-53` |
| The in-app arrival path is SSE + haptic | `AppState.swift:1286-1310`; `AppState+SSE.swift:411-427` |
| Host identity in `UserDefaults`, credentials in the Keychain | `AppState.swift:212`; `Models/HostProfile.swift:65-69`; `AppState+HostProfiles.swift:595-597` |
| Deleting a host deletes its Keychain password; duplicating copies it | `AppState+HostProfiles.swift:404-431, 433-455` |
| The credential store is `AfterFirstUnlockThisDeviceOnly` | `Utils/KeychainHelper.swift:46, 55` |
| The injectable credential seam used by tests | `AppState+HostProfiles.swift:8-24` |
| The deep link is strictly parsed and resolved | `Utils/OpenCodeDeepLink.swift:37-58`; `AppState+DeepLinks.swift:38-88` |
| The host-switch path exists and re-runs the connection flow | `AppState+HostProfiles.swift:382-391` |
| The prior push research and its payload rules | `docs/features/push_notifications/research.md` (esp. `:66, 124, 149`) |
| The wire-contract conventions this document follows | `docs/features/client_capabilities/protocol.md` |

## Appendix B — Unverified claims

Marked rather than asserted, per this repo's rule:

- The exact background execution window Apple grants a notification-action handler. Needs a check
  against the current iOS documentation before S6 is sized.
- The precise shape of a V1 `permission.asked` payload (the client's parser is deliberately tolerant of
  several shapes). Needs a check against a live V1 server.
- Whether the OpenCode **V2** server exposes a plugin `Hooks.event` interface equivalent to V1's.
  Needs a check against a live V2 server (`opencode-official/` is not checked out in this workspace).
- Whether the V2 server will add a `session.idle`-equivalent for *task* completion that is distinct
  from "the turn ended" — the current `session.idle` means the turn ended, which is what a push wants,
  but the server may also have a "background task finished" notion that is not exposed.
- Whether APNs token rotation frequency warrants the 30-day refresh in Q7.

## Appendix C — Follow-ups outside this document

- `docs/README.md` needs a row for `features/push_approvals/` (the index is the entry point per the
  docs conventions) — not changed here, since this document was written as a single new file.
- `docs/features/push_notifications/research.md` should get a pointer to this document once the
  topology decision (Q1) is made, so the two do not drift.
- If Q2 is answered, the answer belongs in `docs/v2_server_compatibility.md` and
  `docs/OpenCode_Web_API.md`, which are the living wire contracts.
