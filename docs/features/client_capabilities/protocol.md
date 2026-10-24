# iOS Client Capability Protocol

> Last reviewed: 2026-08-23 · checked against the current OpenCodeClient implementation

## Protocol Scope

This protocol specifies the behavioral standard for OpenCode iOS acting in the role of capability consumer, covering structured action parsing, Health Quantification cross-app handoff, callback result acceptance, and the full lifecycle of the original Session continuation. The current V0 version registers only one concrete capability: `health_quantification.export_all`.

## Structured Action

In Car Mode, the model uniformly returns a `CarResponseEnvelope` container (containing the `version`, `status`, `speech`, `confirmation`, and `clientActions` fields), where the `clientActions` array may contain at most 1 operation. The Schema for the Health export action is defined as follows:

```json
{
  "id": "health-export-1",
  "type": "health_quantification.export_all",
  "reason": "Sync last night's sleep data to complete the sleep analysis"
}
```

Field constraints (defined in `CarModeProtocol.outputFormat`, which declares `additionalProperties: false`):

- `id`: between 1–100 characters in length, used only for link diagnostics and request deduplication.
- `type`: always the fixed value `health_quantification.export_all`, serving as the sole Key for action dispatch routing and permission checks.
- `reason`: between 1–240 characters in length and non-empty after trimming leading and trailing whitespace, used only to display the authorization explanation in the client's local UI.

The model is strictly forbidden from specifying a URL or continuation text in its response; the callback URL and the parameters it carries are always constructed locally and independently by OpenCode iOS (the System Prompt explicitly forbids the model from fabricating URLs on its own). For an unknown `type`, the parsing layer routes it to the `unknown` enum branch and keeps the `speech` broadcast content from the outer Envelope, but the client never triggers the execution of that action.

## Authorization and Dispatch (reviewed and updated 2026-08)

The permission state `ClientCapabilityPermission` has two values: `ask` (ask every time, by default) and `allow_always` (always allow). It is persisted in UserDefaults under the Key `clientCapability.healthExportAll.permission.v1`; the user can manually reset it back to `ask` in the Settings screen.

- After the model returns the Health export action, `requestClientCapability` triggers the authorization logic: if the permission is `allow_always`, it dispatches directly; otherwise it builds the `pendingClientCapabilityRequest` state and presents the `ClientCapabilityPermissionView` authorization dialog, letting the user choose between "Allow once", "Allow always", and "Cancel".
- In the `dispatchClientCapability` flow, the system first calls `createPending` to generate a `callbackID` and persist the local Pending record, then opens the target Launch URL via `UIApplication.shared.open`; if the launch fails, it immediately cleans up the Pending record just created and throws a `launchFailed` error.
- For the same capability, if a non-expired Pending or Outbox record already exists locally, `createPending` throws the `duplicateCapability` error directly, and the UI layer simultaneously shows the "this capability is already running" notice (corresponding to L10n `capabilityAlreadyRunning`), avoiding concurrent duplicate requests.
- Every persisted record is strictly bound to the Host Profile context at the moment the request was initiated: the persisted `hostProfileID` and `hostConfigurationSignature` (a SHA-256 hash computed over the Transport mode, Server URL, Basic Auth username, and SSH configuration).

## Launch Contract

```text
healthquantification://export-all?callback=<percent-encoded-callback-url>
```

The decoded callback format is strictly fixed as follows:

```text
opencode://client-action-return/<callback-id>
```

The `callback-id` is generated from 32 random bytes encoded as unpadded base64url; in the current implementation its length is fixed at 43 characters. The receiver (consumer) validation rule allows 43 to 128 characters composed of ASCII letters, digits, `-`, and `_`. This ID serves both as the unique request identity for this request and as a one-time authorization credential (bearer token). OpenCode must first persist the Pending record to local disk, and only then call `UIApplication.open` to launch the external app; if the launch fails, it rolls back and deletes that Pending record.

## Return Contract

```text
opencode://client-action-return/<callback-id>?status=success&sent=1240&upserted=1240
```

The list of accepted Query fields (where `status`, `sent`, and `upserted` are required; `failed` and `error_code` are optional):

| Field | Required | Allowed values |
|---|---|---|
| `status` | Yes | `success`, `partial`, `failed`, `busy` |
| `sent` | Yes | a decimal integer from 0 to `Int32.max` |
| `upserted` | Yes | a decimal integer from 0 to `Int32.max` |
| `failed` | No | a duplicate-free subset of `sleep,vitals,body,lifestyle,activity,workouts`, comma-separated |
| `error_code` | No | `category_failure`, `export_in_progress`, `invalid_server_url` |

Any request containing unknown Query fields, duplicate fields, an empty Query, UserInfo, a Port number, a Fragment, extra Path segments, a non-canonical Callback ID (that is, a string that differs after URL decoding), or an illegal enum value is strictly rejected by the parser. The existing Session deep link (`opencode://session/<id>`) is likewise strictly forbidden from carrying any Query, Fragment, UserInfo, or Port, and the Session ID must be prefixed with `ses_`, have a total length between 5–256 characters, and contain only characters from the `[A-Za-z0-9_-]` set.

