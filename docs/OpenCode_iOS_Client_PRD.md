# OpenCode iOS Client — Product Requirements Document

> Version 0.4 · Working Draft · Jul 2026

## 1. Product Positioning

OpenCode iOS Client is a native iOS remote-control app for the OpenCode server. It is not a standalone AI programming tool; rather, it is the **mobile extension** of an OpenCode instance running on a Mac/Server — letting users send instructions, monitor AI work progress, browse code changes, and switch models from situations far from their computer, such as the sofa or a commute.

Core design principle: **lightweight, fast, focused on reading and interaction**. All heavy configuration (such as Provider keys, MCP services, workspace settings) happens on the computer side; the iOS side only handles the necessary interaction and content consumption.

Beyond the technical architecture, the App's more fundamental goal is to close the human–machine interaction loop: **how to make the AI present its key decisions for human review, and, when necessary, support quick voice-driven intervention to correct course** — we call this model **Steer (command)**. In this model, the AI is responsible for execution and exploration, while the human is responsible for judgement and direction control. The App's value lies not only in status monitoring ("taking a look at what the AI is doing"), but in acting as a lightweight **decision-review and direction-control terminal** — each time the user opens the App, they mostly read Markdown reports, inspect embedded screenshots and artifacts, and issue new directional instructions by voice. It is fundamentally a steering tool, not a mere content-browsing tool.

