# V2 server support + `opencode pair` QR onboarding

Status: implementation plan. Ground truth measured 2026-10-24 against upstream `v2.1.3`
(`opencode --version` on this machine) and against the live server at `127.0.0.1:4096`.

## Problem

The app speaks only the V1 API (`GET /global/health`, `/session`, `/session/:id/message`,
`/provider`, …). A V2 server does **not** serve those routes: every V1 path returns the
packaged SPA `index.html` with `200 text/html`. The app therefore cannot connect to a V2
server at all — the health probe decodes HTML as JSON and fails.

Measured on `v2.1.3` (`/openapi.json` has 121 paths):

| Request | Result |
|---|---|
| `GET /global/health` | `200` `text/html` (SPA shell) |
| `GET /session` | `200` `text/html` (SPA shell) |
| `GET /api/info` | `200` JSON `{"version":"2.1.3",…}` |
| `GET /api/session?limit=1` | `200` JSON `{"data":[…]}` |
| `GET /api/health` | `404` |

So the whole client surface must move to `/api/*` for V2 hosts.

## Deltas vs `docs/v2_server_compatibility.md`

That spec was measured on `v2.0.18`. Re-measured on `v2.1.3`:

1. **Archive write now exists.** `PATCH /api/session/:id` with `{"archived": true}` returns
   `204` and persists `time.archived`; `{"archived": false}` restores it. The old spec says
   "no write route" — that is stale. The V1-shaped body `{"time":{"archived":1}}` is still
   ignored, so the V2 body is a top-level boolean.
2. **Todos still have no route.** `GET /api/session/:id/todo` is `404` and there is no
   `todo.updated` event. `sessionTodos` stays `[]`.
3. **`/api/project/current` is `404`**; current project comes from `GET /api/location`.
4. **`GET /api/session/:id/message?limit=`** takes `limit`; `before` is not in the V2 schema.
5. **`GET /api/session/active`** returns `{"data":{"<sessionID>":{"type":"running"}}}`.
6. **V2 event names differ** from V1: `session.created` / `session.renamed` /
   `session.metadata.updated` replace `session.updated`; `session.text.delta` /
   `session.text.started` / `session.text.ended` replace `message.part.delta` /
   `message.part.updated`; `session.execution.failed` replaces `session.error`;
   `form.created` / `form.replied` / `form.cancelled` replace `question.*`.

The repo gate `scripts/v2_contract_check.py` passes `45/45` against the live `v2.1.3` server.
It is the wire-level gate for this work.

## Approach

Mirror upstream's own client (`packages/app/src/servers/connect/pairing.ts`,
`packages/app/src/runtime/server/api.ts`) rather than inventing a shape:

- **Detection**: probe `GET /global/health`, then `GET /api/info`. V1 only when health is
  `200` JSON with a string `version` and `healthy: true`. V2 when `/api/info` is `200` JSON
  with a string `version`. HTML is not V1 — that is exactly the V2 case. The generation is
  stored per host profile and bound to the host URL (changing the URL clears it).
- **Route + body mapping**: a `V2Mapper` translates V2 envelopes (`{"data":…}`) into the
  app's existing `Session` / `MessageWithParts` / `Part` / `FileDiff` models, so the UI,
  `MessageStore`, and SSE handlers keep their current shapes.
- **Pairing**: `opencode pair` prints `http://<host>:<port>/auth/connect/<code>` links and a
  QR code carrying `{"code":…,"urls":[…]}`. The app redeems the code with
  `GET /auth/connect/<code>` and `Accept: application/json` → `{"token":"…"}`. The token is
  a **session token usable as the Basic-auth password** with username `opencode`
  (verified live). The code is single-use and expires in 5 minutes.

## Scope

In scope:
1. `ServerGeneration` detection + per-host storage.
2. `V2Mapper` for every route the app already calls.
3. V2 request routing in `APIClient` (paths, bodies, status codes).
4. V2 SSE event translation into the existing handler shapes.
5. `opencode pair` onboarding: camera QR scan + paste-link, redeem code, save the host with
   the token as its password.

Out of scope (explicitly): a V2 todo UI (no server API), archive UI changes beyond the
now-working write, and `opencode pair --remote` (OpenTunnel).

## Files

| File | Change |
|---|---|
| `OpenCodeClient/OpenCodeClient/Services/ServerGeneration.swift` | new — detection probe |
| `OpenCodeClient/OpenCodeClient/Services/V2Mapper.swift` | new — V2 → app model mapping |
| `OpenCodeClient/OpenCodeClient/Services/APIClient.swift` | route + body branching on generation |
| `OpenCodeClient/OpenCodeClient/Services/PairingClient.swift` | new — redeem `/auth/connect/:code` |
| `OpenCodeClient/OpenCodeClient/Models/HostProfile.swift` | `apiGeneration` field |
| `OpenCodeClient/OpenCodeClient/AppState+SSE.swift` | V2 event translation |
| `OpenCodeClient/OpenCodeClient/Views/HostProfilesView.swift` | pair-link + QR scan entry point |
| `OpenCodeClient/OpenCodeClient/Views/Support/QRScannerView.swift` | new — camera scanner |
| `OpenCodeClient/Info.plist` | `NSCameraUsageDescription` |
| `OpenCodeClient/OpenCodeClientTests/V2MappingTests.swift` | new — mapper unit tests |
| `OpenCodeClient/OpenCodeClientTests/PairingTests.swift` | new — pairing tests |

## Test gate

- `scripts/v2_contract_check.py` against a live V2 server — the wire contract.
  Measured `45/45` against the live `v2.1.3` server.
- `./scripts/test_unit.sh` — unit tests, including mapper tests over saved V2 bodies.
  New suites: `V2MappingTests`, `PairingTests`, `V2EventTranslationTests`.

## Implementation notes

- The client probes the generation on the first request and remembers it for
  the life of the client. `HostProfile.apiGeneration` stores the result so a
  reconnect does not probe again; changing the host address clears it.
- V2 lists permissions and questions **per session**, while V1 lists them
  globally. The client keeps the sessions it has seen and walks them.
- V2 answers a form with `{key: value}`, where the value is the option's
  `value`, not the label the app collects. The label → value mapping is kept
  per form in `FormReplyEntry`.
- V2 has no todo route, so `sessionTodos` returns `[]` and the todo panel stays
  empty. That is the one gap the V2 parity gap list still holds.
- The pairing token is a session token: it is accepted anywhere the server
  password is, so it becomes the host's Basic-auth password with the username
  `opencode`.
- The Car Mode session list has no V2 root page route. It uses
  `GET /api/session?archived=true&limit=50` and returns no next cursor, because
  V2's cursor is an opaque string while the app's page cursor is an integer
  offset. The list shows the first page; it does not page.
- The generation is probed once per connect, in `testConnection`, not per
  request: a client that was never probed keeps its historical V1 behaviour,
  so the request sequence of a V1 host is unchanged.
