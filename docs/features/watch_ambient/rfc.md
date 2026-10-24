# Watch Ambient Implementation Boundaries (Experimental)

## Implementation Updates And Known Limitations

Watch Ambient is integrated as Experimental. On-device voice capture and playback, tool result return, and one initial connection made while the phone was in the background have been proven to work; but with the phone in the foreground at close range or in the background, the connection can still drop during an answer or in the second turn. The watch-side 5-second deadline is triggered when an audio frame send does not complete, an explicit reconnect recovers, and it can drop again afterwards. The underlying cause is unconfirmed and cannot yet be attributed to WatchConnectivity, a server-side active close, or an AVAudioEngine deadlock. Continuous background operation, lock screen, and SSH wake-up recovery still need to be verified.

Capture shutdown shares a 15-second monotonic clock budget. Hardware cleanup retains ownership until it actually completes, may not overlap with a new capture, and a deferred cleanup can restore idle. The Watch audio send has a 5-second deadline, with no automatic reconnect and no replay of write tools. An old phone lease is replaced only for the exact owner just observed, with one retry on explicit start; an old end/poll does not clear a newer run, and a non-WC start failure no longer misreports the phone as unreachable. After a debug probe fails, the busy/run state is cleaned up, and the Watch reuses the iOS icon.

The native diagnostics record socket state, numeric error codes and close codes, sent/received byte counts, scenes, and frame counts; they never write audio, body text, URLs, credentials, or error descriptions to disk. Xcode can list the diagnostic files on the watch, but the current development transfer channel disconnects during export, so the latest native connection evidence has not been read back yet; this issue must not be used as the attribution basis for a voice failure.

The Watch connects to the existing Live gateway on its own to send and receive real-time voice, all OpenCode tool calls are handed to the paired iPhone for execution, and ending the voice session on the watch does not stop OpenCode work that is still running in the background.

This document describes the module split, runtime ownership, and failure boundaries when adding the Watch app. The Watch bridge owns a second `APIClient` instance exclusively and reuses the existing eight-tool definitions. No new approval state machine, custom encryption protocol, offline queue, or audio preemption state machine is added. Steps that lack on-device evidence are listed as experimental under "Still To Be Verified"; no optimistic assumptions are made in the code and nothing is written as a guarantee.

## 1. Shared Core, No Regression On iPhone And visionOS

The project has added an `OpenCodeWatch` target with a watchOS 11 deployment target, whose sources live in the synced directory `OpenCodeWatch`, at the same level as `OpenCodeClient`. Watch embedding only takes effect for iOS and does not embed for visionOS, and the existing list of supported platforms is unchanged. The SSH tunnel code does not participate in compilation on visionOS. The audio reuses the capture and playback core of `CarLiveIOSAudioEngine`; the watchOS branch activates audio on its own, and iOS-only APIs sit behind platform guards.

Shared files are explicitly selected. The Live core only includes Foundation / Observation, and pulls in neither UIKit nor the SSH library. The audio file is selected separately and placed behind platform guards; visionOS does not compile this audio implementation. `AppState`, SSH, and the entire synced group are not dragged into the Watch. The shared surface holds only these definitions:

1. Wire protocol constants: the session creation path `/v1/audio/live/sessions`, the voice model `gpt-live-1`, hosted inference `gpt-6-luna`, the default voice `marin`, a 20-second started wait, a 15-second close grace period, a 64 KiB UTF-8 tool output limit, a 2000-byte commentary limit, and that ending voice does not abort OpenCode.
2. PCM constants: 24 kHz, mono, interleaved Int16. A single audio append has an even length, from 2 to 480000 bytes.
3. The eight tool names, plus the two work models: the default `ollama-cloud/deepseek-v4.1-flash`, and `openai/gpt-6.1-sol` for complex new work.
4. The Watch run's own callID ledger, whose states are an existing result, still executing, and an unknown tombstone. It does not borrow the phone controller's ledger, which only has accepted, duplicate, and rejected.

The existing order of `CarLiveController.start` on the iPhone stays untouched: request the recording permission, call `transport.open`, and only call `beginAudio` once the session is started. `transport.open` itself first POSTs the session path to exchange the ticket and then connects to the returned WebSocket; it does not attach the WebSocket directly to the session path. visionOS does not link this iOS audio engine. This design does not change its existing behavior and does not push the Watch's startup order back into the iPhone or visionOS.

The Watch follows this order on its own:

