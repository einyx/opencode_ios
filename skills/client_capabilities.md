# OpenCode iOS Client Capabilities

## Goal

Add a typed, authorizable, recoverable device capability to the OpenCode iOS client without opening arbitrary URLs, without duplicating device domain logic into OpenCode, and without modifying the OpenCode server tool loop.

The authoritative wire contract is [`../docs/features/client_capabilities/protocol.md`](../docs/features/client_capabilities/protocol.md). Before making changes, read that file, `Models/ClientCapability.swift`, `AppState+ClientCapabilities.swift`, and the provider app's deep-link parser/result types first.

## When it applies

A client capability fits device entitlements, sensors, or on-device-only data. When a separate domain app, permission UI and long-lived state already exist, prefer a restricted deep link + callback; a lightweight system picker can be integrated directly into the OpenCode iOS app; work the server can already do keeps using a server tool/skill.

Do not move database queries, web APIs, email or Smart Home server calls into iOS just to make the shapes uniform. Until a new capability has a clear second consumer, do not extract a separate framework or a generic workflow engine.

## Hard boundaries

- Every action must be a stable typed case; the model must not supply a launch/callback URL.
- The local dispatcher, the permission key and the provider parser together form the allowlist; the system prompt is not a security boundary.
- A callback must use a high-entropy one-time ID, a short-lived Pending and a longer but bounded Outbox.
- Correlation must store the Host, context and session; falling back to the current selection is forbidden.
- A callback payload may only contain enums, bounded numbers and opaque IDs — never user data, tokens, server responses or free-text errors.
- A synthetic continuation is not user authorization; the returned envelope must not execute any client action.
- After a custom scheme callback the authoritative server data must be re-read; a callback is not a domain fact.

## Acceptance criteria for a new capability

- The structured schema, the Swift decoder and the unknown-action fallback are all covered by tests; an unknown action must not lose the whole assistant speech.
- First authorization, allow once, allow always, revoke and deny all have deterministic behavior, and permissions are persisted per capability name only.
- The launch URL is built by the client alone; the provider strictly restricts scheme/host/path/query.
- Pending is persisted before launch; a failed launch deletes it; expired, duplicated callbacks and corrupt files produce no continuation.
- An offline callback first goes to the Outbox and, after reconnecting, is submitted exactly once to the recorded original session.
- Deterministic message IDs and query-before-retry prevent a duplicated model turn.
- Provider and consumer agree on the success/partial/failed/busy fixtures, counts, categories and error codes.
- The original Maps action, the session deep link, the iPhone/iPad/visionOS platform gates and the full test suite do not regress.

## Known traps

- Do not model every action as a struct with many optional fields. The Health action has no `destination`; a fixed Maps shape makes the whole structured message fail to decode.
- Do not reuse the session deep-link queue that is only drained after connecting. When a callback arrives the app may not be connected yet, so the local consumption has to complete first.
- Do not insert a high-content section above the existing Car toggle in Settings; that once pushed the toggle out of the visible area in the fixture UI. Keep the current order of the key controls or update the scrollable test in sync.
- Do not delete the Outbox as soon as the continuation user message is seen. It only proves server admission; wait for the matching assistant response and do not resend in the meantime.

## Where the output goes

A new capability should update `docs/features/client_capabilities/protocol.md`, the matching product/RFC documents, the Swift registry/dispatcher, the provider contract and the tests. A design draft or a one-off investigation must not become a third source of truth for the protocol.
