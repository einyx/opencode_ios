# Watch Ambient Voice Entry PRD (Experimental)

## Current Status: Experimental

On-device voice input, playback, and tool result return have been proven to work, and a connection was also established successfully once while the phone app was not in the foreground. However, the connection still drops during an answer or in the second turn; an explicit reconnect recovers it, and it can drop again afterwards. The current version is integrated as an experimental feature and is not a stable continuous-conversation entry point.

The directly observed trigger is an incomplete audio frame send, after which the watch client drops the connection at the 5-second deadline; the underlying cause is unconfirmed. It also reproduces with the phone in the foreground and the devices next to each other, and the current evidence is insufficient to attribute it to WatchConnectivity. Continuous background operation, lock screen, and SSH wake-up recovery are still to be verified.

The Watch connects to the existing Live gateway on its own to send and receive real-time voice, all OpenCode tool calls are handed to the paired iPhone for execution, and ending the voice session on the watch does not stop OpenCode work that is still running in the background.

This document is aimed at implementers who are already familiar with the OpenCode iPhone client, and defines the product scope, interaction boundaries, and on-device acceptance criteria for the first version of the Watch voice entry point. The first version must deliver a workable raise-the-wrist voice experience without changing the existing eight-tool contract and without moving host credentials onto the watch, instead of building another approval platform or cross-device scheduling framework.

## 1. What The User Can Do

The user can start Live voice on an Apple Watch. The watch uses its own microphone and speaker. Each time voice starts, the watch first asks the phone for the Builder token and portal address via an interactive reply and keeps them in memory only; after receiving the in-memory credentials for that run, it requests the recording permission and activates local audio; only after audio succeeds does it POST the session path on the existing Live portal to create the session and open the returned WebSocket. Session creation still goes through the existing path `/v1/audio/live/sessions`, which is the HTTP ticket-exchange entry point, not the WebSocket address itself. The voice model is fixed to `gpt-live-1`, hosted inference is fixed to `gpt-6-luna`, and the default voice is `marin`. The conversation supports continuous voice, explicit mute and unmute, and interrupting playback. Muting goes through mute / unmute, and neither muting nor a mute frame ends the session.

The interface stays minimal. One large microphone button that becomes an interrupt button in the same place while speaking. Below it, the most recent few lines of transcript. Mute and End sit in a corner or along the bottom edge. A single status line covering connecting, listening, executing on the phone, unreachable, result unknown, and voice ended. No second screen and no preemption state machine.

The tool requests spoken on the watch use the same eight names as on the phone: `query_jobs`, `get_session_messages`, `start_job`, `continue_job`, `stop_job`, `answer_pending`, `archive_job`, `unarchive_job`. The Watch hands the calls to the paired iPhone over WatchConnectivity. The phone reaches OpenCode through the direct connection already configured (LAN, VPN, Tailscale, or HTTPS) or through the existing single local SSH tunnel listener, using the second `APIClient` owned exclusively by the Watch bridge and its own `URLSession`. A tool call is accepted first, and the reply does not carry the output body; the watch pulls the body in fixed 8192-byte `Data` chunks with the total length and sha256, verifies the reassembled body, and only then feeds it into its own Live socket. Commentary and the final result are preferably pulled by the watch about every 2 seconds, which drives the independent reply bridge on the phone to poll with this sibling client, without connecting to or reading the global SSE.

When the user ends voice on the watch, only the watch's own Live connection is dropped, the in-memory credentials are cleared, and the phone bridge run for that session is released. Already accepted OpenCode work keeps running. Ending voice does not call `stop_job`. The user does not have to keep watch voice running to sustain background work. A commentary entry is acked to the phone only after the watch's own gateway has emitted `commentaryAppended` with a matching identifier; when voice ends, unacked records are dropped and results are not re-sent.

The Watch and iPhone Ambient each own their microphone, speaker, and Live connection. Starting, muting, or ending on the watch does not start, stop, or mute the phone's `CarLiveController`, and does not route audio to the phone.

## 2. What We Do Not Do

The Watch does not run Tailscale, does not establish an SSH tunnel, and does not store an SSH private key, host password, basic auth credentials, or the whole host profile. Access to the OpenCode host stays on the phone side. The Builder token and portal address on the watch live only in memory: they are not written to the watch Keychain, not put in UserDefaults, not put in `applicationContext`, and not put into any other transport that persists to disk.