## Local Persistence (reviewed and updated 2026-08)

```text
Application Support/ClientCapabilityCallbacks/
  Pending/<callback-id>.json
  Outbox/<callback-id>.json
```

The Pending record (its data structure declares `version: 1`) fully stores `callbackID`, `capability`, `hostProfileID`, `hostConfigurationSignature`, `carContextKey`, `sessionID`, `assistantMessageID`, `actionID`, the deterministic `continuationMessageID` (fixed as `msg_client_<callback-id>`), the `createdAt` creation time, the `expiresAt` expiry time (computed as `createdAt + 15 minutes`), and the `result` execution result (initialized to null).

When a valid Callback request is received, the system validates the Pending record and migrates it to the Outbox directory (filling in the `result` content and safely deleting the original Pending file); Outbox records are kept locally for at most 6 hours (counted from the record's `createdAt` time). A Callback received twice must never produce a second Continuation record (when a record with the same name already exists in the Outbox, the `consume` method returns nil directly). The entire callback directory may hold at most 50 records (Pending and Outbox counts combined). Records with corrupted data, an unknown version, an illegal filename, or that have expired are automatically deleted during the bounded cleanup flow; if the number of valid records still exceeds the 50-record limit, records are discarded one by one starting from the earliest according to the `createdAt` timestamp. All disk writes go through the "write a temporary file + atomic move" mechanism, which prevents file corruption caused by concurrent writes.

## Continuation Contract (reviewed and updated 2026-08)

The client is responsible for sending the following structured message to the original Session recorded in the Pending record:

```json
{
  "kind": "client_action_result",
  "capability": "health_quantification.export_all",
  "invocation_id": "<callback-id>",
  "status": "success",
  "sent": 1240,
  "upserted": 1240,
  "failed_categories": [],
  "error_code": null
}
```

The `POST /session/:id/message` request explicitly passes a `messageID` deterministically generated from the Callback ID (that is, `continuationMessageID = msg_client_<callback-id>`). The request payload also carries `system` (using the preset `clientResultSystemPrompt`), `format` (matching the Car Mode json_schema constraint), `agent: "build"`, and the Car Mode-specific model configuration.

Before actually submitting the network request, the client must first query the current session's message history to perform an idempotency check:

- If the session history does not yet contain a User Message with `id == continuationMessageID` → submit the request to the server directly.
- If that message already exists but the corresponding Assistant reply has not finished generating → keep the local Outbox record and poll for reconciliation every 2 seconds, up to 15 attempts; if it is still incomplete after the timeout, mark this Continuation as failed (the Outbox is kept locally for later retries).
- If the corresponding Assistant reply has been fully generated → validate the structured response data and, once it passes acceptance, delete the local Outbox record entirely.

Both the network submission and the result acceptance are constrained by strict Host and route guards: the `isConnected` connection state, `currentHostProfileID` matching the Host Profile in the record, `hostConfigurationSignature` matching the current runtime configuration exactly, and the `deepLinkRouteID` route generation not having jumped must all hold at the same time; if the original Host Profile has been deleted by the user, the Outbox record is silently cleaned up (no error is thrown); if a configuration change is detected (signature mismatch), the Outbox is deleted and the error `continuationFailed` is reported externally.

When the API returns a 401, 403, or 404 status code, it is judged to be a terminal failure: the client deletes the Outbox and marks it failed. For other network hiccups or 5xx server errors, the Outbox is kept, awaiting a network reconnect or a safe retry on the next trigger, until the record expires.

A Synthetic result synthesized by the client does not constitute a new user authorization in semantic terms. The response payload produced by the Continuation must not carry any Client Action (that is, `clientActions` must be empty), and it must be a completed Assistant message in the same Session, satisfying Envelope `version == 1` with a non-empty `speech` field. The AI must then re-read the freshness and sample metrics of the data from the Health server based on that result, and finally answer the user's original question.

## Security Boundary (reviewed and updated 2026-08)

The V0 architecture explicitly accepts the residual risk that, in theory, a malicious app on the same device could hijack the listening side of the Custom URL Scheme mechanism. The `callback-id` only proves that the caller holds the one-time Bearer Token; by itself it cannot serve as an absolutely trustworthy credential that the underlying health data has truly finished syncing. The Callback URL is responsible only for conveying the summary execution result of the export operation (`status`, `sent`, `upserted`, `failed`, `error_code`); it never carries concrete health data details, nor does it trigger any authorization-change side effects. In the Continuation phase, the System Prompt forces the AI to actively pull the real data from the server again for verification, instead of unconditionally trusting the status description carried in the URL. If, in the future, the forgery risk from malicious apps on the same device needs to be fully defended against, the communication channel should be upgraded to Universal Links based on Associated Domains, rather than blindly expanding the data payload carried under the Custom Scheme.
