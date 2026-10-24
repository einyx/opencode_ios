# iOS Client Capabilities RFC

## Implementation Conclusion

The V0 stage introduces in the client a "local-first" callback path that is independent of the regular Session deep link. The traditional `opencode://session/...` still has to wait for the server to establish a connection before resolving the target session; `opencode://client-action-return/...` instead forces the Pending record to be consumed locally and dropped into the Outbox first, and only then waits for the network to become available before submitting to the server. This design guarantees that even if OpenCode is suspended by the system or the process is killed during the Health export, the correlation context is not lost.

## Components

- `Models/CarMode.swift`: implements fault-tolerant Action Union decoding based on `type`; strongly types the known Maps and Health actions, and still keeps the complete `speech` content when an unknown Action is encountered.
- `Models/ClientCapability.swift`: defines the permission model, the callback record and the Health result enumeration.
- `Services/ClientCapabilityCallbackStore.swift`: is responsible for Pending/Outbox management, atomic file writes, timeout expiry determination, the Single-flight limit and bounded capacity cleanup.
- `AppState+ClientCapabilities.swift`: hosts the authorization/authentication, the Handoff jump, the callback consumption, the query-before-retry and the Continuation result projection logic.
- `Utils/OpenCodeDeepLink.swift`: contains two mutually independent, strictly bounded parsers, one for Session and one for Callback.
- `APIClient.promptStructured`: supports passing an optional deterministic `messageID` parameter.

## State and Correlation

On-disk storage is divided into only two discrete stages: the Pending stage waits for the external Callback to return, while the Outbox stage means the Callback has passed local acceptance but the Continuation has not yet been confirmed complete with the server. Every persisted record is strictly bound to `hostProfileID + carContextKey + sessionID`; when handling a Callback it never reads the volatile `currentSessionID`, and the original delivery target does not change because the user has switched to another Workspace.

While the permission sheet is up, the user may switch Host on their own. Therefore the request captures the current Host Profile synchronously when it is issued; when the user taps allow, if the currently connected Host has changed, the client directly refuses to launch the external app, eliminating the risk of binding the original Session to a new Host. Records in the Outbox trigger a network submission only when the Host that owns the record is exactly the same as the currently active Host and is in a connected state; silent cross-Host submission is strictly forbidden.

## Idempotency Strategy

The `callback-id` is both the unique name of the Pending file and a one-time Bearer Token. When consuming a callback, the transactional order is "write the Outbox first, then delete the Pending"; if a record with the same name already exists in the Outbox, the duplicate Callback is simply ignored. When submitting the Continuation, a fixed ID `msg_client_<callback-id>` derived from the callback-id is used, and before every retry the session history is fetched for validation, so that when the server has already accepted the request successfully but the HTTP response was lost in transit, the retry does not trigger a second round of model inference.

In the normal execution path of the existing synchronous interface, the server directly returns the Assistant response. If the User Message of that Continuation already exists in the history but the Assistant has not finished being generated, the client keeps the Outbox and waits for the app cold start, the return to the foreground, or the network reconnect to do the reconciliation check again; it never blindly resends the packet.

## UI and Lifecycle

The first time a Health action is triggered, the system shows an authorization sheet that cannot be dismissed with a swipe-down gesture, forcing the user to make an explicit choice among "Cancel", "Allow Once" and "Always Allow". The Settings screen reflects the current authorization state in real time and only offers the operation of revoking an existing "Always Allow" permission.

The Cleanup/Retry pipeline is triggered on app cold start, on return to the foreground, on network connection recovery, when a new Pending is created, and when a Callback message is received. The local acceptance of a Callback does not depend on network connectivity at all, while the network submission must wait for the corresponding Host to be connected. The execution result of the Continuation is projected as a Speech/TTS announcement only while the user is still in the original Car context; if the user has already switched to another context, the original session record is only quietly updated in the background, avoiding disturbing the task the user is currently doing.

## Verification

The Tier 1 and Tier 2 tests comprehensively cover fault-tolerant Action decoding, strict Callback parsing, standard-compliant Launch URL construction, Pending/Outbox expiry determination and duplicate-consumption prevention, the allow-once authorization flow, Continuation recovery in the original session, and deterministic Message ID generation. The Fixture-based XCUITest focuses on the permission Reason display and the interaction branches of the three local authorization decisions. For the specific test commands see `docs/tests.md`; the results of this round of verification have been fully archived in `docs/WORKING.md`.