The eight-tool set keeps `answer_pending`, but the watch does not provide full approval. It uses the binding of its own Watch run, handles items through the token-carrying read and reply interfaces, and reads once more after submitting to confirm. It does not use the revision of the phone's pending list and does not call the phone Ambient approval function. When there is no binding or the item cannot be read, it returns `needs_input` without writing anything; the copy says there is nothing pending, and in fact nothing was approved. Permission replies accept only `once` or `reject`, do not support always, do not discover requests across sessions, and do not show the full command scope. A failed confirmation is `not_confirmed`, and the pending item is kept. All of these cases direct the user to the phone's OpenCode interface. This version does not create a new approval state machine.

The eight tools are neither added to, removed from, nor renamed, and no host, account, or secret is stuffed into the parameters. No custom encryption protocol is built on top of WatchConnectivity, file transfer is not used, and the output body is never placed into an asynchronous queue that could still deliver after the run ends. Do not add a second slot to the existing `CarLiveTransportGate`, and do not call `armLiveTransport()` or `startCarLive()`. When the phone is unreachable, the host is unreachable, the request times out, or the result is unknown, the user is told directly; side-effecting requests are not queued and are not automatically replayed after the network recovers. No cross-device preemption state machine is built.

For `start_job` and `continue_job`, HTTP 200/202/204 only means the call was accepted. Without evidence of a result, neither the voice nor the UI may say the task is complete.

## 3. First-Round On-Device Acceptance

The first round only verifies watch voice plus read operations through the phone bridge; it does not automatically create work and does not do approvals.

1. The phone already has a usable Live portal address, a Builder token, and a connection to OpenCode. Each time voice starts, the watch asks the phone for the Builder token and portal address via an interactive reply, and uses them only in that launch call — never reused across rounds and never persisted. Without a reply it does not record and does not POST. The watch's background audio and cleanup behavior still await on-device acceptance.
2. The watch first obtains the in-memory credentials for that run, then requests the recording permission and activates 24 kHz, mono, Int16 PCM audio (without calling `setPreferredSampleRate` or `setPreferredIOBufferDuration`). On failure it clears the credentials and stops, without POSTing and without opening a socket. Only after success does it POST the session path to create the Live session and open the returned WebSocket. The 20-second started deadline is counted from opening the socket. Mute, unmute, interrupt, and ending voice are available.
3. `query_jobs` must explicitly set `archivedOnly=false`, with a small count. The default `true` only finds archived items. Results are announced by voice, without reading out session IDs or paths.
4. `get_session_messages` only reads sessions that already exist.
5. This round does not proactively call `start_job`, `continue_job`, `stop_job`, `archive_job`, `unarchive_job`, or `answer_pending`. The eight tools stay in the schema, for when the user explicitly asks for them later.

## 4. What The User Sees On Failure

The WatchConnectivity envelope is fixed to `v`, `op`, `run`, `call`, `seq`, `payload`. `v` is 1. The failure semantics must distinguish at least `unreachable`, `stale`, `unknown`, `duplicate`, `needs_input`, and `not_confirmed`. Only `ready` allows the body pull to continue. Neither unknown nor invalidated results are replayed.

| Failure scenario | What the user sees | System boundary |
|---|---|---|
| Token or portal address not ready | Please prepare voice credentials in OpenCode on iPhone first | Without an interactive reply there is no recording and no POST; memory only, never written to the watch Keychain, UserDefaults, `applicationContext`, or logs, and no fallback token is embedded |
| Audio activation failed | Audio cannot start, returning to standby | Clear the in-memory credentials for that run, do not POST, do not open a WebSocket |
| The paired phone is unreachable, or the phone cannot reach the host | The phone is unreachable, or it cannot execute right now | Return `unreachable`; when the phone is unreachable, do not open SSH first — if the sibling client's own health check fails, reply unreachable; no queueing, no replay |
| The phone switched hosts or disconnected | The connection changed, voice must be restarted | First synchronously cancel the sibling client's network and invalidate its token, then tear down the SSH tunnel; the run returns `stale`, and in-flight tools no longer write to the host |
| Timeout, chunk verification failure, or unknown result | Result unknown, please check the phone | A mismatched length, hash, sequence number, or run replies `unknown` and records a tombstone; unknown is never treated as success, the phone does not re-execute, and side-effecting calls are not retried automatically |
| The same callID arrives again | Not presented to the user as a new execution | Within the same run, deduplicate by callID and mark `duplicate` without replaying. If a result exists, return that result header; if it is still running, do not start it again; an `unknown` that left a tombstone still returns `unknown` |
| `needs_input` or `not_confirmed` | Please handle it in OpenCode on the phone | No binding or an unreadable item replies `needs_input` without writing; if the post-submit read-back confirmation fails, reply `not_confirmed`; never fake an approval |
| The user ends voice while background work remains | Voice ended, background work is still running | Only the Watch connection is closed, the in-memory credentials are cleared, and that run is released; unacked commentary is dropped, no `stop_job` is sent, and no subsequent notification is promised |