1. Each time voice starts, the watch asks the phone for the Builder token and portal address via an interactive reply and keeps them in memory only. Without a reply it stops: no recording, no POST, and a prompt to prepare on the phone first.
2. After receiving the in-memory credentials for that run, it requests the recording permission and activates the Watch's own audio, preparing 24 kHz mono Int16 capture and playback. The watch must not call `setPreferredSampleRate` or `setPreferredIOBufferDuration`.
3. Only after audio activation succeeds does it POST the session path and open the returned socket. The 20-second started deadline is counted from opening the socket and excludes the preceding audio activation.
4. The credentials are limited to that launch call and are not stored in the Watch model or any other long-term state; if audio activation fails, the run ends without POSTing and without opening a socket. No credentials are kept for reuse in the next round after the launch call ends. Whether the audio survives and cleans up after the watch enters the background still awaits on-device acceptance.

The Watch only sends the already-allowed events on the wire: audio append, close, mute, unmute, commentary, thinking, function output, and continue. It does not send `session.start` or `session.update`.

## 2. Audio Ownership And Independent Operation

The Watch's microphone, speaker, and Live socket belong to the Watch. The iPhone Ambient microphone, speaker, and `CarLiveController` belong to the iPhone. The Watch does not start, stop, or mute the phone controller, and does not route playback to the phone. Both can exist at the same time; there is no preemption state machine.

The interface stays minimal. One large microphone button that becomes an interrupt button in the same place while speaking. Below it, the most recent few lines of transcript. Mute and End sit in a corner or along the bottom edge. A single status line covering connecting, listening, executing on the phone, unreachable, result unknown, and voice ended. No second screen and no preemption state machine.

Ending Watch voice only closes the Watch's socket, clears the in-memory credentials for that run, and ends the corresponding short-lived run on the phone. The close grace period is still 15 seconds. It does not call `stop_job` and does not abort OpenCode work that has already been accepted.

Today the phone has only one `CarLiveController`, one `CarLiveLease`, and one `CarLiveReplyBridge`. The live transport gate of `APIClient` also has only one active token: `arm` replaces the active one, and `allows` only recognizes the current active one. If the Watch calls the existing `armLiveTransport()` or `startCarLive()`, it displaces the lease the phone is using.

Therefore the Watch bridge owns a second `APIClient` and its own `URLSession`, uses the base URL the phone is already configured with, and gets its own reply bridge. SSH remains the existing single local listener, and both clients go through it. No second tunnel is built, and no private key or host profile is handed to the watch. Do not add a second slot to the existing `CarLiveTransportGate`; call `armLiveTransport()` only on the sibling client, and do not call the phone controller's `startCarLive()`.

## 3. Handshake, Snapshot, And Invalidation

When the Watch is ready to start voice, it generates a UUID as the owner of that run and asks the phone to establish a short-lived run. The phone verifies this identifier and snapshots the host ID, host generation, context key, directory, and current agent at that moment. This snapshot is bound to the run. Host, account, or credential values are not passed in tool parameters.

The allow conditions for a Watch run look only at: the run has not ended, the host ID and generation still match, and the workspace context still matches. They do not read the phone Live's `carLiveEpoch` and do not read `isConnected`. Starting or ending Ambient on the phone itself bumps that epoch; if the Watch became invalid along with it, it would be bound to the phone Live lifecycle again.

The phone's initialization reconnect and health check wait at most 20 seconds; on timeout the run is invalidated and unreachable is returned, without dropping the existing shared SSH. The watch's initialization reply waits 30 seconds, and ordinary messages wait 8 seconds. On first launch it waits up to 5 seconds to activate WatchConnectivity and then tries an interactive message, without using a transient `isReachable` value to block the system from waking the phone.

When explicitly starting new voice, if the phone replies busy and includes a valid `activeRun`, the Watch retries begin exactly once, carrying `replacing=activeRun`. The phone ends the old lease only while the replacement value still equals the current owner; a late replacement or end does not affect the new lease. This retry exists only to establish the voice run and never resends a tool call.

When the host is switched, first synchronously cancel the sibling client's network and invalidate its token, then tear down the SSH tunnel; do not wait for the shared client's `configure` to clean up as a side effect. A Watch run becomes invalid as soon as it sees that the generation or host ID no longer matches. When the Watch ends actively, it likewise ends that run and calls `invalidate()` on the independent reply bridge. Late tool calls on the old run return `stale` and no longer read from or write to the host.

## 4. Tools, Deduplication, And Unknown Results

The eight tool names and parameter contracts stay unchanged. `continue_job` cannot change the model. For `start_job` and `continue_job`, HTTP 200/202/204 only means the call was accepted. `query_jobs` defaults to `archivedOnly=true`; looking up in-flight work requires an explicit `false`.

WatchConnectivity may deliver duplicates. Within the same run, deduplicate by callID; the phone bridge keeps its own callID ledger:

- The first time a callID is seen, register it and execute it.
- When the same callID is seen again in the same run, mark it `duplicate` and do not execute it again. If a result already exists, return that result header without re-executing. If it is still executing, do not start it a second time. An `unknown` leaves a tombstone, so the same callID arriving again still returns `unknown` and is not replayed.
- An error, a timeout, the phone being unable to reach the host, or an unknown result are not success, and are not retried automatically on either the watch or the phone side.

