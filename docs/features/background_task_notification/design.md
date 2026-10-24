# Background Subagent Task Notification Rendering Design Draft

## Conclusion

When a background subagent completes, the server injects a **synthetic user message** into the parent session, whose content is an XML envelope of the form `<task id=... state="completed">`, containing the summary and the result body. The iOS client currently does not decode the `synthetic` field of TextPart, so such messages are rendered as raw XML inside the blue user bubble — one of the most glaring rendering flaws.

This UI element should be a **TaskNotificationCard** — a "subagent task receipt" card in the message stream: the first screen shows a status icon + status label + task title, the result body is rendered as markdown inside the card, and once expanded it can open the subagent session with one tap to audit the whole process. It is not a user bubble (it is system-injected, not something the user said), and it is not a tool card either (a tool card represents "one call", while this card represents "one asynchronous job delivered a result").

Identification uses a two-gate rule: the part carries `synthetic: true` **and** the text can be parsed as a `<task>` envelope → render the card; on parse failure, safely fall back to the current behavior.

The scope is strictly limited to task receipts. The server's other synthetic injection points (plan mode instructions, compaction continuation, MCP resources, etc.) are explicitly out of scope, and the user bubble rendering logic is left untouched; they are listed in the appendix as observation records only.

## Success Criteria

1. After a background task completes, a clearly-stated receipt card appears in the session (green for complete / red for failure); the task name and status are visible on the first screen, and no raw XML leaks through.
2. Tapping the card expands it, revealing the complete subagent result markdown (including workspace link resolution and images); overly long results are protected by the existing 12k preview limit.
3. After expanding, tapping the button opens the subagent session, reusing the existing selectSession path.
4. When parsing fails or the server is an older version (the payload has no `synthetic` field), the behavior safely falls back to the current state: no content swallowed, no crash.

## Data Path (Evidence)

### Server Generation

`opencode-official/packages/opencode/src/tool/task.ts`:

- `renderOutput()` generates a fixed XML envelope:
  ```
  <task id="{childSessionID}" state="completed|error|running">
  <summary>Background task completed: {description}</summary>   # "failed" when error
  <task_result> or <task_error>
  {markdown of the subagent's last text part}
  </task_result>
  </task>
  ```
- When a background task completes or fails, `injectBackgroundResult` injects a user message into the **parent session** via `ops.prompt`, with the text part carrying `synthetic: true`.
- When a background task starts, the `task` tool part in the parent message carries `state.metadata = { parentSessionId, sessionId, model, background: true, jobId }`, and the output is an envelope with `state="running"` (not handled by this design; see the appendix).
- `TextPart.synthetic` is an optional boolean in the V1 API schema (`packages/schema/src/v1/session.ts:108`).

Live verification (2026-09-27, local server on port 4096, `GET /session/:id/message`):

- The receipt is a **user-role** message with a single text part
- The part payload actually carries `synthetic: true`
- The body is a complete `<task>` envelope; that part has no `time` field

### Current Client State

- The `Part` struct in `Models/Message.swift` does not decode `synthetic`.
- `MessageRowView.userMessageView` renders the text parts of all user messages into the blue user bubble (`DesignColors.Brand.primary` fill + a 4pt vertical bar on the left); the XML text is judged by `hasMarkdownSyntax` and then goes through MarkdownUI, displayed as raw HTML-like text.
- The `task` tool part lands in the collapsed "N tool calls" row, and its output is the boilerplate text "Background task started..." (not handled by this design).

## Change List

### 1. Model layer: decoding `synthetic`

`Part` gains:

```swift
let synthetic: Bool?
```

`decodeIfPresent` semantics, with the default treated as `false`; a `Part.isSyntheticText` convenience property (`type == "text" && synthetic == true`). When the server does not include the field, the behavior is exactly the same as today.

### 2. Parsing layer: `TaskNotificationParser`

A pure function, in the same style as `ToolCardClassifier` (unit-testable, with no View dependency):

```swift
struct TaskNotification {
    let sessionID: String        // <task id>
    let state: TaskState         // completed | error | running
    let summary: String?
    let resultText: String       // content inside <task_result>/<task_error>
    var isFailed: Bool { state == .error }
}

enum TaskNotificationParser {
    static func parse(_ text: String) -> TaskNotification?
}
```

Parsing rules: locate the outermost `<task ...>` opening tag (leading whitespace is allowed at the start) and the `</task>` closing tag; `id` / `state` are taken from the opening tag's attributes; the body is the content inside the `<task_result>` or `<task_error>` range. Ranges are used throughout instead of a global regex, so that nested angle brackets inside the result body (such as XML fragments emitted by the subagent itself) never cause a wrong cut. If any step is missing, return `nil`.

### 3. Rendering layer: `TaskNotificationCardView`

Placed in `Views/Chat/`. The handling of user messages in `MessageRowView` changes to:

- Non-synthetic text part → goes into the user bubble as usual (with zero changes to the rendering logic);
- Synthetic text part whose `TaskNotificationParser` parse succeeds → `TaskNotificationCardView`;
- All other cases (including synthetic but failed parsing, and non-synthetic) → rendered as today, with a safe fallback.

`copyableText(for:)` is adjusted accordingly: for a receipt message that parses successfully, the result body is copied instead of the XML; the copy content of the user bubble is unaffected (this design does not change the user bubble logic).

## UI Specification (TaskNotificationCard)

### Visuals