Around the Steer paradigm, the App focuses on three interaction surfaces: the **Markdown conversation window** (the primary channel through which the AI reports progress and shows artifacts to the human), the **file card preview** (for quickly reviewing the AI's modifications, mostly documents rather than code), and **voice input** (so the user can efficiently issue directional instructions when away from a keyboard). Code syntax highlighting is not a core priority — the user's review focus is the basis and the results of the AI's decisions, not the typographic beauty of the code itself.

### 1.1 What It Is Not

This App explicitly does not do the following: edit code on the phone, run an OpenCode server on the phone, or replace the full Web UI. Its core scenario is this: at any moment while the AI is executing a task, the user can pull out the phone and read the freshly generated Markdown analysis report or code changes; as soon as they notice the direction has drifted, they can immediately correct course with a voice instruction.

### 1.2 Core Interaction Paradigm

#### Steer Paradigm

The App designs its interaction flow around the cognitive loop of "command":

1. **Surface** — The AI presents its decision process, reference code, executed commands, analysis reasoning, and final conclusions to the human through the Markdown window. Content is expressed in natural-language Markdown and supports embedding visual artifacts such as deployment-result screenshots, charts, and UI diffs, rather than merely piling up code. This is the primary information channel between the AI and the human.
2. **Review** — The human evaluates the soundness of the conclusions and the overall direction by reading Markdown. Most output consists of documents, analyses, or research content, which is naturally suited to Markdown; when necessary, code diffs can be inspected to confirm details. The human's core responsibility in this step is decision-making, not writing code.
3. **Steer** — If the execution direction deviates from expectations, the user can quickly issue a corrective instruction by voice (for example, "Stop, don't use inheritance — switch to composition instead"), or switch the model/Agent and start over. Instructions are entered in natural language, with no tedious typing.

The whole loop runs asynchronously on both ends: the AI executes on the computer, the human reviews on the phone, and the two sides need not stay in real-time sync — a unique advantage of mobile over desktop. But this also creates a practical pain point: when the AI pauses and waits for a human decision (for example, when it triggers the `question` tool), the user receives no notification while away from the App, easily leaving both sides waiting. The root fix is not in the UX interaction layer but at the iOS system-engineering level — push notification or Live Activity must be introduced to provide proactive reminders.

#### Markdown as the Interaction Window

Markdown is the **core information medium** through which the AI and the human interact in this App. The App is not a code editor that "happens to support Markdown"; it is a steering terminal that takes the Markdown reading and review experience to the extreme. The concrete design shows up as follows:

- **Code syntax highlighting is not emphasized**; Markdown rendering quality comes first (clear heading hierarchy, lists, links, code blocks, and embedded images). The user's core need is to review the AI's reasoning logic and delivered artifacts, not the appearance of the code.
- **Complete image embedding support**: the AI can embed deployment-result screenshots, generated charts, and UI comparison images directly into Markdown reports. The App ships with a dedicated Skill system that guides the AI in using these capabilities, and ensures that relative-path images behave consistently in Files preview and Chat rendering.
- **Content forms are not limited to programming**: the AI's output includes both code diffs and research articles, analysis reports, and system design documents. Markdown naturally carries all kinds of content well.

#### File Card Preview (Not a Code Editor)

The core positioning of file browsing is to **quickly confirm the AI's changes**, not "to write code on the phone". In the vast majority of cases the user jumps straight to the file preview through the tool/patch cards in the Chat window — the Files Tab is a fallback entry point, not the main workflow. For example, when the user sees an `edit_file` card in Chat, tapping the file path on the card opens the preview directly, with no need to switch to the Files Tab and dig through the directory tree layer by layer.

Document diffs carry far more review weight than code diffs: the AI already has good coding ability, so the human's review focus is mainly on document-level logic and architectural decisions.

This App explicitly does not do the following: edit code on the phone, run an OpenCode server on the phone, or replace the full Web UI. Its value lies in the core scenario of "pulling out the phone at any time to check the AI's current progress and, when necessary, quickly intervening to adjust direction".

## 2. Target Users and Use Cases

The target users are developers who use OpenCode daily (initially mainly the author). The key insight to make explicit is that heavy users do not open the App to "glance at the status" — every opening is a deep interaction: reading Markdown reports, talking to the AI by voice, and frequently switching between Sessions to track different tasks. The App's core value is letting the user keep judgement and control over the AI's entire workflow while away from the computer, rather than acting as a mere status checker.

**Scenario A — Remote Monitoring and Review**: after kicking off a long-running refactor task on the computer, the user leaves their desk. When they pick up the phone, they can not only check how many files the AI has processed, but directly read the latest Markdown analysis report the AI produced — the report explains the reason behind each change and includes architecture diagram screenshots. The user's core actions are: read the report in depth, tap file cards to verify specific changes, and confirm the overall direction is correct.

**Scenario B — Fast Correction (Voice-Driven)**: on the phone, the user discovers the AI's implementation approach has deviated from expectations and it is building the feature with the wrong approach. They can then quickly issue an instruction via voice: "Stop, don't use inheritance — use composition instead", and put the phone away. The key value of voice input in this scenario is avoiding the inconvenience of typing on a phone and reducing the interaction friction of steering to a minimum.

**Scenario C — Model A/B Testing**: the user needs to compare how different models (such as GPT-5.3 Codex / DeepSeek / Opus / GLM) perform on the same task. On the phone they can switch to another model with one tap and send the same instruction to observe the differences. This scenario is usually paired with Fork Session — branching attempt branches of different models from the same conversation node.

**Scenario D — Document Review**: after the AI finishes a round of modifications, the user browses the diff of the Markdown document on the phone, primarily using Preview mode to review the changes, and only lets the AI proceed to the next step once the document edits look reasonable. Code review is secondary — the AI already writes high-quality code, so the human's review center of gravity lies in document-level logic and architectural decisions. Output is not limited to programming either; it may cover research reports, system design documents, deployment-result showcases, and other content that naturally takes the form of Markdown.

### 2.0 Time Distribution of Heavy Users

Understanding how heavy users allocate their time is essential for steering the product's evolution:

- **Roughly 60% of the time is spent reading Markdown** — including the AI's analysis reports, research articles, design documents, and deployment results with embedded screenshots; this corresponds to the "review" step.
- **Roughly 25% of the time is spent talking to the AI** — issuing new instructions by voice, correcting the execution direction, or asking follow-up questions; this corresponds to the "command" step.
- **Roughly 10% of the time is spent switching between Sessions** — tracking progress across different projects and directions and deciding which tasks need intervention; this corresponds to "commanding multiple lines at once".
- **Roughly 5% of the time is spent in the Files Tab** — this entry is essentially a fallback channel; the vast majority of file access happens by jumping straight from tool/patch cards in the Chat window.

Based on the time distribution above, the priority order for product-experience optimization is defined as: Markdown rendering quality > voice input fluency > Session distinguishability > file tree features.

### 2.1 Distribution

To lower the barrier to trying the product, two distribution paths are offered at the same time:

- **TestFlight**: for the vast majority of users; install and use, no Apple Developer account required
- **Source build**: for developers who need to modify the code locally, debug it, or use custom signing

The README provides the latest installation entry points; this PRD only keeps the product-level distribution strategy.

## 3. Technical Architecture

### 3.1 Overall Architecture

```
┌──────────────┐                                 ┌──────────────────┐
│              │ ◄─────────────────────────────► │                  │
│  iOS Client  │    LAN / Tailscale / etc.       │  OpenCode Server │
│  (SwiftUI)   │                                 │  (Mac/Linux)     │
│              │                                 │                  │
└──────────────┘                                 └──────────────────┘
     Presentation only + command sending              File system + AI compute
```

The iOS side is designed as a pure API consumer: it carries no local AI inference, file system access, or shell execution logic. All data is fetched through OpenCode's HTTP API, and real-time state is delivered via SSE (Server-Sent Events).

### 3.2 Technology Choices

| Layer | Choice | Rationale |
|------|------|------|
| UI framework | SwiftUI | Native experience, smooth animations, full use of iOS system capabilities |
| Networking | URLSession + native SSE | No third-party HTTP library needed; the SSE protocol implementation is lightweight and direct |
| State management | Swift Observation (@Observable) | Native iOS 17+ solution; the most concise fit with SwiftUI |
| Code highlighting | Not implemented for now | For now only a monospaced font and line numbers are kept |
| Markdown rendering | MarkdownUI + custom image resolution | Meets document preview and code block display needs, and supports resolving relative-path images inside the repo |
| Diff rendering | Custom-built component (based on the server-returned before/after) | The server already computes the diff, so the client only renders it; document diffs need changes highlighted |
| Minimum version | iOS 17.0 | Fully adopts the Observation framework; iOS 16 is no longer supported |
| Persistence | UserDefaults + Keychain | Only connection configuration and model presets need to be stored; no local database required |

### 3.3 Communication with the OpenCode Server

Communication between the client and the server runs over two channels:

**REST API** — Carries all active operations (such as sending messages, fetching file lists, modifying configuration, etc.). The base path for requests is determined by the `http://<ip>:<port>` the user configures in Settings.

**SSE (Server-Sent Events)** — Carries real-time event pushes. The client connects to the `GET /global/event` endpoint to receive the full event stream, with the data format `{ directory, payload: { type, properties } }`.

Lifecycle management of the SSE connection is one of the client's core technical points:
- Establish or restore the SSE connection when the App enters the foreground
- Disconnect the SSE connection when the App enters the background (to avoid keeping a long connection alive in the iOS background)
- When returning from background to foreground, first pull the latest state via the REST API to complete a full sync, then re-establish the SSE connection

### 3.4 Authentication

The OpenCode Server supports optional Basic Auth (controlled by the server-side environment variable `OPENCODE_SERVER_PASSWORD`). The iOS side exposes username and password fields in Settings and stores them securely in the Keychain. The client attaches a Basic Auth header to every REST request it issues and to the SSE connection.

## 4. Feature Specifications

### 4.1 Layout Structure

#### 4.1.1 iPhone: Tab Bar

The iPhone uses a bottom Tab Bar with three tabs:

```
┌─────────────────────────────────────┐
│                                     │
│          (Tab Content Area)         │
│                                     │
├───────────┬───────────┬─────────────┤
│   💬 Chat  │  📁 Files  │  ⚙ Settings │
└───────────┴───────────┴─────────────┘
```

#### 4.1.2 iPad / Vision Pro: Split View (No Tabs)

On iPad and Apple Vision Pro, the **Tab Bar is not shown**; a three-column layout is used (Workspace / Preview / Chat):

```
┌──────────────────────────────┬───────────────────────────────┬───────────────────────────────┐
│ [New] [Rename] [Session List]        [GPT] [Spark] [Opus] [GLM] [◔] [⚙]                      │  ← Row 1: Session actions + models + Context usage + Settings
├──────────────────────────────┼───────────────────────────────┼───────────────────────────────┤
│                              │                               │                               │
│     🧭 Workspace             │         📄 Preview            │           💬 Chat             │
│     (Files + Sessions)       │         (File preview)        │      (Message feed + input)   │
│                              │                               │                               │
│  File tree (top)             │File content / Markdown preview│  Message feed + input box     │
│  Sessions (bottom)           │  Refresh button (top right)   │                               │
│                              │                               │                               │
└──────────────────────────────┴───────────────────────────────┴───────────────────────────────┘
```

**Design points**:
- **Left column**: Workspace (contains the file tree and the Sessions list)
- **Middle column**: Preview (shows file content and Markdown preview, supports manual refresh)
- **Right column**: Chat (contains the message stream and the input field; the interaction logic stays identical to iPhone)
- **Width ratio**: Workspace ≈ 1/6; Preview ≈ 5/12; Chat ≈ 5/12 (Preview and Chat keep the same width)
- **Draggable**: users can drag the dividers to adjust the three column widths, with the initial ratios above used by default
- **Settings**: an independent button in the first toolbar row (alongside the Session actions and the model switch), presented as a sheet or a navigation push when tapped
- **Advantage**: on large-screen devices Chat and Preview sit side by side, so viewing a file preview requires no overlay; meanwhile Workspace and Sessions stay docked on the left without disturbing the main reading flow

### 4.2 Chat Tab (Main Interaction Screen)

As the App's core interaction screen, the Chat Tab has the model and Agent selectors at the top, the message stream in the middle, and the input controls (Composer) at the bottom.

#### 4.2.1 Model and Agent Selectors

Located in the right-hand toolbar area at the top of the Chat screen. It uses a **dropdown list** (Menu + Picker), replacing the original horizontally scrolling chip bar.

**Model selector**: a dropdown list containing the following fixed options:

| Display Name | providerID | modelID |
|----------|------------|---------|
| GLM-5.1 | `zai-coding-plan` | `glm-5.1` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |
| DeepSeek | `deepseek` | `deepseek-v4-pro` |

**Agent selector**: a dropdown list whose options are fetched dynamically from the `GET /agent` API; the client filters out agents with `hidden != true` before displaying them. Each option shows the agent name (such as `Sisyphus`), and the description can be shown as a tooltip or subtitle for extra context.

**iPhone display strategy**: on narrow-screen iPhones short names (`DeepSeek` / `GPT` / `GLM`) are used to keep the layout compact; on larger devices such as iPad the full names are shown.

**Technical implementation**:
- Switching the model or Agent only changes local state; no API call to the server is needed
- When sending a message, the request body of `POST /session/:id/prompt_async` includes:
  - the `model: { providerID, modelID }` field
  - the `agent: string` field (the agent name)
- The selected model and Agent are remembered per Session; switching Sessions automatically restores the corresponding configuration

#### 4.2.1.1 Context Usage Indicator

A **ring-shaped progress indicator** is shown at the top right of Chat (between the Agent selector and the Settings gear icon), representing how much of the context window was used during the most recent generation of the current session.

- **Data source**: computed from `info.tokens.total` in the assistant message returned by `GET /session/:id/message` (together with the input/output/reasoning/cache breakdowns), combined with `limit.context` for the matching `providerID/modelID` from `GET /config/providers`.
- **Provider Config loading**: the result of `GET /config/providers` is cached locally; if it has not been loaded yet or the data is empty, tapping the ring triggers the load automatically and shows a loading state; on failure the sheet presents the specific error message instead of merely stating "Provider config not loaded".
- **When there is no data**: a grey empty ring is shown (with no numeric value); tapping it still opens the detail sheet, whose content reads "No usage data".
- **Color strategy**: usage below 70% shows the normal color; 70-90% shows the warning color; above 90% shows the danger color (to prevent users from blindly sending on iOS and blowing past the token limit, which truncates the output).
- **Tap interaction**: tapping the ring opens a detail sheet (supported on both iPhone and iPad) showing the following details:
  - Session (title/id, copyable)
  - provider/model
  - context limit
  - total tokens + usage %
  - input/output/reasoning/cache read/cache write
  - total cost (shown if the server returned a message cost; hidden if missing)

Note: raw messages are not shown in the first version; as for the context breakdown (that is, the respective share of system/user/assistant/tool), support will be added once the server explicitly exposes the corresponding fields or a stable derivation method exists.

- **Visibility during AI responses**: whatever the current state (idle / busy / streaming), the context ring stays permanently visible and is never replaced by a spinner or another transient control. The busy state is uniformly expressed by the red stop button on the right of the input bar; the toolbar no longer injects an extra `ProgressView`.

#### 4.2.2 Message Stream

A vertically scrolling message list whose styling references the OpenCode Web client: **no left/right chat bubbles**; all messages are laid out uniformly as a stream, with human messages distinguished from AI messages by a grey background, keeping a compact overall reading rhythm.

Each message contains:

**User message**: a grey-background card that shows the text content, with the selected model noted in small text at the bottom.

**AI message**: a white or transparent background, supporting rendering per Part type:
- `text` — full Markdown rendering (supports code blocks, links, lists, and other formats)
- `reasoning` — a collapsible panel titled "Thinking...", which expands on tap to reveal the detailed thinking and reasoning process
- `tool` — a tool call card showing the tool name and its current execution state (pending → running → completed/error). In the **running state it is expanded by default** and shows a loading indicator (spinner); in the **completed state it is collapsed by default**, and the user can tap to expand and see the metadata details (such as file paths and command output)
- `tool` (todowrite) — rendered as a Task List (todo) card: it shows the item list and the completion progress (completed/total); the full todo data can be obtained from the tool input/metadata and is updated in real time by the SSE `todo.updated` event. **It is displayed inline only inside each tool card, and is not permanently shown at the top of Chat (option B)**
- `step-start` / `step-finish` — rendered as step dividers showing the token usage and the invocation cost
- `patch` — a file change summary card listing the modified files; tapping it jumps directly to the file tree of the Files Tab and opens the corresponding file preview
- `tool` (write/edit/apply_patch/read_file, etc.) — if the current part contains a file path (such as metadata.path, state.input.path, a files array, or a path parsed out of patchText), tapping the card offers an "Open in File Tree" action that brings up the file preview directly; if the target is an image file and the tool output supports decoding, a thumbnail is shown inline and can be tapped to zoom

**Large-screen layout supplement (iPad / Vision Pro)**: to make full use of the horizontal screen space, `tool` / `patch` / permission cards support a **three-column grid** laid out horizontally (wrapping automatically when space runs out); `text` (the final reply), however, still spans the full row width, to preserve reading continuity for long text.

**Streaming updates (Think Streaming)**: the behavior is kept consistent with the official Web client. When SSE pushes `message.part.updated` containing a `delta` field, the client incrementally appends to the corresponding text or reasoning Part, producing a typewriter effect; if the event contains no delta, a full reload is performed. A specific Part is located with the composite identifier `messageID` + `partID`. **Note**: the server API does not yet support real-time line-level streaming of Tool output (such as printing terminal content line by line); the output data is only returned in one shot when the state becomes completed.

**Auto-scroll rules**: only when the user's current view is near the bottom of the message stream do newly arriving streaming text, tool cards, permission cards, question cards, or activity rows drive the view to keep scrolling down; if the user has already scrolled up to browse history, scroll-following pauses automatically so that reading is not interrupted.

**Paginated loading of history**: to shorten the first-screen load time on weak networks (such as an SSH tunnel or a WAN connection), only the most recent **3 conversation turns** are fetched by default (6 messages in total: 3 user and 3 assistant). The top of the chat view offers a "pull down to load more history" interaction, and each pull appends 3 more turns of history.

**Activity Row consistency rule**: the actual runtime state takes priority over the transient flicker that `session.status=idle` may produce. As long as the client still holds a tool in the running or pending state, or is receiving streaming deltas, the Activity Row must stay in the running state; only after it is confirmed that the whole assistant turn has completed does it switch to completed.

**Session status indicator**: the top of the message stream shows the runtime state of the current session (idle / busy / error) in real time, with the data coming from the `session.status` SSE event. A progress animation is shown while busy.

#### 4.2.3 Permission Notifications

In OpenCode's normal execution flow, permission requests are rarely raised proactively; once a `permission.asked` event fires, it usually indicates something abnormal. The client therefore adopts a **manual approval** mode:

- Listen for the SSE `permission.asked` event in real time
- Insert a permission request card inline in the message stream, clearly showing the operation awaiting approval (such as "execute `rm -rf node_modules`")
- The user must manually tap "Approve" or "Deny"; the client submits the decision by calling `POST /session/:id/permissions/:permissionID`
- The client offers no form of auto-approval

#### 4.2.3.1 Question Card

When the server proactively asks the user a question through the `question` tool, a question card is inserted directly into the Chat message stream, so the session does not fall into an unresponsive wait.

- Listen for the SSE events: `question.asked`, `question.replied`, `question.rejected`
- On initialization and on reconnect, pull the pending questions of the current session through `GET /question`
- Support selecting single-choice or multi-choice preset options, or typing custom text in the input field
- Submitting an answer calls `POST /question/{requestID}/reply`
- Rejecting a question calls `POST /question/{requestID}/reject`

#### 4.2.4 Composer: voice rail + text review field

The fixed composer at the bottom uses a two-row structure: the voice rail on top and the text review field below. Session-related actions (new, rename, list, Compact) are all placed in the top Chat toolbar and never intrude into the composer area.

This structure directly serves the Steer positioning: the user's core habit on mobile is not lengthy keyboard typing, but adding a quick directional instruction by voice after reading the AI's output. Voice is the primary input modality, while the text field carries the review of the transcription result, light touch-ups, and typing as a fallback. The composer therefore does not treat the microphone as a secondary button inside the text field; it promotes the voice rail to the first row as the primary interaction panel.

**Draft persistence**: unsent input is persisted locally per sessionID; after switching to another session and returning, the draft is fully restored; once the message is sent successfully the local draft is cleared.

**Voice rail (speech recognition)**: the voice rail sits above the text field and is made up of the transport control button on the left, the central waveform/status display area, and a lightweight recovery action area on the right. Tapping the transport control to start recording makes the system create a VoiceFlowKit realtime session and collect a PCM16 mono 24kHz audio stream through `AVAudioEngine`. While recording, the central waveform directly consumes the smoothed microphone level in the 0..1 range provided by `VoiceFlowMicrophone.audioLevel`, giving the user intuitive feedback on sound capture. Tapping the transport control again is a normal end of audio capture that enters the transcription phase, and is conceptually independent from aborting an agent run (agent abort).

While VoiceFlowKit sends live PCM data to the remote end, it also appends the same PCM audio stream synchronously to a local temporary `.pcm` file; if the heartbeat check or the live send detects a broken WebSocket connection, the Kit does not terminate the current recording but automatically rebuilds the session and replays the complete PCM data from the local cache, catching up with the current recording progress before resuming the real-time transmission. When the user stops recording, the system waits for the retransmission recovery to complete and then sends the `commit` / `stop` commands, after which the finally recognized transcript is appended to the text review field below.

If the transcription process hits a wait timeout or stalls, the voice rail shows a processing waveform and offers an explicit recovery entry point (such as `Stop transcription wait`). This action calls `abortPreservingAudio()` to terminate the current WebSocket and the finalize wait flow, while fully preserving the recorded PCM audio; the rail then enters the preserved-audio state, the transport button on the left turns into a `Retry this segment` icon that calls `transcribe(preservedAudio:)` to run recognition over that audio segment again, and the action on the right becomes `Discard audio`, used to drop the currently preserved audio and reset to the normal input state. Here retry means re-transcribing an already saved audio file — it is not an additional recording, and the user does not need to speak again. If the retry still fails, the system keeps that audio segment, and the user can either keep retrying or tap discard to leave the recovery flow.

**Text review field**: the lower text field supports multi-line editing and receives the speech transcription result, manual modifications and light touch-ups, and pure keyboard input. While recording, the placeholder reads "Transcription will appear here", to avoid visual duplication with the Listening state already shown in the voice rail and status row above. When the speech transcription or the preserved-audio retry streams back a partial transcript, the text field scrolls to the end automatically, so that the user can watch the transcript being generated in real time; ordinary manual typing and draft restoration, on the other hand, do not trigger forced scrolling. The send button is fixed to the right of the text field; it stays usable even when the current session is busy, because the server-side `prompt_async` endpoint has a built-in queueing mechanism.

**Agent interrupt**: the running state of the agent is hinted at by a low-weight status line near the composer (such as `Agent running`). `Interrupt agent`, a low-frequency interruption action, is tucked into the `⋯` overflow menu and calls `POST /session/:id/abort` when triggered; by design there is no eye-catching red banner at the top, and it shares no stop icon with the speech transcription recovery actions, so that the user can clearly distinguish three different dimensions of state: speech capture, transcription waiting, and agent running. The related Token and Base URL are configured under Settings → Speech Recognition, are stored in the Keychain, and are not committed to git.

**Message queue**: when a session is busy, a newly sent message goes straight into the queue. The OpenCode Server's `POST /session/:id/prompt_async` already has a queueing mechanism built in on the server side — messages received while busy are queued automatically and processed one after another once the current task completes. The iOS side simply calls `prompt_async` and needs no local queue logic of its own. If the server API changes in the future, it can degrade into local queue management.

**Enter behavior research conclusion**: research shows that the OpenCode Web client calls abort when Enter is pressed with an empty input field, terminating the current run; when the input field has content, Enter sends the message through prompt (with the server queue handling the queueing). The system itself has no so-called "smart steer" mechanism, only simple termination or queueing. The iOS side can therefore offer an explicit manual abort button, without needing to design any complex steer detection.

Additional actions (invoked through the buttons in the top Chat toolbar, from left to right):
- Session list, rename, Compact, new Session (strictly in this order)
- Compact Session (calls `POST /session/:id/summarize`, used to compress the historical context and reduce the risk of exceeding the token limit) (🔲 not implemented yet)

#### 4.2.5 Session Management

The user can enter the Session list from the button at the top left of the Chat Tab (presented either as a slide-over or a navigation push). This page **lists every Session under the current workspace**, and is also the core functional verification channel: it can be used to verify the network connection, the API data parsing, and the correctness of the message and status rendering.

On iPhone, besides tapping the top `Session List` button, a right-swipe gesture from the left edge of the screen brings up the Session List directly. The gesture does not create a new navigation branch but reuses the existing list entry point, to lower the cost of tapping the top-left button when the phone is held one-handed.

The Session List is positioned as the management console for the current working set, rather than a mere historical archive list. Active sessions are shown by default, sorted by update time in descending order; Archived sessions exist as a separate collapsible section inside the list, so the user can retrieve them at any time without entering Settings. Both the Session sheet on iPhone and the left sidebar on iPad / Vision Pro uniformly use the dual Active and Archived section structure, and both sections support independent expansion and collapse. The current version does not offer session search, to avoid a local title-based filter being mistaken for a full history search.

Each entry in the list contains: the Session title, the update time, `summary.files` (the number of files touched by that session's changes), and the current state (idle/busy/retry). For Active sessions, create, switch, archive, and delete are supported; for Archived sessions, switch to view, restore, and delete are supported. The Archive / Restore / Delete actions are all triggered through swipe actions, following the existing button style: the SF Symbol icon on top and the text below. Delete is fixed to the trailing swipe and uses the red destructive style; Archive / Restore are fixed to the leading swipe and use a restrained electric blue or neutral color. All swipe actions disable full swipe (triggering directly on a full swipe), to prevent accidental activation in daily use. The Delete action no longer pops a secondary confirmation dialog — completing the "swipe + tap the button" action chain already conveys sufficient and explicit user intent.

Archive behavior: after tapping Archive, the session immediately moves from the Active section to the Archived section and no longer takes up visual space in the main list. If the archived session has child sessions, the client must recursively archive the entire subtree, and the archiving order is "children first, parents last", so that a child session does not briefly surface as an Active root node after its parent is hidden. Restore behavior: after tapping Restore, the session moves back into the Active section; when restoring a subtree the order is reversed, "parents first, children last", so that a child session does not end up orphaned while its parent is still archived. If the user keeps sending messages directly in an archived session, the client should first auto-restore that session and then perform the send, ensuring that a reactivated task returns to the current working set. The Pin feature is not implemented at this stage.

Visual and interaction specification: list text uses a neutral grey by default, to avoid triggering the iOS default link blue. The currently active Session is highlighted with a light background, and embeds a 3pt-wide electric blue accent bar on its left edge (the same "left color bar" visual language used by user messages and action cards; the bar merges into the rounded selection background, is fully clipped inside the rounded region, does not overflow, and does not conflict with the expand chevron or the indentation levels). The selected state no longer shows an extra checkmark, so that users do not mistake it for a task-completed state or a multi-select mode. Archived rows remain tappable to view their history, but rank visually below Active rows: their title and time use lower-contrast neutral colors and they render no selection accent bar, so that no expectation of currently active processing is created.

#### 4.2.6 Fork Session (Session Branching)

The user can fork the current conversation from any historical message node, producing a brand-new session that contains all the history preceding that node. Typical use cases include: being unsatisfied with the AI's current reply and wanting to start over from a specific node; or wanting to explore different prompt directions from the same precondition.

**Interaction**: a "..." more button is provided next to the model label at the bottom of every user message (such as `anthropic/claude-opus-4-6`). Tapping it opens a menu, and choosing the "Fork from here" option calls `POST /session/{id}/fork`. The server creates the new session and copies all the history preceding the selected message, and the client then switches automatically to the newly created session view.

**API**: calls `POST /session/{sessionID}/fork`, with the request body `{ "messageID": "..." }` (optional). The endpoint returns a brand-new `Session` object.

**Implementation note**: uses the SwiftUI `Menu` component (tap-triggered) rather than `.contextMenu` (long-press dependent), to improve the discoverability of the feature. The title of the forked session is automatically named "{original title} (fork #N)".

#### 4.2.7 Session Deep Link (Locating a Session Across Entry Points)

The client provides a standard, unified read-only navigation link protocol:

```text
opencode://session/<session_id>
```

The link can be generated by an Agent's Markdown output in Chat, or come from Apple Notes, email, a web page, or another external app. After the user taps the link, the client verifies on the currently connected Host whether the target session exists; if the verification passes, it switches project and session in turn and enters the Chat page; if it fails, the current session is kept unchanged and a global error message is shown in the UI. If the App has not been launched yet or is in the middle of a network reconnection, the system parks the navigation request first and resolves it once the current Host becomes reachable again.

Global retrieval of Sessions remains handled by the semantic-search capability of the Agent and the workspace; the client adds no dedicated search page, embedding index, or archive-reading feature locally. After the Agent presents 3-5 candidate results backed by source text, it renders the explicit action as `[Open in OpenCode](opencode://session/<session_id>)`; the corresponding action link may only be generated when the metadata is explicitly marked as OpenCode and contains a valid session ID.

The scope of the V1 version is strictly limited to the currently configured Host. The link itself carries no device-local Host Profile UUID, server URL, credentials, query parameters, or absolute file paths, and the client never polls automatically or switches across Hosts. For a session in OpenCode's soft-archived state, it opens normally as long as the current server can still read it; but ancient history kept only in an offline SQLite database or a local Markdown archive is out of scope for automatic recovery.

A deep link is a low-privilege, pure navigation action and never acts as a channel for executing instructions. It does not support sending a prompt directly, approving a permission request, invoking a tool, deleting or archiving a session, and it never triggers a jump automatically once the Markdown rendering has finished. The V1 version does not support message-level targeting parameters; until the Chat has stable and reliable precise scrolling and highlight positioning, every link carrying a query, a fragment, or extra path segments is rejected as an illegal link.

### 4.3 Files Tab (File Browsing and Diff)

> In terms of product positioning the Files Tab is a **fallback entry point**, not the main workflow. The vast majority of the user's file-viewing behavior is completed by tapping tool/patch cards directly in the Chat window — when the user sees an `edit_file` or `patch` card in the Chat message stream, tapping the file path opens the preview directly. The value of the Files Tab lies in serving the global inspection need: when the user wants to browse all modified files at a high level, or to search for files that were not mentioned in the Chat cards, it provides a reliable access channel. It therefore does not need to chase overly elaborate interface detail, but it must guarantee the absolute stability of its basic capabilities.

#### 4.3.1 File Tree

Shown full screen on iPhone and as the left sidebar on iPad. The data comes from `GET /file?path=<path>`.

The file tree supports expanding and collapsing directory levels in a recursive tree structure. Each tree node shows the file/directory name and a corresponding type icon. Files with git changes carry an explicit color marker (green for added, yellow for modified, red for deleted), with the data coming from `GET /file/status`.

A search box is provided at the top, supporting fuzzy search by file name (calling `GET /find/file?query=...`).

#### 4.3.2 File Content Viewing

Tapping a node in the file tree opens the file content detail page. The data comes from `GET /file/content?path=...`.

- **iPhone**: push to the content detail page within the Files Tab navigation stack
- **iPad three columns**: after tapping a file it is rendered inline in the Preview column in the middle; tapping a file path in a tool/patch card in Chat likewise refreshes the Preview area directly (no separate sheet)

For plain-text files: a monospaced code viewer is provided, showing line numbers and supporting horizontal scrolling. The current version does not do syntax highlighting, prioritizing rendering stability and text readability.

For Markdown files: seamless switching between Preview (rich-text preview) and Markdown source (raw source) is supported. Preview mode is rendered with MarkdownUI, and for extremely long text lines and very large files it automatically falls back to the raw text mode to prevent the interface from stuttering.

For image references contained inside Markdown, the client must fully support **relative-path resolution inside the repo**, especially the common report-reference form such as `![x](../assets/foo.png)`. Image loading cannot rely solely on MarkdownUI's default network image loader; instead, the client must combine the path of the current markdown file with the workspace root directory, resolve it into a valid local file request, and render it on screen. This capability behaves consistently both for `.md` files opened directly in Files and for AI reports shown in Chat.

For image files: base64 decoding and inline preview are supported, with the default initial scale being fit-to-screen; pinch-to-zoom, drag-to-pan, and double-tap-to-magnify gestures are supported, and the system share sheet is integrated. When system photo library permission is granted, the share sheet should support the `Save to Photos` action.

#### 4.3.3 Diff Viewing and Document Preview

**Core positioning**: **document review** is the first priority. Markdown rendering, document diff, and Preview preview are core, mandatory capabilities.

**Markdown presentation specification**:
- Prefer **Preview mode**: the user reads documents mainly as a rich-text Preview; if the implementation complexity proves too high, a Preview / Markdown toggle may be provided
- **Changes highlighting**: the specific changes must be clearly highlighted in the diff. If inline rich-text highlighting is difficult in Preview mode, the changes can be marked in the Markdown source view, and the user can compare them in Preview mode
- The minimum supported version is iOS 17, with no legacy system compatibility burden

**Two entry forms**:

**Session Diff**: currently not displayed directly in the iOS client (because the server diff API may return an empty array in certain boundary scenarios).

**Single-file Diff**: when tapping a file with a change marker in the file tree, if that file has uncommitted changes, the content detail page automatically switches to diff mode for display.

Diff rendering follows a unified diff format (GitHub-like): a green background marks added lines and a red background marks deleted lines. The server returns the complete `before` and `after` file contents to the client, which performs the diff comparison and the highlighted rendering locally. Given the limited width of phone screens, only the unified mode is provided by default, with no side-by-side two-column comparison.

#### 4.3.5 Markdown Web Preview (HTML Cards / Enhanced SVG Reading)

When a `.md` document is opened, the default is a layout with a rich visual structure: various HTML status cards, inline SVG charts, and dark-mode reading all render correctly, and the toolbar can switch back to the plain-text Native view or the Markdown source with one tap. See RFC §7.5 for the underlying technical details.

<style>
.wp-stat{display:inline-block;border-radius:999px;padding:1px 8px;font-size:.78rem;font-weight:650}
.wp-stat.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.wp-stat.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

| What the user experiences | Status |
|---|---|
| One-tap switch between Web / Native / source in the toolbar, with Web as the default | <span class="wp-stat ok">Shipped</span> |
| HTML status cards / inline SVG display correctly | <span class="wp-stat ok">Shipped</span> |
| Relative images inside the document can be loaded | <span class="wp-stat ok">Shipped</span> |
| The same document reads well in light / dark mode | <span class="wp-stat ok">Shipped</span> |
| Switching files refreshes the content immediately; large files ask for confirmation first | <span class="wp-stat ok">Shipped</span> |
| `.html` browsing / Mermaid / code highlighting / tap-to-zoom images | <span class="wp-stat block">Next round</span> |

Details and sources — the decision process is documented in [`WORKING.md`](WORKING.md); the complete sub-project PRD / RFC are kept on disk at `docs/archive/2026-06_markdown_web_preview_prd.md` / `2026-06_markdown_web_preview_rfc.md`, and have been removed from git tracking.

### 4.4 Settings Tab

#### 4.4.1 Host Profiles (Multiple OpenCode Environments)

The top of Settings no longer presents Server Address and SSH Tunnel as flat global configuration items; instead they are presented uniformly under the currently active `Host`. A Host here represents an independent OpenCode runtime environment, which can be a directly connected LAN / Tailscale / HTTPS server, or an isolated OpenCode container reached through an SSH gateway proxy. Tailscale, VPN, and the LAN are all transparent networks for the App and are grouped together as Direct transport.

**Design goal**: ensure that within 5 seconds the user can tell which OpenCode environment they are connected to and which underlying transport channel it uses (Direct or SSH Tunnel), and can conveniently switch to another host, avoiding accidental modification of the underlying network configuration.

**Host list management**:

- The top of Settings shows a Current Host summary card: profile name, transport type, address summary, real-time connection status, and a Test button.
- The Current Host card embeds lightweight connection diagnostics. While the connection is being established it shows the current stage; on failure it presents troubleshooting copy with clear action guidance, instead of throwing an unhandled native Swift error.
- Tapping the card enters the Hosts management page, which fully lists all the configured profiles; the currently active profile is highlighted on the left with an accent bar and a checkmark.
- Each row of the list shows the profile name, a transport summary, and the most recent connection status (such as `example.com:8006 -> :19001`, `Direct HTTPS + Basic Auth`, `Last used yesterday`). If that host has no successful connection record yet, it is clearly labeled `Never connected`; formatting an epoch timestamp into a meaningless long relative time is forbidden.
- Tapping any row of the list enters the Host Detail page. Switching hosts is an explicit `Use This Host` primary action inside the detail page, so that the user does not switch by mistake merely while looking at the configuration.
- Add Host, Host Detail, Edit, Duplicate, and Delete actions are provided. Before deleting the currently active host, the user must be forced to switch to another host first, or to confirm in a second dialog.
- The Device Public Key, a device-level general credential, is placed at the bottom of the Hosts page; this public key is used only by SSH Tunnel hosts, while Direct hosts do not need it.

**Host Detail (detail page)**:

- Shows the profile name, the transport type, a summary of the connection address, real-time connection diagnostics, and the time of the most recent connection attempt.
- A Direct profile shows the OpenCode URL and whether a Basic Auth username has been configured.
- An SSH Tunnel profile shows the Gateway Host, SSH Port, SSH Username, Assigned Remote Port, the locally mapped OpenCode URL `127.0.0.1:4096`, and the trusted host fingerprint (if any).
- If the host being viewed is not the active one, the page offers the `Use This Host` primary action; the detail page also provides the `Test Connection`, `Edit`, and `Copy Host Config JSON` shortcuts.
- The detail page of an SSH Tunnel profile provides a `Copy This Device Public Key` entry point. The private key is kept strictly in the local Keychain and does not support any form of export.

**Add Host flow**:

1. The preferred entry point is `Import Host Config`. The user can paste the standard setup JSON config distributed by the administrator, preventing mistakes in the host, port, username, or remotePort during manual entry.
2. When creating manually, the `Direct` or `SSH Tunnel` transport type must be chosen explicitly first.
3. The Direct form only requires Name, OpenCode URL, and optional Basic Auth credentials.
4. The SSH Tunnel form requires Name, SSH Gateway Host, SSH Port, SSH Username, and Assigned Remote Port. The OpenCode URL field is locked and not editable for the user; after saving, the App always connects through the local `127.0.0.1:4096` proxy tunnel.
5. The SSH Tunnel form must explicitly provide a `Copy This Device Public Key` button, together with clear security guidance: "Give the public key to the server administrator; never share the private key with anyone".
6. Test Connection performs a chain validation according to the currently configured transport: in Direct mode it issues a `/global/health` liveness request straight to the remote end; in SSH mode it first establishes the SSH tunnel and then runs the health check against the local OpenCode proxy port.
7. Tapping `Save` only means the local profile was saved successfully; only passing `Test Connection` means the network connection has been validated. The UI design must clearly separate "saving the configuration" from "the connection being ready".

**Switching behavior**:

- When switching hosts, the system proactively tears down the established SSH tunnel and the SSE long connection, and then loads and applies the target profile.
- After the switch, the selection state of the current session is reset; session and project state data logically belongs to a specific host, and later versions can extend this to remember the last selected project/session per host.
- If the target host has SSH Tunnel enabled, the App may attempt to establish the tunnel automatically; if the connection fails, only the current connection status is updated, with no interrupting blocking alert dialog.
- Basic Auth credentials are stored in the Keychain isolated per profile; the SSH private key is by default shared globally at the device level as a single key pair.

#### 4.4.2 Direct Transport

Direct mode applies to the network scenarios where the App can communicate directly with an OpenCode instance: a local LAN, a Tailscale / VPN virtual private network, or a public HTTPS server.

**Configuration item list**:

| Field | Description | Default |
|------|------|---------|
| Name | Profile name | Inferred from the host, or filled in by the user |
| OpenCode URL | `ip:port` or `http(s)://host:port` | - |
| Username | Basic Auth username, optional | - |
| Password | Basic Auth password, optional, stored in the Keychain | - |

**Protocol security notice**: when Direct mode is configured with the HTTP protocol and the target address is not localhost, a LAN private range, or Tailscale MagicDNS (`*.ts.net`), the UI shows a non-blocking warning suggesting that the user upgrade to HTTPS. This notice applies to Direct mode only; under SSH Tunnel mode the local loopback address `http://127.0.0.1:4096` is expected by design and no HTTPS protocol warning is shown.

#### 4.4.3 SSH Tunnel Transport (Remote Access)

This applies to reaching a hosted OpenCode Server deployed inside an intranet or an isolated container through an SSH gateway. The network communication topology is as follows:

```
iOS App → SSH Gateway (:8006) → Assigned Remote Port (:19001) → OpenCode (127.0.0.1:4096)
```

Prerequisite conditions:
- The administrator has completed the deployment of an independent OpenCode instance on the server side and assigned the corresponding remote port
- The user has provided the iOS device's public key to the administrator for configuration; the private key is kept strictly in the local Keychain

**Configuration item list**:

| Field | Description | Default |
|------|------|---------|
| Enable SSH Tunnel | Toggle | Off |
| Gateway Host | SSH gateway address | - |
| SSH Port | SSH port | 8006 |
| Username | SSH username | opencode |
| Assigned Remote Port | The remote port assigned by the administrator | 19001 |

**Key management specification**:

- The App automatically generates an Ed25519 key pair on first use
- The private key is stored securely in the iOS Keychain (with the access control attribute set to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- The key pair is a long-term device identity: it is generated only on first use (when the Keychain entry is genuinely missing) or when the user explicitly rotates it; when the Keychain is temporarily unreadable (for example while the device is locked), an error asks the user to unlock the device and retry, rather than silently regenerating
- The public key is shown in the Settings interface, with one-tap copy to the clipboard
- A key rotation entry point is provided (supporting the regeneration of a brand-new key pair)

**First-time setup flow**:

1. Go to Settings → SSH Tunnel
2. The App automatically generates the local key pair
3. Copy the generated public key and send it to the OpenCode host administrator
4. After the administrator completes the authorization on the server side, they return the gateway host, SSH port, username, and assigned remote port parameters
5. Enter the above parameters one by one in the App, and turn on the SSH Tunnel feature switch
6. Set Server Address to `127.0.0.1:4096` (forwarded through the local tunnel), and tap the `Test Connection` button above to verify the connectivity

**Connection status display**:

- Four states are displayed in real time: Connected / Connecting / Disconnected / Error.
- The connection diagnostics of the SSH Tunnel need chain-decomposition capability, clearly distinguishing at least four stages: SSH gateway connectivity, SSH auth authentication, the local tunnel proxy channel, and the OpenCode health check.
- When something goes wrong, a clear failure cause and troubleshooting advice are given, for example telling the user to copy the current device public key and send it to the administrator when the public key is not authorized, or to check the username and password configuration when the Basic Auth validation fails.

**Security requirements**:

- Only key-based SSH authentication is supported; password authentication is not enabled
- The first connection uses a TOFU (Trust On First Use) strategy to automatically trust and store the server's host fingerprint, and subsequent connections perform a strict fingerprint check; the UI provides fingerprint viewing and a reset trusted host function

#### 4.4.4 Model Presets

**Current implementation**: a built-in fixed list of preset models (GLM-5.1, GPT-5.4, GPT-5.3 Codex, DeepSeek); importing and ordering are not supported yet. When sending a message, the request body carries the `model: { providerID, modelID }` structure.

#### 4.4.5 Project (Workspace)

Used to specify the OpenCode project context that currently needs to be browsed. The OpenCode Server natively supports multi-project management, with each project owning an independent session dataset. The iOS client filters the corresponding sessions by project directory through `GET /session?directory=<worktree>`.

**Selecting an existing project**:
- Call `GET /project` to fetch the list of all projects known to the server
- Render the projects with a Picker component; the option display name defaults to the last-level directory name of the worktree path (such as `knowledge_working`, `agentic_trading`)
- The project selected by the user is persistently stored in UserDefaults

**Custom path support**:
- A "Custom path" option is provided, supporting the user typing in any absolute worktree path manually
- It applies to edge-case directories where the server has session records but they were not automatically collected into the project list
- If the entered path is wrong, the `/session?directory=xxx` endpoint returns 0 sessions, which the user perceives directly

**Default project behavior**: if the user has not explicitly selected a project, no `directory` parameter is passed when calling `GET /session`, and the project currently open on the server is used by default (consistent with the logic of the Web client). Once a specific project is selected, the client calls `GET /session?directory=xxx&limit=100` to fetch the corresponding data.

**Session creation restriction**: creating a new session is allowed only when Server default is selected. Because the server's `POST /session` endpoint does not support passing a directory parameter, a newly created session is always bound to the project currently open on the server. When the user has manually specified a concrete project, the new button is automatically greyed out and carries an info hint icon, telling the user that they need to launch OpenCode from the command line with a different working directory before creating one.

#### 4.4.6 Appearance

- **Theme follows the system** (Light/Dark/Auto): automatically switches the presentation style according to the light/dark theme setting of the iOS system
#### 4.4.7 About

- Shows the current App version number
- Shows the version of the currently connected OpenCode Server (taken from the `version` field in the `GET /global/health` response)

### 4.5 Car Mode (Experimental)

Car Mode is a foreground voice interaction mode designed specifically for the iPhone. In driving scenarios where reading long conversations or typing is inconvenient, a single tap is enough to complete the loop of "dictate the instruction → auto-submit → listen to a condensed conclusion". This feature is a built-in capability of the OpenCode iOS Client: no separate in-car App is maintained, and it is not a standalone CarPlay App either.

#### 4.5.1 Product Scope

- Car Mode is off by default, with an explicit opt-in entry point only in Settings → Experimental Features.
- Once enabled, the tab order at the bottom of the iPhone becomes Chat / Files / Car / Settings; once disabled it returns to Chat / Files / Settings.
- On iPad and Apple Vision Pro, the Car Tab and its configuration switch are not shown (including in iPad compact window mode).
- Tapping the large primary button starts the recording; tapping again ends the audio capture and automatically triggers the send, completely skipping the composer confirmation step of normal Chat mode.
- The AI's reply is strictly constrained to a short, directly readable structured speech format; after the system calls the Apple TTS engine to speak it, it automatically resets to the idle standby state.
- The client actions that are allowed to be triggered include `open_navigation` and the V0 `health_quantification.export_all`. Maps navigation assembles the target URL locally on iOS; Health data export is completed through local permission checks, a restricted App handoff, and coordination with the original session callback. See [`features/client_capabilities/prd.md`](features/client_capabilities/prd.md) for the product interaction contract.

Car Mode does not promise to keep recording in the background, to keep the SSE connection alive, or to continue TTS playback after the system switches to Maps or another App. As soon as the App enters the background, the current foreground interaction logic stops immediately, but the Car session is persistently retained; once the user returns to the App, they can continue interacting in the original context.

#### 4.5.2 Dedicated Session and Visibility

Car Mode does not reuse the conversation context currently selected in normal Chat. Each `(host profile, workspace)` dimension independently maintains its own dedicated, persistent Car session, and locally records the most recently processed assistant message ID, the pending confirmations, and the last active timestamp.

- On the first interaction, a dedicated session titled `Car Mode` is created automatically.
- Before every subsequent send, the client verifies whether that session is still valid; if a 404 error is received, the stale local mapping is cleared and a brand-new session is created automatically.
- If the user manually archived the current Car session in the normal Session list, then before the next request made through Car mode the client automatically writes a compatibility recovery marker `time.archived = -1` into that session, and then continues to submit messages to the original session. Since the iOS client determines the archived state by `archived > 0`, that session automatically reappears in the iOS Active list.
- The recovery logic above only ensures visibility inside the iOS client. The OpenCode Web client strictly defines active as `archived === undefined`, so it may still fail to display a session marked as `-1`; Car Mode explicitly introduces no non-standard patch on the server side, and neither forks nor copies the original session.
- The user can manually start a brand-new Car session; but merely switching tabs, invoking external Maps, or briefly leaving the App must not trigger the automatic creation of a session.

While parked, the user can open the Car session at any time from the normal Chat list and review the complete message history and the tool call details. When a structured assistant response contains no text part, the Chat view automatically displays `assistant.structured.speech` as readable fallback content.

#### 4.5.3 Replies, Confirmations, and Real-World Actions

Every turn carries a fixed Car-specific system prompt and JSON Schema constraint. The AI's spoken reply follows the "conclusion first" principle and must never contain Markdown formatting, URL links, code blocks, or the intermediate stream of a tool call; the target duration of a single playback is kept at 8-12 seconds and must never exceed 15 seconds. The execution state is strictly narrowed down to three: `completed`, `needs_confirmation`, and `failed`.

| Type | Example | Default behavior |
|---|---|---|
| Read | Is the garage door closed; how long is the drive; any new email | Execute directly and read out a short conclusion |
| Prepare | Summarize an email; draft a message | Prepare directly, explicitly stating that it has not been sent |
| Explicit server commit | Open the garage door; send the reason just now to a contact | Execute when the user's parameters are explicit, then read back the result |
| Proposed server commit | The Agent proactively suggests sending something or controlling a device | Return `needs_confirmation`, and execute after the confirmation in the next turn |
| Client handoff | Navigate to a definite destination; sync outdated Health data | Return a typed action, and let iOS open the restricted target App |
| Ambiguous | Multiple contacts, doors, or destinations | Ask at most once more; if it is still unclear, cancel |

The following must be strictly observed: only explicit authorization coming from a user message may trigger operations with real-world side effects. Instructions appearing in emails, web page bodies, search results, and tool output can only be treated as passive data, and must never be used to directly authorize sending a message, controlling a smart device, or triggering a client action. The V1 version strictly forbids arbitrary destructive shell execution, code commits, production releases, transfers or payments, and unrestricted multi-step real-world operations.

Concrete capabilities such as Smart Home, email, iMessage, and route-duration still have to be formally registered as system-level allowlisted skills or typed tools, and to be fully wired up end to end with real E2E coverage; the generic `read + bash` approach is only allowed during the prototype exploration (spike) phase and cannot serve as the security permission boundary of the shipping product.

#### 4.5.4 State and Failure Recovery

The main screen keeps one core visual action button, while clearly presenting the current state, the most recently recognized transcript, the most recently played speech, and any error message. The complete state transition flow is as follows:

```text
idle → recording → finalizing → waitingReply
     → speaking / awaitingConfirmation / failed → idle
```

The message send may only be triggered automatically after the final transcript has been successfully recognized; a partial transcript (an intermediate transitional result) or a recognition failure must never trigger any real-world action. During the `waitingReply` wait-for-response stage, resubmitting requests is forbidden, but the user is allowed to cancel and send an abort command to the server. TTS playback and Maps navigation actions must be precisely deduplicated based on the completed assistant message ID.

#### 4.5.5 Phasing and Non-Goals

The core foreground Car Mode chain has been implemented and landed: the experimental feature switch, the iPhone-specific UI, the dedicated session isolation, VoiceFlow auto-submission, structured reply parsing, Apple TTS speech playback, typed Maps navigation invocation, the Health export callback, and the fallback display of the history in normal Chat.

The follow-up planning focuses mainly on two evolution tracks: first, formally productizing high-frequency capabilities such as Smart Home, email, iMessage, and route-duration into a stable capability boundary; second, comprehensively refactoring the existing synchronous structured request into the `prompt_async + SSE + message reload` asynchronous model, to support more robust foreground/background state recovery and exactly-once idempotent action execution. It should be clear that even after the asynchronous recovery mechanism is completed, it does not mean that voice conversations can continue in the background.

Developing a native CarPlay App, achieving hands-free continuous conversation while Maps is in the foreground, supporting arbitrary URL action jumps, and open-ended real-world automation operations are all explicitly out of the product scope of the current version.

## 5. Data Flow and State Management

### 5.1 Core State Model

```swift
@Observable class AppState {
    // Host profiles
    var hostProfiles: [HostProfile]
    var currentHostProfileID: UUID
    var currentHostProfile: HostProfile

    // Derived connection state for current host
    var serverURL: String              // derived from currentHostProfile.serverURL
    var isConnected: Bool
    var serverVersion: String?
    var sshTunnelConfig: SSHTunnelConfig? // present only for sshTunnel transport
    var connectionTransport: HostTransport
    
    // Project (workspace filter)
    var projects: [Project]
    var selectedProjectWorktree: String?   // nil = use server current
    var customProjectPath: String         // for "Custom path" option
    
    // Sessions
    var sessions: [Session]
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus]  // sessionID → status
    
    // Messages (for current session)
    var messages: [Message]          // ordered by time
    var parts: [String: [Part]]      // messageID → parts
    
    // Models
    var modelPresets: [ModelPreset]   // user-configured
    var selectedModelIndex: Int
    
    // Files
    var fileStatuses: [FileStatus]   // git status
    var sessionDiffs: [FileDiff]     // current session's diffs
    
    // Permissions
    var recentPermissions: [PermissionLog]
}
```

Data migration strategy: in the first implementation, the existing fields such as `serverURL`, Basic Auth, and `SSHTunnelManager.config` may be retained as an expanded cache of the currently active profile, but the single source of truth for data persistence must uniformly converge on `hostProfiles`. When the profile is switched, the selected profile writes the data back into these runtime fields, thereby avoiding a one-off deep refactor that would endanger the runtime stability of the APIClient, SSE, and SSH tunnel modules.

### 5.2 SSE Event Handling

After an SSE event is received, it is dispatched to the corresponding business logic according to its `type` field:

| Event | Handling logic |
|------|----------|
| `session.created` | Append to the sessions list |
| `session.updated` | Update the attributes of the corresponding session |
| `session.status` | Update the sessionStatuses dictionary |
| `session.diff` | Update sessionDiffs (if pushed by SSE; otherwise pulled via `GET /session/:id/diff`) |
| `message.updated` | Update or insert the message |
| `message.part.updated` | Update the corresponding part; if there is a delta, append it to the end of the text part's text |
| `message.part.removed` | Remove it from parts |
| `permission.asked` | Show the permission request card and wait for the user to approve manually |
| `file.edited` | Trigger a file status refresh |
| `session.error` | Show an error toast |

### 5.3 Connection Recovery Strategy

```
App enters the foreground
  ├── Call GET /global/health to confirm the server is alive
  ├── Call GET /session to pull the session list
  ├── Call GET /session/:id/message?limit=6 to pull the most recent 3 turns of the current session
  ├── Call GET /session/status to pull all the session states
  └── Establish the SSE connection to GET /global/event
      └── Subsequent incremental updates are driven by SSE
```

A combined "full state pull + incremental event subscription" model is adopted, ensuring that even if the SSE connection is interrupted by the system while the App is in the background, no state is lost and no data inconsistency occurs when returning to the foreground.

## 6. API Dependency List

The following is the complete list of the OpenCode APIs that the iOS Client needs to call:

### 6.1 Required APIs

| Method | Path | Purpose |
|------|------|------|
| GET | `/global/health` | Connection test, fetch the server version |
| GET | `/global/event` | SSE event stream |
| GET | `/session` | Session list (supports the `directory` and `limit` parameters to filter by project) |
| POST | `/session` | Create a Session |
| GET | `/session/:id` | Session details |
| DELETE | `/session/:id` | Delete a Session |
| GET | `/session/:id/message` | Message list (supports `limit`; by default pulls the most recent 6) |
| POST | `/session/:id/prompt_async` | Send a message (asynchronous) |
| POST | `/session/:id/abort` | Abort the run |
| GET | `/session/:id/diff` | Session diff |
| GET | `/session/status` | All Session states |
| POST | `/session/:id/permissions/:pid` | Respond to a permission request |
| GET | `/question` | Pull the pending questions |
| POST | `/question/:id/reply` | Answer a question |
| POST | `/question/:id/reject` | Reject a question |
| GET | `/file?path=...` | File list |
| GET | `/file/content?path=...` | File content |
| GET | `/file/status` | File git status |
| GET | `/find/file?query=...` | File search |
| GET | `/config/providers` | List of available Providers and models |
| GET | `/agent` | List of available Agents |
| GET | `/project` | Project list |
| GET | `/project/current` | Current project |

### 6.2 Optional APIs (Future Enhancements)

| Method | Path | Purpose |
|------|------|------|
| POST | `/session/:id/summarize` | Compact session (🔲 not implemented yet) |
| POST | `/session/:id/fork` | Fork session |
| GET | `/session/:id/todo` | View the AI's todo list |
| GET | `/find?pattern=...` | Full-text search |
| GET | `/mcp` | MCP service status |
| GET | `/lsp` | LSP status |
| PATCH | `/config` | Modify the configuration |

## 7. UI Wireframe Descriptions

### 7.1 Chat Tab — iPhone

```
┌─────────────────────────────────┐
│ ☰ Sessions    Session Title  ⋯ │  ← Navigation bar
├─────────────────────────────────┤
│ [Claude Opus] [Sonnet 4.6] [G.. │  ← Model switcher bar (horizontal scrolling)
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐  │
│  │ Refactor the auth module  │  │  ← user message
│  │              Claude Opus  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ ▸ Thinking... (collapsed) │  │  ← reasoning part
│  │                           │  │
│  │ I'll start by analyzing   │  │  ← text part (streaming)
│  │ the current auth flow...  │  │
│  │                           │  │
│  │ ┌───────────────────────┐ │  │
│  │ │ 🔧 read_file ✓        │ │  │  ← tool part
│  │ │   src/auth/handler.ts │ │  │
│  │ └───────────────────────┘ │  │
│  │                           │  │
│  │ ┌───────────────────────┐ │  │
│  │ │ 🔧 edit_file ⟳        │ │  │  ← tool running
│  │ │   src/auth/handler.ts │ │  │
│  │ └───────────────────────┘ │  │
│  │                           │  │
│  │ ⚠️ Permission required:   │  │  ← permission request (manual approval required)
│  │  shell: npm test [Approve]│  │
│  └───────────────────────────┘  │
│                                 │
├─────────────────────────────────┤
│ │ Type a message...    │ ➤ 🎤   │  ← input field (send + microphone)
└─────────────────────────────────┘
```

### 7.2 Files Tab — iPhone

```
┌─────────────────────────────────┐
│         Files                   │
├─────────────────────────────────┤
│ [File Tree]                     │
├─────────────────────────────────┤
│ 🔍 Search files...              │
├─────────────────────────────────┤
│ ▼ src/                          │
│   ▼ auth/                       │
│     ● handler.ts        +12 -5  │  ← modified (yellow dot)
│     ○ types.ts                  │
│   ▶ api/                        │
│   ▶ utils/                      │
│ ▼ tests/                        │
│   ● auth.test.ts        +45 -0  │  ← new file (green dot)
│ ○ package.json                  │
│ ○ tsconfig.json                 │
└─────────────────────────────────┘
```

Tapping a file pushes to the file detail page:

```
┌─────────────────────────────────┐
│ ◀ Files   handler.ts   [Diff]  │
├─────────────────────────────────┤
│  1 │ import { Router } from ... │
│  2 │ import { verify } from ... │
│  3 │                            │
│  4+│ export async function      │  ← added line (green background)
│  5+│   authenticateUser(        │
│  6+│   req: Request             │
│  7 │ ) {                        │
│  8-│   const token = req.head.. │  ← deleted line (red background)
│  9+│   const token = extractT.. │  ← added line
│ 10 │   ...                      │
└─────────────────────────────────┘
```

### 7.3 Settings Tab — iPhone

```
┌─────────────────────────────────┐
│         Settings                │
├─────────────────────────────────┤
│                                 │
│ SERVER CONNECTION               │
│ ┌─────────────────────────────┐ │
│ │ Address   192.168.0.80:4096   │ │
│ │ Username  opencode          │ │
│ │ Password  ••••••••          │ │
│ │ Status    🟢 Connected      │ │
│ │           [Test Connection] │ │
│ └─────────────────────────────┘ │
│                                 │
│ APPEARANCE                      │
│ ┌─────────────────────────────┐ │
│ │ Theme             [Auto   ▾]│ │
│ └─────────────────────────────┘ │
│                                 │
│ SPEECH RECOGNITION              │
│ ┌─────────────────────────────┐ │
│ │ AI Builder Base URL  (space.ai-builders.com/backend) │ │
│ │ AI Builder Token     •••••• │ │
│ │           [Test Connection] │ OK │
│ └─────────────────────────────┘ │
│                                 │
│ ABOUT                           │
│ ┌─────────────────────────────┐ │
│ │ App Version        0.1.0    │ │
│ │ Server Version     1.1.61   │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

## 8. Development Phases

### Phase 1 — Minimum Viable Version (MVP)

**Goal**: successfully connect to the server, send messages normally, and receive the AI's streaming responses in real time.

| Feature | Description |
|------|------|
| Server connection | Manual IP:Port entry, Basic Auth |
| SSE event stream | Connect, disconnect, reconnect, foreground/background switching |
| Basic session support | List, create, switch (delete not implemented yet) |
| Message sending | Text input, sending (using `prompt_async`), viewing the response; messages are queued automatically while busy |
| Streaming rendering | Real-time typewriter effect for the text part |
| Model switching | Preset model list, specifying the model when sending |

**Estimated effort**: 2-3 weeks (assuming prior SwiftUI development experience)

### Phase 2 — Full Interaction

**Goal**: deliver effective monitoring and review capability over the AI's entire execution flow.

| Feature | Description |
|------|------|
| Message Part rendering | All Part types: reasoning, tool, step, patch, etc. |
| Manual permission approval | Listen for permission.asked, show the request card, the user approves manually |
| Abort / Compact | Abort the run, compact the session |
| Markdown rendering | Full Markdown rendering in AI messages |
| Theme switching | Follows the system Light/Dark theme |
| Code block highlighting | Syntax highlighting for code blocks in messages |
| **Think Streaming** | Delta incremental updates (typewriter effect), Tool collapsed by default after completion |

**Estimated effort**: 2 weeks

### Phase 3 — File Browsing, Document Review, and the iPad / Vision Pro Layout

**Goal**: complete the full file browsing and **document review** capabilities, and finish the large-screen three-column layout adaptation for iPad and Vision Pro.

| Feature | Description |
|------|------|
| File tree | Directory expand/collapse, git status markers |
| File content | Line numbers, monospaced font (syntax highlighting not implemented yet) |
| File search | Fuzzy search by file name |
| Markdown preview | Preview mode first, supporting Markdown/Preview switching |
| Document Diff | Highlight the changes (prefer highlighting inside Preview, otherwise inside Markdown) |
| Session Diff | The changed file list and diff view of the current session |
| Single-file Diff | The uncommitted changes of a file |
| **Think Streaming** | Delta incremental updates (typewriter effect) |
| **iPad / Vision Pro layout** | No Tab Bar; three columns: Workspace (Files+Sessions) on the left, Preview in the middle, Chat on the right; Settings as a button in the first toolbar row |

**Estimated effort**: 2-3 weeks

### Phase 4 — Polish and Enhancements (Not Implemented Yet, Ordered by Priority)

| Feature | Description |
|------|------|
| **Push notification / Live Activity** | When the AI pauses to wait for a human decision (question / permission / run completed), proactively raise a notification through APNs or a Live Activity, eliminating the human–machine asynchronous idling. This is the core engineering capability for completing the Steer loop |
| **Improved Session distinguishability** | Optimize the visual distinction between active and inactive Sessions, reducing the cognitive burden of locating the target session in a long list |
| mDNS auto-discovery | Automatically discover OpenCode servers inside the LAN |
| Widget | Provide an iOS home-screen widget that shows the current session state in real time |
| Haptic feedback | Introduce haptic vibration feedback at key interaction points |
| Spotlight integration | Support quick retrieval of recent sessions through the system Spotlight |

## 9. Known Limitations and Risks

**Network dependency**: the App depends entirely on the network connection to the OpenCode Server. If the Server is unreachable (for example, due to a network outage or because the Server process is not running), the App cannot work properly. Two modes are currently supported: direct LAN access and SSH tunnel remote access; in weak network environments, the "pull the most recent 3 turns + pull-down paginated loading" strategy reduces the first-screen waiting time.

**SSE behavior on iOS**: when the App enters the background, the iOS system aggressively reclaims network resources and drops the long connection. A robust reconnection mechanism and foreground state recovery logic must therefore be designed, and keeping SSE alive in the background is not recommended.

**Screen size**: in the narrow space of an iPhone, the horizontal layout and readability of code and diff content face objective challenges. Interaction details such as horizontal scrolling and font scaling need careful optimization. Relatively speaking, the larger iPad screen provides a better visual presentation.

**Server API stability**: OpenCode's HTTP API does not currently provide a strict versioning commitment (for example, no `/v1/`-style version prefix has been introduced). The evolution of later Server versions may introduce breaking changes. The iOS client is advised to parse API responses defensively, silently ignoring unknown fields instead of crashing outright.

**Security policy**: in its early stages the App is mainly used in trusted local LAN environments, so the overall security risk is manageable. If direct public-internet access is opened up later, hardening such as TLS encryption and token-based authentication must be introduced comprehensively. The Basic Auth over HTTP currently used applies only to LAN environments and must not be exposed directly to the public internet. **ATS policy exceptions**: HTTP is allowed for the LAN (private IP ranges, localhost, .local) and Tailscale MagicDNS (`*.ts.net`); all other public WAN requests strictly require HTTPS. The `NSExceptionDomains` in Info.plist has already been configured with the corresponding exemption for `ts.net`.

**Human–machine asynchronous idling (missing notifications)**: when the AI suspends because it triggers the `question` tool, requests a permission, or waits for human review, and the user has already left the App (iOS in the background), there is currently no way to notify proactively. This leaves both sides in a mutually waiting "idle spin" state — the AI waits for a human instruction while the human does not know that a decision is needed. The essence of this problem is an iOS system engineering limitation rather than a matter of pure UX interaction design: push notification (APNs) or Live Activity must be introduced to break through the background restrictions and actively wake the user. Although this capability is marked as "not implemented yet" in Phase 4, it should be treated as a high-priority engineering enhancement — it directly determines the closed-loop efficiency of the Steer paradigm.

## 10. Resolved Decisions

1. **Message sending API**: `POST /session/:id/prompt_async` is chosen. Research on the server source code confirms that the synchronous (sync) and asynchronous (async) interfaces both call the same underlying `SessionPrompt.prompt()` logic; the async mode simply does not block while waiting for the final response; the two behave identically in message creation, task processing, and SSE event pushing. Given that the iOS client uniformly relies on SSE to obtain real-time results, the async asynchronous mode is the more reasonable choice.

2. **Large Sessions**: no special handling for now. The current design expects that the number of messages in a single session will not exceed a hundred.

3. **Push notification**: not implemented at this stage, but already identified as a high-priority engineering enhancement — when the AI suspends to wait for a human decision (such as question / permission / run completed), APNs or Live Activity must be used to bypass the iOS background restrictions and reach the user proactively, thereby eliminating the human–machine asynchronous waiting.

4. **Multi-project support**: not implemented at this stage.

5. **Default Server**: the default address is `127.0.0.1:4096`. Authentication is disabled by default, but the client must fully implement Basic Auth authentication support so that it can be configured as needed.

## 11. Getting Started Guide

### 11.1 Project Setup

The current repository already contains a complete Xcode project that can be opened directly. For developers joining the project, the following two starting approaches are recommended:

1. Install the prebuilt version directly through the TestFlight link provided in the README to try it out
2. Clone the local repository and open `OpenCodeClient/OpenCodeClient.xcodeproj` directly for local building and debugging

### 11.2 Dependencies and Structure

- **Networking**: REST requests and the SSE event stream are implemented natively with `URLSession`, with no need to introduce third-party networking libraries such as Alamofire
- **State management**: iOS 17+'s native `@Observable` is used together with SwiftUI to implement reactive state binding
- **Markdown**: integrates the open-source library [MarkdownUI](https://github.com/gonzalezreal/MarkdownUI)
- **Theme**: observed through `@Environment(\.colorScheme)` and following the system theme
- **SSH Tunnel**: integrates the Citadel library to implement the SSH tunnel capability

The current client code follows a clear directory architecture layered by responsibility:

- `Views/`: contains the UI views of modules such as Chat, Files, Settings, and Split View
- `Controllers/`: hosts the logic controllers for interaction events such as permission and question
- `Services/`: encapsulates the core services such as API communication, the SSE event stream, SSH tunnels, voice recording and transcription
- `Stores/`: manages the core business state such as Session, Message, File, and Todo
- `Models/`: defines data structures such as Session, Message, Project, Question, and ModelPreset
- `Support/`: collects the localization resources and the general support components
- `Utils/`: provides basic utility libraries such as Keychain storage, PathNormalizer path handling, and the LayoutConstants layout constants

### 11.3 Recommended Implementation Order

1. **Phase 1**: get the Server connection, the SSE event stream, Session management, message sending, and basic streaming rendering working
2. **Phase 2**: implement full message Part rendering, manual permission approval, theme switching, and the message queueing mechanism based on `prompt_async`
3. **Phase 3**: complete the file tree, the Markdown preview, the document Diff comparison, and the change highlighting rendering

### 11.4 Integration with the OpenCode Server

The default Server connection address is `127.0.0.1:4096` (no authentication). If the server has enabled authentication environment variables such as `OPENCODE_SERVER_PASSWORD`, just fill in the corresponding Username and Password in the client Settings. In the direct LAN scenario it can be configured directly with the LAN IP address of the server; in the remote access scenario it can be forwarded through an SSH tunnel proxy to the local `127.0.0.1:4096` port.

---

## Appendix A — Reference for the Key OpenCode Server Data Structures

### Session

```typescript
{
  id: string
  slug: string
  projectID: string
  directory: string
  parentID?: string
  title: string
  version: string
  time: { created: number, updated: number }
  share?: { url: string }
  summary?: { additions: number, deletions: number, files: number }
}
```

### Message (User)

```typescript
{
  id: string, sessionID: string, role: "user",
  model: { providerID: string, modelID: string },
  time: { created: number }
}
```

### Message (Assistant)

```typescript
{
  id: string, sessionID: string, role: "assistant",
  parentID: string,  // links to user message
  providerID: string, modelID: string,
  cost: number,
  tokens: { input: number, output: number, reasoning: number, cache: { read: number, write: number } },
  time: { created: number, completed?: number }
}
```

### Part (core types)

```typescript
// Text
{ id, type: "text", text: string }

// Reasoning
{ id, type: "reasoning", text: string }

// Tool call
{ id, type: "tool", callID: string, tool: string, state: "pending"|"running"|"completed"|"error", metadata?: any }

// Step markers
{ id, type: "step-start", snapshot?: string }
{ id, type: "step-finish", reason: string, cost: number, tokens: {...} }

// File change
{ id, type: "patch", hash: string, files: [...] }
```

### FileDiff

```typescript
{
  file: string,       // relative path
  before: string,     // full content before
  after: string,      // full content after
  additions: number,
  deletions: number,
  status?: "added" | "deleted" | "modified"
}
```

### SSE Event

```typescript
{
  directory: string,  // project path, or "global"
  payload: {
    type: string,     // e.g. "message.part.updated"
    properties: any   // event-specific data
  }
}
```