`answer_pending` uses the binding of that Watch run, handles items through the token-carrying read and reply interfaces, and reads once more after submitting to confirm. It does not use the revision of the phone's pending list and does not call the phone Ambient approval function. It does not search other sessions; when there is no binding or the item cannot be read, it returns `needs_input` without writing. Permissions accept only `once` or `reject`. A failed confirmation is `not_confirmed`. Both results send the user to OpenCode on the phone. This tool is not written up as full approval.

## 5. Reply Bridge And Background Wake-Up

The independent reply bridge serves only the run that is still allowed. Commentary and the final result are preferably pulled by the watch about every 2 seconds, which drives the independent reply bridge on the phone to poll with the sibling client, without connecting to or reading the global SSE. The commentary body is still subject to the existing 2000-byte limit. The watch feeds it into its own socket, and only after its own gateway has emitted `commentaryAppended` with a matching identifier does it ack to the phone. A successful WatchConnectivity send is not an ack. `invalidate()` is called when the run ends or the host is switched; when voice ends, unacked records are dropped and not re-sent, and there is no promise to push asynchronous results back to the watch later.

Commentary is offered in enqueue order. If an entry is still unconfirmed 8 seconds after it was first offered, that entry is dropped and recorded as an unconfirmed failure, releasing the following results; it is not recorded as injected and is not announced again. If the gateway has confirmed but the phone's ack is lost, the watch retries the ack in a later poll.

During an active Watch run, the app does not proactively drop SSH. This is not permanent iOS background keep-alive; it is only an experiment and must not be written as a guarantee. Each WatchConnectivity message runs its own bounded background task. When the phone is unreachable, do not open SSH first. SSH is reconnected only when it is not currently connected; when it is already connected, calling connect again is forbidden. Use the sibling client's own health rather than `isConnected`. If health fails, reply `unreachable` (unreachable), without queueing and without replaying.

## 6. How 64 KiB Of Output Crosses WatchConnectivity

Existing tool output is already limited to 64 KiB UTF-8, and function output over the limit is not encoded onto the wire. List-type results are shrunk within this limit and marked partial. The commentary injection limit is still 2000 bytes, which is a separate limit.

The common fields of a WatchConnectivity request are `v`, `op`, `run`, and `call`, with `seq`, `name`, `arguments`, or `sha256` added per operation. `v` is 1. The operations include `begin`, `end`, `tool`, `result`, `pull`, `ack`, `commentary`, and `commentaryAck`. The interactive reply of `begin` provides `portal` and `token` in memory only. A tool first returns `pending`, and `result` then returns the status, `bytes`, `sha256`, and `chunks`, without the body. Only `ready` triggers a `pull` per `seq`; the `data` in the reply is `Data` of 8192 bytes except for the last chunk, and it carries `run`, `call`, and `seq` back. `ack` is sent only after the watch verifies the length and sha256. A repeated call reuses the existing state; `unknown`, `unreachable`, `stale_context`, and conflicts must not trigger a tool replay. `needs_input` and `not_confirmed` are business results inside the tool output body and are not conflated with transport-level errors.

The phone bridge keeps using this existing limit and does not silently truncate a second time, so that the partial marker is not cut off. A tool call is accepted first, and the reply does not carry the output body. The body is pulled in fixed 8192-byte `Data` chunks, with the total length and sha256. The watch verifies the reassembled body before feeding it into its own Live socket. A mismatched length, hash, sequence number, or run replies `unknown`, and the phone does not re-execute. No file transfer is used, and the body is never placed into an asynchronous queue that could still deliver after the run ends.

## 7. In-Memory Credential Acquisition And Cleanup

The Watch needs only two things to open Live: the Builder token, and the Live portal base URL. The phone does not sync over the SSH private key, host password, basic auth credentials, or the whole host profile.

Each time voice starts, the watch asks the phone for the Builder token and portal address via an interactive reply. The watch uses them only in that launch call, never writing them to the watch Keychain, never putting them in UserDefaults, never in `applicationContext`, never in any other transport that persists to disk, and never in logs. They are not reused across rounds. Without a reply there is no recording and no POST. No fallback token is embedded.

## 8. Still To Be Verified

The following three items are experimental and must not be written as guarantees; on failure, stop, and do not retry side-effecting calls:

1. Whether SSH and HTTP can complete within the time the system allows after a background wake (not proactively dropping SSH during an active Watch run is experimental and is not a guarantee of background survival).
2. Whether activating audio before POSTing the session path gets the app killed by the system.
3. Whether the 20-second started deadline is enough on the watch's network.

The copy and the front-end instruction draft are in the appendices of `prd.md` in the same directory. The read-only restrictions of Appendix C are only for the first round of acceptance and are not written into the long-term front-end instruction.