## 5. Still To Be Verified

Continuous voice stability has not yet passed on-device acceptance. The background and startup behaviors below are also experimental and must not be written as guarantees; on failure, stop, and do not retry side-effecting calls. A successful build, unit test run, and install does not mean continuous conversation is stable.

Whether SSH and HTTP can complete within the time the system allows after a background wake (the app does not proactively drop SSH during an active Watch run, but this is only an experiment and not a guarantee of permanent iOS background keep-alive).

Whether the system kills the app when the watch first obtains the in-memory credentials for that run, activates audio, and only then POSTs the session path.

Whether the 20-second started deadline, counted from opening the socket, is enough on the watch's network path.

## Appendix A. Short Interface Copy

The short copy serves a small screen. Accepted is not completed, and an unknown result is not an automatic retry after a failure. No notification is promised after ending voice.

| Scenario | Chinese | English |
|---|---|---|
| Start | 开始语音 / 连接中… | Start Voice / Connecting… |
| Mute | 静音 / 取消静音。已静音，轻点恢复说话 | Mute / Unmute. Muted. Tap to speak again |
| Interrupt | 打断。已停下播报，请直接说 | Interrupt. Playback stopped. Go ahead |
| End voice | 结束语音。只断开手表语音 | End Voice. Disconnects Watch voice only |
| Phone unreachable | 手机不可达。无法连到配对 iPhone | iPhone Unreachable. Can't reach the paired iPhone |
| Credentials not ready | 请先在 iPhone 的 OpenCode 里准备语音凭证 | Open OpenCode on iPhone to prepare voice setup |
| Tool executing | 正在通过手机执行 | Running on iPhone |
| Result unknown | 结果未知。请到手机查看，不要再发一次同样的操作 | Result unknown. Check iPhone. Don't send the same action again |
| Work continues after ending | 语音已结束。后台工作仍在继续，可到手机查看 | Voice ended. Background work keeps running. Check iPhone |
| Needs phone confirmation | 请在手机处理。手表完不成这项确认 | Review on iPhone. Watch can't finish this confirmation |
| Connection changed | 手机上的主机已切换或断开，请重新开始语音 | Host changed on iPhone. Start voice again |

## Appendix B. Watch Front-End Instruction Draft

The following is the draft that is injected into the Watch Live session for the long term. It is not the phone's "Ambient Mode on iPhone" instruction. The read-only restrictions of the first-round on-device acceptance must not be written into the long-term instruction; during acceptance, add a separate temporary override, see Appendix C.

You are the voice entry point on the user's wrist, not the one on the phone. You talk with the watch's microphone and speaker. OpenCode tools are executed via the paired iPhone, and the host and directory are bound by the phone when this run starts. Do not fill host, account, or secret values into the parameters.

Keep answers short, suitable for being heard with the wrist raised. Do not read out session IDs, directories, file paths, host addresses, accounts, or any credentials. Refer to the work by its subject and its most recent progress.

Ending watch voice only closes this voice session and does not stop OpenCode work that has already been accepted. Call `stop_job` only when the user explicitly asks to stop a specific task. Do not promise a push notification after ending, or that results will later be delivered to the watch.

Only these eight tools may be used; do not invent names: `query_jobs`, `get_session_messages`, `start_job`, `continue_job`, `stop_job`, `answer_pending`, `archive_job`, `unarchive_job`. To look up in-flight work you must pass `archivedOnly=false` to `query_jobs`; the default true only searches archived items. The only models for new work are `ollama-cloud/deepseek-v4.1-flash` and `openai/gpt-6.1-sol`. `continue_job` cannot change the model. HTTP 200/202/204 only means the call was accepted; without completion evidence, you cannot say it is complete.

An error, a timeout, an unreachable phone, an unavailable host, an invalidated connection, and an unknown result are not success. Report the status truthfully; do not automatically retry or replay side-effecting calls.

`answer_pending` is not full approval. It only reads and replies to pending items according to the session binding of the current Watch run, and reads once more after submitting to confirm; permissions support only `once` or `reject`. When it returns `needs_input` or `not_confirmed`, or when the user needs to check the full command or handle another session, tell the user to open OpenCode on the phone. Do not describe it as already approved.

## Appendix C. Temporary Override For First-Round Acceptance Only

During acceptance, only do small-scale reads. `query_jobs` must use `archivedOnly=false` with a small count. `get_session_messages` only reads existing sessions. Do not proactively call `start_job`, `continue_job`, `stop_job`, `archive_job`, `unarchive_job`, or `answer_pending`. This override is removed after acceptance finishes and does not enter the long-term front-end instruction.
