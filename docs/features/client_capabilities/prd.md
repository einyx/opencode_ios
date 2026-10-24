# iOS Client Capabilities PRD

## Conclusion

OpenCode iOS allows restricted structured actions under Car Mode to be dispatched to the current iPhone for local execution, and the execution result is passed back to the original Car Session. The V0 stage opens only the `health_quantification.export_all` capability: when the AI finds that the health data stored on the server is missing or stale, it invokes the iPhone to open Health Quantification; after the data export completes it jumps back to OpenCode automatically and seamlessly continues the previous analysis task.

The core value of this capability is eliminating the tedious manual switching between different Apps, not evolving the iPhone into a general-purpose remote tool execution environment. The OpenCode Server, the regular Chat flow, the underlying HealthKit data collection and the health analysis protocol all stay as they are.

## User Flow

```text
The user requests a health analysis in Car Mode
→ The AI first checks data freshness with the server tool
→ When the data is missing or stale it returns a typed Health export action
→ OpenCode iOS shows the local authorization for the first time
→ Health Quantification performs Export All
→ The callback wakes OpenCode
→ OpenCode sends the normalized result to the original Car session
→ The AI re-reads the server data and completes the analysis
```

When the authorization sheet first appears, three options are offered: "Cancel", "Allow Once" and "Always Allow". The permanent authorization entry is persisted under a stable capability name, and the user can revoke it at any time in the Settings → Client Capabilities screen. The natural-language reason returned by the model is only used to explain the intent of this call to the user, and does not participate in permission rule matching.

## Product Boundaries

- In the V0 stage, it is open only to Car Mode and `health_quantification.export_all`.
- The model has no authority to specify the launch URL, the callback URL, the Session ID, the Host Profile or the expiry time.
- OpenCode itself does not read HealthKit directly; data collection, the system permission request, progress display and error messages remain the independent responsibility of Health Quantification.
- The callback only returns the execution status, the number of exported items, the failure category and fixed error codes; it never carries concrete health detail data or free text.
- The continuation stage must re-fetch the data from the Health Quantification server; receiving a successful callback response cannot be equated with the server-side data already being up to date.
- Explicitly not supported: regular Chat, Shortcuts, the Share Sheet, arbitrary custom URL invocations, the server-side remote-tool protocol, the background message Broker and multi-device collaborative routing.

## Success Criteria

- The user only needs to express the health analysis intent once; at most one local authorization confirmation is needed on the first trigger, with no need to manually tap Export All or re-ask the question.
- In abnormal scenarios such as the Health App not being installed, an expired callback, a duplicate callback, a network disconnect or a Host switch, the system always falls back defensively and never misdelivers the result to another Session.
- Globally, at most one Pending or Outbox record for a Health export is maintained at any time; a duplicate action does not trigger a second export.
- The permanent authorization supports manual revocation, and choosing cancel or allow-once produces no persisted configuration.
- Guarantee that the Maps action and the existing `opencode://session/<id>` deep link behavior have no regression whatsoever.

For the formal URL, the storage specification and the continuation protocol see [`protocol.md`](protocol.md); for the specific architecture and implementation trade-offs see [`rfc.md`](rfc.md).
