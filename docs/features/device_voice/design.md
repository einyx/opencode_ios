# Device-only voice — design

> Status: **landed** (2026-10-26). Plan: `plan.md`.
> Every voice surface now runs on the device: the streaming on-device recogniser, the
> device voice engine, the iPhone Ambient tab, the watch (whose microphone travels to
> the phone), and the removal of the hosted path and its token.
> Related: `docs/appstore/privacy-policy.md` (published copy), `docs/appstore/review-notes.md`.

## Intent

Voice should not need a third-party account. Today **Ambient Mode** — the hands-free
car surface — is the only voice feature that cannot be used without setup: it runs on
the hosted "AI Builder Space" realtime service and refuses to start without the user's
access token (`AppState+CarLive.swift:58-62`). The one surface that is supposed to be
hands-free is the one that needs a key first.

Dictation already has the answer — Apple on-device recognition, no token — so the
inconsistency is not "the app needs a key", it is "the app needs a key for *some* of its
voice". The hosted realtime service is also the only part of the app that uploads raw
audio to somebody else's server.

This change makes **every** voice surface in the app run on the user's own devices:
recognition on the device, the user's own OpenCode server as the conversation brain,
synthesis on the device. The hosted service, its token, its settings and its realtime
gateway are removed.

## Goals

- **G1** Ambient Mode starts and holds a conversation with no token, no portal URL and
  no third-party account.
- **G2** Every speech-recognition path is on-device, on iPhone **and** on the watch.
- **G3** Every speech-output path is on-device (`AVSpeechSynthesizer`).
- **G4** The conversation brain is the user's own OpenCode server. A voice turn is text
  to the user's server and nothing else.
- **G5** The watch keeps a working voice surface and needs no credential of its own.
- **G6** The hosted voice service is gone from the app: no token field, no portal URL,
  no realtime gateway client, no hosted function tool set.
- **G7** Audio never leaves the device except as recognised text sent to the user's own
  server.
- **G8** The Ambient screen shows the live transcript while the user speaks, and the
  spoken reply can be interrupted by speaking again.

## Non-goals

- **NG1** No full-duplex realtime conversation. A turn is request/response: speak, the
  app transcribes, the server answers, the app speaks. The hosted `gpt-live-1` duplex
  session is gone.
- **NG2** No client-side job orchestration. The hosted model called the phone's
  `query_jobs` / `start_job` / `continue_job` / `stop_job` / `archive_job` tools; in the
  new design the *server's own agent* does that work, directly against the server it
  already runs. The phone-side tool set is deleted.
- **NG3** No hosted cost/usage ledger in the Ambient UI. It was portal-specific
  (`portalEstimatedUSD`, `portalUsageSettled`).
- **NG4** No new server endpoint. The turn uses the existing session, prompt and
  structured-output APIs.
- **NG5** The voice-first composer keeps its current shape. Only its *engines* change:
  the three cloud engines disappear, the on-device engine stays.
- **NG6** No attempt at continuous background listening. Ambient Mode listens while its
  screen is up, exactly as the hosted path did.

## Wire facts the design is built on

| Fact | Consequence |
|---|---|
| **watchOS ships no `Speech.framework` at all** — no `SFSpeechRecognizer`, no `SpeechAnalyzer` | The watch cannot transcribe locally. It must stream mic audio to the phone, which already has `AppleSpeechTranscriber`. |
| `AVSpeechSynthesizer` **is** available on watchOS (2.0+) | The watch can speak replies locally; only recognition has to move to the phone. |
| `AppleSpeechTranscriber` is **file-based only** today (`SFSpeechURLRecognitionRequest`) | A live mic needs a new streaming path (`SFSpeechAudioBufferRecognitionRequest`). |
| `submitCarTurn(_:)` (`AppState+CarMode.swift:41`) is already a complete **token-free** turn: ensure the "Ambient Mode" session → `promptStructured` → speak `envelope.speech` | The conversation loop exists. Only its **input** side is missing. |
| `promptStructured` returns the finished assistant message and never touches the message store | A voice turn adds no rows to the chat transcript. |
| The ambient session is a *different* session, and every SSE message branch is session-guarded (`AppState+SSE.swift`) | Voice turns do not pollute the chat view of whatever session is open. |
| `CarLiveAudioEngine` already captures PCM16 / 24 kHz / mono on iOS **and** watchOS (an `AVAudioEngine` input tap) | Mic capture exists for both platforms; it is currently wired to the hosted socket instead of a recogniser. |
| `VoiceFlowMicrophone` (VoiceFlowKit) is the app's **only** recorder and level meter | Dropping the package requires an in-app recorder — which the Ambient path needs anyway. |
| `WatchPhoneBridge.begin()` returns `portal` + `token` to the watch; `CarLiveController.start()` requires a non-empty `builderToken` | Both gates go; the watch's `begin` reply carries the run id and nothing else. |
| `WCSession.sendMessage` needs a reachable phone and is size-bounded — the repo already chunks tool output at 8 KiB with a SHA-256 digest | Mic audio goes up in the same chunked shape the tool-output path already uses. |
| `state.respondPermission(_:response:)` is session-scoped by `perm.sessionID` | A voice turn can answer its own permission request without the chat transcript being involved. |

## The design, as shipped

### 1. One voice engine, two platforms

A new `DeviceVoiceEngine` owns the whole loop and is the only voice entry point left:

```
mic ──▶ on-device recognition ──▶ transcript ──▶ turn ──▶ spoken reply
```

- **iPhone** — `AppleSpeechTranscriber` gains a streaming sibling
  (`SFSpeechAudioBufferRecognitionRequest`, `requiresOnDeviceRecognition = true`,
  `shouldReportPartialResults = true`) fed by the existing `CarLiveAudioEngine` tap.
  Partial results drive the live transcript; a silence threshold ends the utterance.
- **Watch** — the watch has no recogniser, so it streams its mic frames to the phone
  over the existing WatchConnectivity channel. The phone recognises, runs the turn and
  sends the reply text back; the watch speaks it with a local `AVSpeechSynthesizer`.

The engine has one input (a transcript) and one output (a spoken reply), so the phone
and the watch share the turn logic and differ only in who recognises and who speaks.

### 2. The turn

The turn is `submitCarTurn(_:)`, unchanged: the "Ambient Mode" session is created or
reused, `promptStructured` asks for the structured envelope, and the envelope's
`speech` field is spoken by `carSpeechOutput` (already on-device).

- Progress while the server works comes from `session.status` and
  `ActivityTracker.bestSessionActivityText` — both already work for any session.
- The reply is spoken as one utterance. A new utterance while the app is speaking
  interrupts it (barge-in), which the hosted path also supported.

### 3. Permission and confirmation by voice

The token-free path had no permission handling; the hosted path answered permissions
by voice (`AppState+CarLive.swift:336-384`). The device path re-implements that one
behaviour, and adds the confirmation the agent asks for at the end of a turn:

- `permission.asked` for the ambient session is announced by voice.
- The spoken answer ("yes" / "no") is parsed and sent with `state.respondPermission`.
  Matching is whole-word, so "I don't know" cannot read as a refusal.
- The agent's structured envelope can end a turn with `needs_confirmation` and a
  prompt. The prompt is asked out loud with "say confirm or cancel", and the answer
  continues the turn: it goes back to the server as the next thing the user said.
- Both answers follow the **delivery mode**: on the watch they are spoken on the
  wrist, not on the phone next to the user's arm.

### 4. What is deleted

| Removed | Why it goes |
|---|---|
| `aiBuilderToken`, `aiBuilderBaseURL`, `aiBuilderCustomPrompt`, `aiBuilderTerminology`, the connection test and the Keychain entry | The hosted service is gone; nothing needs a credential. |
| The AI Builder block in Settings → Input & Voice, and the three cloud engines in the strategy picker | Ditto; the picker keeps only the on-device engine. |
| `CarLiveTransport` + the ticket handshake + `/v1/audio/live/sessions` | The hosted gateway is gone. |
| `CarLiveController`'s hosted session (start/stop/captions/tool calls/barging) | Replaced by `DeviceVoiceEngine`. Its audio engine is kept. |
| `CarLiveTools` — the eight hosted functions and their server wrappers | NG2: the server's own agent does this work. |
| `CarLiveReplyBridge`'s hosted commentary path and the portal cost ledger | Portal-specific. |
| The `VoiceFlowKit` package | Its only remaining job was the hosted service; its recorder is replaced in-app. |
| `CarLiveProtocol`'s portal constants, `CarLiveModels`' hosted wire types | Portal-specific. |

The **in-app recorder** that replaces `VoiceFlowMicrophone` is a prerequisite, not an
optional extra: the chat composer's dictation uses it for the level meter and the WAV
file, and the Ambient path uses it for the live recogniser feed.

### 5. The watch

The watch stops being a second hosted client and becomes a remote control for the
phone's engine:

- **Up:** the watch's mic frames go to the phone as `audio` messages. The phone
  recognises them, because watchOS has no recogniser.
- **Down:** the answer comes back as text over the `voice` op; the watch speaks it
  locally with `AVSpeechSynthesizer` and shows it as a caption.
- The `begin` reply no longer carries `portal` or `token` — it carries the run id and
  nothing else.
- The watch's tool bridge (`tool` / `result` / `pull` / `ack`) went with the hosted
  path: the phone's engine runs the turn, so the watch no longer executes tools.

The watch still needs the phone: `sendMessage` only reaches a reachable phone, exactly
as the existing tool bridge already requires.

### 6. Accessibility

- The Ambient screen announces the phase as text *and* as speech; the caption line is
  the transcript, not a decoration.
- Every spoken prompt has a visible twin, so a deaf user can drive the same flow.
- Barge-in is available from the mic button as well as by speaking.
- The watch's status line and caption remain the visible twin of everything it speaks.

## Test coverage

Planned, in the order the stages land:

- `DeviceVoiceEngineTests` — utterance end detection, barge-in, partial-transcript
  ordering, turn ownership and cancellation.
- `OnDeviceStreamingRecognizerTests` — the request is pinned to on-device recognition,
  partials are reported, a final result resolves exactly once.
- `AmbientVoiceTests` — a turn creates/reuses the ambient session, speaks the
  envelope, adds no rows to the chat transcript, and answers a permission by voice.
- `WatchVoiceBridgeTests` — the audio reaches the phone's engine, the answer comes
  back, and **no credential crosses the bridge**.
- Source guards — no `aiBuilderToken`, no `portal`/`token` in the watch `begin` reply,
  no `Speech.framework` import in the watch target.
