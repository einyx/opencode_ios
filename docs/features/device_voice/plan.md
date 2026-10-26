# Device-only Voice — Implementation Plan

> Status: **stages 1–6 landed** (2026-10-26) — the app has no hosted voice path
> left. The iPhone and the Apple Watch both recognise on the device and speak on the
> device, and the only thing that leaves the device is text to the user's own
> server. Still to do: the App Store copy, the published privacy policy and a new
> build. Spec: `design.md` (read it first — it carries the wire facts). Plan: this
> file. Design: `design.md`.

**Goal:** Make every voice surface in the app work with no third-party account, no
pasted token and no audio leaving the device — Ambient Mode, the dictation engines and
the Apple Watch included.

**Architecture:** One engine, two platforms. `DeviceVoiceEngine` turns microphone
frames into a transcript, runs a turn, and speaks the reply. On the iPhone the
recognition is local (`SFSpeechAudioBufferRecognitionRequest`, on-device pinned); on the
watch it is not possible — watchOS ships no `Speech.framework` — so the watch streams
its mic frames to the phone, which recognises them and runs the turn. The turn itself
is `submitCarTurn(_:)`, which already exists and already needs no credential: the
"Ambient Mode" session, `promptStructured`, and on-device `AVSpeechSynthesizer`.

**Tech Stack:** Swift 5 / SwiftUI / Swift Testing, iOS 17+, watchOS 11. Apple Speech
framework (iOS only), `AVSpeechSynthesizer` (iOS + watchOS). OpenCode V1 + V2 HTTP APIs.

## Global Constraints

- Unit tests run through `./scripts/test_unit.sh`; `xcodebuild build`/`test` run
  sequentially (shared build database).
- Tests that build `AppState` must pass an isolated `userDefaults:` suite.
- New files are auto-included (`PBXFileSystemSynchronizedRootGroup`).
- Every new `L10n.Key` needs **both** English and zh-Hans entries (`LocalizationTests`).
- No magic visual values — `DesignTokens` only; Views never call `.opacity(` and never
  use `Semantic.error/success/warning`.
- Protocol changes must not break the 13 existing `APIClientProtocol` conformers: new
  requirements get **protocol extension defaults**.
- **No credential may cross the WatchConnectivity boundary.** The watch's `begin`
  reply carries the run id and nothing else. A source guard asserts it.
- **No `Speech.framework` (or `SpeechAnalyzer`) import in the watch target.** watchOS
  has no such framework; a source guard asserts it, so the watch never grows a
  transcription path it cannot run.
- The App Store submission (build 33) is **in review** and the privacy policy is
  **published**. A change to the voice architecture needs a new build (34) and a
  republished policy; the submitted build still ships the hosted path.

## Tasks

1. **Streaming on-device recogniser — done.** `OnDeviceSpeechSession` wraps a
   `StreamingSpeechRecognizing` seam and Apple's `SFSpeechAudioBufferRecognitionRequest`
   adapter: on-device pinned, partial results, one final result per utterance, and a new
   request per utterance on the same recognizer. *Tests: `OnDeviceSpeechSessionTests` —
   authorization, missing recognizer, on-device probe, ordered transcripts, audio only
   after start, one end per utterance, cancel closes the stream, regional locale
   fallback.*
2. **Device voice engine + Ambient tab cutover — done.** `DeviceVoiceEngine`: the
   microphone (the existing `CarLiveAudioEngine` capture, converted 24 kHz → 16 kHz) →
   the recogniser → the live transcript → the utterance end (silence backstop) →
   `submitCarTurn` → the spoken answer, with barge-in cancelling the abandoned turn. The
   Ambient tab now renders `AmbientVoiceView` instead of the hosted `CarLiveView`, which
   makes the whole hosted path unreachable in production. `submitCarTurn` returns the
   answer text so the caller decides who speaks it. *Tests: `DeviceVoiceEngineTests` —
   final → spoken answer, partial without a turn, barge-in, missing microphone, stop
   releases the mic, frames reach the recogniser.*
3. **Permission by voice — next.** A `permission.asked` for the ambient session is
   spoken and answered by voice; `question.asked` uses the structured envelope's
   `confirmation` prompt. Answered with `state.respondPermission`.
4. **Watch: audio up, reply down.** New WatchConnectivity ops for mic frames (8 KiB
   frames, SHA-256 digest, sequence numbers, reusing the existing chunked shape) and
   for the transcript/reply text; local `AVSpeechSynthesizer` on the watch; the
   `begin` reply loses `portal` and `token`.
5. **In-app recorder.** Replace `VoiceFlowMicrophone` (VoiceFlowKit) with an
   app-owned recorder: PCM16 / 24 kHz / mono capture, a smoothed level meter and a WAV
   writer. It backs the composer's dictation. *Tests: level smoothing, WAV header,
   capture-stop-resets.*
6. **Delete the hosted path.** The AI Builder token/base URL/custom prompt/
   terminology and its Settings block; the three cloud speech engines and the strategy
   picker rows for them; `CarLiveTransport` + the ticket handshake;
   `CarLiveController`'s hosted session; `CarLiveTools`' eight hosted functions;
   `CarLiveReplyBridge`'s hosted commentary path; the portal cost ledger; the
   `VoiceFlowKit` package, its licence manifest entries and the generated notices. The
   24 polish-lint baseline entries for the deleted views go with them.
   *Tests: the suites for the deleted code go with it; the surviving suites must stay
   green.*
7. **Docs + App Store.** This folder and the `docs/README.md` index row are done. Still
   to do: the **published** privacy policy (drop the "Cloud (opt-in)" path, describe
   Ambient Mode as on-device); `docs/appstore/review-notes.md` (the watch description is
   inaccurate today — it says the watch does not run tools itself while it runs a
   hosted session); `docs/appstore/app-privacy.md` (the answers stay "Data Not
   Collected", now without the cloud-speech caveat); `docs/appstore/submission-checklist.md`;
   new build 34 uploaded and attached to version 1.0.


## Verification

- `OpenCodeClientTests/DeviceVoiceTests` — the engine, the recogniser, the permission
  answer, the watch bridge.
- Full unit suite — expected to shrink (the hosted suites go) and must stay green.
- `scripts/polish_lint.sh` — clean.
- New source guards — no `aiBuilderToken` left in the app tree, no credential in the
  watch `begin` reply, no `Speech.framework` in the watch target.
- Device check — Ambient Mode on a real iPhone and on a real Apple Watch, with the
  phone on the user's own server and **no** AI Builder token set anywhere.

## Deferred

- Full-duplex realtime conversation (the hosted `gpt-live-1` duplex session is gone).
- On-device recognition **on the watch** — watchOS has no `Speech.framework`, so this
  is not deferral but a platform limit; the watch streams to the phone instead.
- Live partial transcripts in the chat composer (dictation still shows its text when
  the recording stops).
- A watch-side turn that runs without the phone (the phone owns the server connection).
- Portal cost/usage reporting (portal-specific, and there is no portal).