- Card background: `DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for:))`, consistent with ToolPartView; corner radius `DesignCorners.medium`, padding `DesignSpacing.cardPadding`.
- Header row (first-screen information, not collapsible):
  - Status icon: completed → `checkmark.seal.fill` + `DesignColors.Semantic.success`; error → `xmark.seal.fill` + `DesignColors.Semantic.error`.
  - Status label: localized through L10n (`taskNotificationCompleted` / `taskNotificationFailed`), generated from `state`, and the English prefix "Background task completed:" inside the summary is **not** displayed as-is; the description remaining after stripping the prefix becomes the task title.
  - Task title: truncated to one line.
  - Right side: expansion chevron (built into DisclosureGroup, tinted brand primary).
- Expanded content: `resultText` goes through the existing `markdownText` path (workspace link resolution, image resolution, `textSelection(.enabled)`), and overly long content is protected by `LargeMessagePreview` (>12k truncation + a hint); an empty result shows the placeholder caption "No output".
- Default expanded state: **collapsed by default** (decided by the user on 2026-09-27, replacing the original "expand when ≤500 characters" design) — the main agent's subsequent message usually carries the digested conclusion, while the card body is reference material that the user taps to expand. The same behavior applies on both iOS and Android.
- `accessibilityIdentifier("task-notification-card")`; the navigation button uses `accessibilityIdentifier("task-notification-open-session")`; UI tests anchor on these two.

### Interaction

- **Primary action = expand/collapse**: tapping the whole card (header + content area) toggles the expanded state, consistent with ToolPartView / ThinkingCard. "Tap to navigate" is not made the primary action: reading the result is a high-frequency intent and expanding is reversible and free; navigation switches the current session context and is a low-frequency audit action. The high-frequency action owns the primary gesture.
- **Navigation = a labeled button inside the expanded area**: a button at the bottom of the expanded content with the copy "Open Subagent Session" (L10n `taskNotificationOpenSession`), in brand primary color and `DesignTypography.micro`. The button's hit area takes priority over the card's toggle gesture (a SwiftUI Button naturally takes priority inside a tappable container, the same mechanism as the file-open button inside the ToolPartView label).
- **No navigation entry in the collapsed state**: navigating requires expanding first and then tapping the button, i.e. two taps. This is acceptable for a low-frequency action; the header stays quiet (no unlabeled icon button), maintaining the information density of the first screen.
- **Navigation behavior**: `selectSession(subagentSessionID)` plus switching the project directory when necessary (the same path as session_finder's "Continue in This Session"); when the target session has been deleted, the existing error path (`state.sendError`) is used and the card itself is unaffected.
- Message row action menu: a synthetic receipt message does not show Edit-from-here (it is not a user turn), while Fork is kept.

## Edge Cases

- **Streaming truncation**: mid-stream the part is incomplete XML (no `</task>`) → the parser returns nil → render as today for now; once the part is updated to the complete version, it re-renders as a card. The part id is stable, and the replacement render leaves no state residue.
- **Old server**: the payload has no `synthetic` → decodes to nil → not synthetic → behavior identical to today (user bubble + raw text), with no content silently swallowed.
- **User manually pastes envelope-like text**: no `synthetic` marker → the two-gate rule does not hold → rendered normally as a user message, not hijacked into a card.
- **Multiple background tasks**: each notification is an independent message → an independent card, supported naturally.
- **Nested XML inside the result**: ranges locate the outermost envelope (see the parsing rules), covered by unit tests.
- **error state**: the `<task_error>` tag + `state="error"`, a red icon, and the body rendered as markdown as well.
- **Missing summary**: the title falls back to a short form of the task session ID.

## Implementation Scope

A single phase:

1. `Part.synthetic` decoding (`decodeIfPresent`).
2. `TaskNotificationParser` + unit tests.
3. `TaskNotificationCardView`: the completed/error states, expand/collapse (collapsed by default), markdown rendering, and the navigation button.
4. `MessageRowView` routing + the `copyableText` fix.
5. L10n keys: `taskNotificationCompleted` / `taskNotificationFailed` / `taskNotificationOpenSession` / `taskNotificationNoOutput`.

Explicitly out of scope (this phase): the running indicator and metadata decoding for the `task` tool part, and hiding or restyling other synthetic content inside the user bubble.

## Test Plan

- `TaskNotificationParserTests` (unit): completed / error / running / no summary / truncation (no closing tag) / non-task text → nil / nested angle brackets inside the result / empty result / leading and trailing whitespace.
- `MessageRowView` rendering unit tests: a synthetic message with an envelope → the card (asserting the a11y id); the same text without synthetic → the user bubble (fallback path); `copyableText` returns the result body for a receipt message.
- UI (Tier 4): tapping the card expands it and shows the markdown; after expanding, tapping the navigation button successfully switches to the subagent session (asserted via the child session title "…(@general subagent)" or the message content).
- Builds and tests run sequentially per the AGENTS.md convention (build → test).

## Appendix: Other Observed synthetic Injection Points (out of scope)

The remaining `synthetic: true` generation points in `packages/opencode/src`. This design does not handle them; if they later become a rendering defect, handle them with the same pattern (the already-decoded `synthetic` field + type-specific rendering) instead of inventing a separate mechanism.

| Location | Content | Form |
|---|---|---|
| `session/reminders.ts:34/45/64` | plan mode instructions (PROMPT_PLAN / BUILD_SWITCH / PLAN_MODE) | appended to the user's last message |
| `session/compaction.ts:541` | "Continue if you have next steps..." (carries `metadata.compaction_continue`) | standalone synthetic user message |
| `tool/plan.ts:68` | "The plan at X has been approved, execute the plan" | standalone synthetic user message |
| `session/prompt.ts:447` | "Summarize the task tool output above and continue" | standalone synthetic user message |
| `session/prompt.ts:485` | "The following tool was executed by the user" + tool part | boilerplate text + tool part |
| `session/prompt.ts:711+` | "Reading MCP resource: X (uri)" / resource body / omitted hint | appended to the user message |
