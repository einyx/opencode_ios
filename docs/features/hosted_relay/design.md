# Hosted Relay — Design

Status: proposal. No implementation. Companion to `../push_notifications/research.md`
(push transport is assumed to be carried by the relay, per that document's
"Notification Bridge" recommendation).

This document answers one question: *what would a hosted relay for OpenCode
look like such that (a) it is worth selling, (b) it cannot read the user's
traffic, and (c) the app keeps working with no subscription at all.*

Everything below is derived from the current iOS client source unless marked
`unverified — needs check`.

---

## 1. Decision summary

| Question | Answer |
|---|---|
| What is sold | **Reachability + push delivery.** A flat subscription for a relay that lets a phone reach a home server and wakes the phone when the agent needs a human. |
| What is not sold | Model credits, tokens, provider keys, hosted agents, hosted execution. The user's provider credentials never leave the user's server. |
| Relay topology | The **connector** on the user's server dials *out* to the relay (NAT-friendly). The relay is an authenticated **message bus**, not a reverse proxy. |
| Trust model | End-to-end encrypted between the phone and the host. The relay routes sealed envelopes and never terminates the seal. |
| Encryption anchor | The **QR pairing exchange** (`opencode pair`), extended to carry the host's X25519 public key. The phone pins it at pairing time. |
| Payment route | **Unresolved.** App Store IAP vs external purchase. This blocks the entire revenue design. See OQ-1. |

### 1.1 Product invariants (non-negotiable)

1. **The relay cannot read traffic or prompts.** Enforced by E2E sealing, not by policy.
2. **The app works fully self-hosted with no subscription.** A relay host is *additive*; `.direct` and `.sshTunnel` hosts keep every current feature. A relay outage must never reduce the app's capability against a self-hosted server.
3. **The relay is not a reseller of AI model credits.** No per-token metering, no bundled inference, no balance/stored value, no handling of the user's money for third parties (which would also drag in KYC/AML and money-transmission obligations).
4. **The relay holds no model credentials.** The server's Basic auth / pairing token travels *inside* the sealed envelope, never as an HTTP header to the relay.

### 1.2 The constraint nobody planned for

`docs/appstore/app-privacy.md` currently answers the entire App Store Connect
App Privacy questionnaire with **"Data Not Collected"**, on this stated basis:

> "The key point is that the app is a *client*. Everything it sends goes to the
> OpenCode server the user configured; the developer of the app operates no
> service and receives none of it."

A hosted relay falsifies every sentence of that paragraph. The relay is a
developer-operated service that holds accounts, IP addresses, device
identifiers, APNs tokens, host↔device routing tables, and timestamps. It also
creates accounts, which triggers **Guideline 5.1.1(v) in-app account deletion**.

Consequences that must be planned for, not discovered later:

- The App Privacy questionnaire flips to "Yes" for identifiers, purchases, usage
  data and diagnostics; user content stays "not collected" *only* because of the
  E2E seal (this becomes the app's strongest privacy claim — and its strongest
  marketing message).
- `docs/appstore/privacy-policy.md` and a new Terms of Service are required.
- If the relay is EU-hosted, the relay is a processor of personal data (IPs,
  timestamps, opaque identifiers). Metadata is personal data under GDPR.
- Account deletion must delete: account, relay credential, device records
  (including APNs tokens), host enrollments, queued envelopes, and audit rows.
- `docs/README.md` needs a `hosted_relay/` row; `docs/appstore/app-privacy.md`
  needs a rewrite.

This is a product-shape decision, not a compliance chore. Decide it before
writing code.

---

## 2. Scope split

### 2.1 What the relay does

| Capability | Detail | Content visible to relay? |
|---|---|---|
| **Reachability** | Accept a device connection and a connector connection; route sealed envelopes between them so a phone on cellular can reach a server behind NAT without the user running a tunnel. | No |
| **Push transport** | Hold the APNs device token, hold the APNs provider key, forward a push when the connector reports an attention event, delete the token on APNs `410`. | No (push payload is a generic string + an opaque sealed blob) |
| **Session fan-out** | Deliver one connector's event stream to N enrolled devices for the same host, each sealed to that device's key. | No |
| **Short-lived presence** (optional) | "This host was reachable 40 s ago." TTL-bounded, coarse, not a heartbeat stream. | Coarse: reachability only, no identity beyond `hostID` |
| **Routing & bookkeeping** | Map `deviceID ↔ hostID ↔ relay credential`, enforce per-account quotas, rate limits, revocation. | Metadata only |
| **Bounded queueing** | Hold sealed envelopes for an offline device for a TTL so a phone that was asleep still gets the attention event. | No — the queue stores ciphertext |

### 2.2 What the relay must never do

| Forbidden | Why | Enforced by |
|---|---|---|
| Read prompts, replies, file contents, diffs, tool output | Core product promise | E2E seal; the relay holds no key |
| Hold the host's Basic auth / pairing token | Would let the operator impersonate the user to their own server | The credential is inside the sealed envelope; the relay never parses HTTP headers of the inner request |
| Hold the host's private key or the device's private key | Same | Key material never leaves the endpoint |
| Hold model provider credentials | They live on the user's server and never enter the relay | Not in the path |
| Persist message content | Even encrypted-at-rest retention is a liability the operator would be asked to hand over | Relay stores opaque blobs with a TTL and a size cap; a legal/ops policy forbids attempting decryption (it cannot) |
| Log inner request paths, query strings, or bodies | These leak content | The relay's logs record `hostID`, `deviceID`, byte counts, timings, and error codes only |
| Terminate TLS to the host on the user's behalf | Equivalent to holding credentials | The connector terminates TLS locally (`https://127.0.0.1:4096`) |
| Meter model usage | Product invariant 3 | The relay meters bytes and accounts, not tokens |

### 2.3 Explicit non-goals for the relay

- Not a VPN, not a general-purpose proxy. It routes between exactly one enrolled
  connector and its enrolled devices. (App Store Guideline 2.5.4 concerns VPN
  APIs — this design uses plain TLS, not Network Extension — but a reviewer may
  still read it as tunneling. **unverified — needs check with Apple.**)
- Not a store of user data. No session history, no message history, no file
  index. If the relay can answer "what did the agent say?", it is a data
  product and the privacy posture collapses.

---

## 3. End-to-end encryption

### 3.1 The anchor: the QR pairing exchange

The client already has a device-enrollment primitive: `opencode pair` prints a
QR payload `{"code":…,"urls":[…]}` that the app scans (`QRScannerView` →
`PairingLink.parse` → `PairingClient.redeem`). Verified properties of that
exchange, from `PairingClient.swift` and `PairingLink.swift`:

- The code is **single-use** and **expires in five minutes**.
- The code is `randomBytes(16).toString("base64url")` — 22 base64url characters,
  i.e. 128 bits of entropy.
- Redemption is `GET /auth/connect/<code>`, unauthenticated.
- The returned token "is accepted anywhere the server password is", so it
  becomes the host's Basic-auth password with username `opencode`.
- `PairingLink.parse` accepts only an exact `/auth/connect/<code>` path, so a
  mistyped server address is never redeemed as a code.

**The relay anchor is that exchange, extended.** The pairing payload gains the
host's long-term public key:

```json
{
  "v": 2,
  "code": "<existing 22-char base64url code>",
  "urls": ["http://192.168.1.10:4096"],
  "hostKey": {
    "alg": "x25519",
    "pk": "<base64url raw 32-byte public key>",
    "fp": "SHA256:<base64url>"
  },
  "relay": { "url": "https://relay.example", "enroll": "<base64url enrollment blob>" }
}
```

The phone **pins `hostKey.pk` at pairing time**. Because the QR is a
human-mediated out-of-band channel (the user physically points a camera at the
server's terminal), this is a genuine trust anchor: the relay cannot substitute
its own key, because it never appears in the pairing exchange.

The relay is given an `enroll` blob, not the host's private key.

### 3.2 Key hierarchy

| Key | Where it lives | Lifetime | Purpose |
|---|---|---|---|
| `K_host_static` (X25519 private) | The connector, on the user's server | Long-term | Identity of the host. Proves possession to the phone. |
| `K_host_pub` (X25519 public) | Pinned on the phone at pairing; registered with the relay | Long-term | Anchor for the pairing fingerprint UI. |
| `K_device_static` (X25519 private) | Phone Keychain | Long-term | Identity of the device. One per phone per host. |
| `K_pair` | Derived on both ends | Long-term | `HKDF-SHA256(X25519(K_device_static, K_host_static))`. Seals envelopes that must **survive queueing at the relay** (push payloads, offline inbound). |
| `K_chan` | Derived on both ends per session | Per connection | `HKDF-SHA256(X25519(K_device_ephemeral, K_host_static))` — Noise IK-style. Seals the **live** request/response and event channel. Forward secrecy per session. |
| `K_relay_cred` | Phone Keychain; relay DB | Long-term, revocable | Authenticates the *device to the relay*. Orthogonal to the host credential. |
| `K_conn_cred` | Connector; relay DB | Long-term, revocable | Authenticates the *connector to the relay*. Derived from `K_host_static` so it is useless without the private key. |

The split between `K_relay_cred`/`K_conn_cred` and the seal keys is
non-negotiable: if the relay credential were the server's Basic auth, the relay
would hold the server's password (invariant 2.2). If the relay credential were
the seal key, the relay would hold the content key. They must be independent
secrets with independent rotation.

### 3.3 What the relay can see

| Visible | Not visible |
|---|---|
| `hostID`, `deviceID`, `accountID` (opaque, random) | Prompts, replies, tool output, diffs, file bytes |
| Both endpoints' IP addresses and connection timestamps | HTTP method, path, query, headers, body of the inner request |
| Byte counts per envelope and per connection | The event type (sealed) |
| Envelope arrival/departure timing | The session id (sealed) |
| Which device is subscribed to which host | The user's prompts, filenames, model names, provider names |
| Relay-side error codes (envelope too large, seq gap, unknown route) | The plaintext of anything inside a sealed blob |

**Metadata that is not sealed and therefore is seen:** the `hostID`/`deviceID`
pairing, and the fact that *something* was transferred at time *t*. This is the
residual that cannot be removed: a relay that routes bytes knows who talked to
whom and when.

**One honest caveat.** If the connector dials out to the relay (the NAT-friendly
topology), the relay learns the user's **home egress IP**, which is a far
stronger identifier than the phone's IP and often identifies a household. Two
mitigations, both imperfect: (a) the connector can be pointed at the relay
through a user-chosen egress (Tailscale exit node, WireGuard) so the relay sees
the VPN exit IP instead; (b) the relay can retain the connector's IP for hours
rather than days, and never log it alongside a `hostID` in long-lived analytics.
This is a real leak and belongs in the privacy policy, not in a footnote.

### 3.4 Sealing

- **Algorithm:** XChaCha20-Poly1305 or ChaCha20-Poly1305 (RFC 7539) with
  `CryptoKit.ChaChaPoly`. AAD = `hostID | deviceID | direction | seq | class`,
  binding an envelope to its route and position so a relay cannot repoint it.
- **Nonce:** 4-byte random per-envelope prefix + 8-byte monotonic counter,
  concatenated to a 12-byte nonce. The prefix is generated by the *sender* and
  travels in clear; the counter is implied by `seq`. This avoids the
  "random 96-bit nonce" birthday problem over a long-lived key pair.
- **Key derivation:** HKDF-SHA256 (RFC 5869). CryptoKit provides
  `SharedSecret.hkdfDerivedSymmetricKey(using:salt:sharedInfo:outputByteCount:)`.
  Whether a standalone HKDF over a static key (as opposed to a shared secret)
  is directly expressible with the same helper is **unverified — needs check**;
  if not, a short HMAC-SHA256-based HKDF is ~20 lines.
- **Frame format:** each envelope carries `seq` (per-direction monotonic
  counter), `class` (`request` | `response` | `event` | `push`), and the
  ciphertext. `seq` gives replay detection and gap detection for free.

### 3.5 Replay, reorder, and drop

The relay is an untrusted transport and can be hostile in ways TLS does not
prevent: it can **drop** envelopes, **replay** old ones, and **reorder** them.
It cannot forge content (it lacks the key).

| Attack | Mitigation |
|---|---|
| Replay of an old envelope | Monotonic `seq` per direction per route. The receiver rejects `seq <= lastSeen` and rejects a gap beyond a window. |
| Reorder | Same: out-of-order frames within the window are buffered and re-ordered; beyond the window they are dropped and the peer is asked to resync. |
| Drop | Detected as a `seq` gap. The receiver issues a `resync(from:)` to the peer (over the same sealed channel); the peer replays from its own buffer. The peer is the host, which is the authoritative source of truth, so a dropped event is recovered by re-reading the host's REST state (the app already reconciles permissions/questions after a reconnect). |
| Forge | Impossible without `K_pair`/`K_chan`. |
| Roll back to an old host key | The phone pins `K_host_pub`; a changed key requires an explicit re-pair, and the UI shows the fingerprint change (see §3.7). |

### 3.6 Key rotation

| Rotate | Mechanism | Blast radius |
|---|---|---|
| **Device static key** | Re-enroll **over the existing sealed channel**: the device proves possession of the old private key; the connector adds the new public key and drops the old. No QR needed. | That device only. Old key stops working immediately. |
| **Host static key** | New QR pairing per device. | **Every** enrolled device must re-pair. Therefore the host key should rotate rarely, and the design prefers ephemeral per-connection keys so that a long-lived static key is the only thing at risk. |
| **Session channel key** | Automatic — a new `K_chan` per connection, derived from a fresh device ephemeral key. | None. Forward secrecy means a captured session cannot be decrypted later. |
| **Relay credential** | `POST /v1/devices/rotate-credential`, old credential valid for a 5-minute grace window. | That device. |
| **Revocation** | The connector drops the device public key; the relay deletes the device's route and queued envelopes. The device is refused on the next handshake. | That device. |

### 3.7 The fingerprint the user can check

The codebase already has the right precedent: `SSHKnownHostStore` persists a
trusted OpenSSH host key per `host:port` and surfaces a
`SHA256:<base64>` fingerprint with an explicit "Trust New SSH Host Key?" prompt
(`SSHHostKeyMismatch`, `settingsTrustHostKeyTitle`). The relay host key should
reuse that exact pattern:

- The host's key fingerprint is displayed at pairing time on the server console
  *and* in the app after scanning.
- The app stores the pinned fingerprint alongside the host profile.
- A later mismatch (the host key changed) raises the same "Trust and
  Reconnect" style prompt, never a silent re-pin.

This gives the user a real MITM check without inventing a new concept.

### 3.8 If the user loses the phone

| Asset | Where | Consequence |
|---|---|---|
| `K_device_static` (private) | Phone Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, per `KeychainHelper`) | Gone. The phone cannot re-derive `K_pair`. |
| `K_relay_cred` | Phone Keychain | Gone. The relay must drop the device's route. |
| The host's enrollment of the device | Connector + relay | **Still valid.** The old device's public key remains registered until revoked. |
| The host's data | The user's own server | **Untouched.** This is the point of the whole design: losing the phone loses no conversation, no code, no model credits. |
| Queued inbound envelopes for the dead device | Relay | Dropped when the device is revoked or when the TTL expires. |
| The APNs token | Relay | APNs returns `410 Unregistered` once the token is dead; the relay deletes it. The relay also reaps device records not seen for N days. |

Recovery: the user runs `opencode pair` again (or an in-app "re-pair" flow) and
scans a fresh QR. The connector enrolls the new device key and **revokes the
old one** — revocation must be automatic on re-pair for a lost device, or the
old phone stays a live credential.

**What the user must do that the design cannot do for them:** revoke the lost
phone from the *host*, because the host is the authority. The app should make
this a one-tap action ("Revoke this device" in Host Profiles), and the connector
should expose the same list to the user on the server side.

### 3.9 Honest limits of this design

- An **unlocked, stolen phone** is fully compromised for that host until the
  device is revoked. The phone holds the host's Basic auth in the Keychain
  today (`hostProfile.<uuid>.password`), so a stolen phone is a stolen host
  credential, with or without a relay. The relay's contribution is that
  revocation is *remote and fast*, not that theft is harmless.
- A **compromised host** can decrypt everything for that host. The host is the
  trust anchor; the relay cannot defend against it.
- A **malicious app on the device** can hijack the `opencode://` custom URL
  scheme used for notification-tap routing (the push research already flags
  this). Universal Links (Associated Domains) is the fix, and it is deferred.
- **Traffic analysis** is not prevented. The relay learns volume and timing.
- **The relay can deny service** at will. It cannot forge content.

---

## 4. Protocol

### 4.1 The shape of the relay

The relay is **not** a reverse proxy. It is an authenticated, revocable message
bus with two kinds of participant per host:

```
┌──────────────┐   sealed envelopes   ┌───────────────────┐   sealed envelopes   ┌──────────────────────┐
│  iOS device  │◄────────────────────►│      RELAY        │◄────────────────────►│  Connector          │
│  (phone)     │   device ↔ relay     │                   │   relay ↔ connector  │  (on the user's     │
│              │   (TLS, relay cred)  │  sees: ids,       │   (TLS, conn cred)  │   server)            │
└──────────────┘                      │  sizes, timings  │                      │  ↕ plaintext        │
                                      └───────────────────┘                      │  127.0.0.1:4096     │
                                                                               └──────────────────────┘
```

The connector dials **out** to the relay, so the relay needs no inbound port on
the user's network and no tunnel on the user's machine. This is the only
topology that satisfies "the user runs nothing extra at home" — and it matches
the push research's recommendation of an outbound-only Plugin → central
Gateway.

Consequence: **the relay never terminates the inner HTTP.** It forwards opaque
blobs. Every inner request/response is produced by the connector against the
local OpenCode server, and sealed before it leaves the machine.

### 4.2 Connection lifecycle

```
DEVICE                                          RELAY                                CONNECTOR
  │  POST /v1/devices/register                     │                                    │
  │  {devicePublicKey, apnsToken, appVersion}      │                                    │
  │──────────────────────────────────────────────► │  store device, issue relayCredential │
  │◄────────────────────────────────────────────── │                                    │
  │  {deviceID, relayCredential, hostID, K_pair}   │                                    │
  │                                               │                                    │
  │  GET /v1/stream?hostID&role=device  (WS)       │                                    │
  │──────────────────────────────────────────────► │◄──────── POST /v1/hosts/enroll ──────┤
  │                                               │    {hostPublicKey, connCredential}   │
  │                                               │  host route created                 │
  │                                               │                                    │
  │  ◄══ sealed "hello" {deviceNonce, ...} ══════►│  ══ sealed "hello" ════════════════►│
  │                                               │                                    │
  │  X25519(K_device_ephemeral, K_host_pub)       │                                    │
  │  → K_chan, both sides                          │                                    │
  │                                               │                                    │
  │  sealed request  {id, method, path, body} ───►│  forward blob ─────────────────────►│
  │                                               │                     decrypt, perform │
  │                                               │                     local HTTP call │
  │  ◄── sealed response {id, status, body} ──────│◄──── sealed response ────────────────┤
```

**Handshake details.** After the two WebSockets are up, the device sends a
sealed `hello` containing a device nonce; the connector answers with a sealed
`hello` containing the host nonce. Both sides derive

```
K_chan = HKDF-SHA256( X25519(K_device_ephemeral, K_host_pub),
                      salt = hostNonce || deviceNonce,
                      info = "opencode-relay/v1/chan" )
```

The relay is a passive observer of this exchange: it sees two opaque blobs of
similar size and nothing else. The relay cannot MITM it because it holds neither
private key.

**Keepalive.** Both peers ping every 30 s; the peer answers `pong`. The relay
closes a connection after 90 s of silence. On reconnect the client sends
`resumeFrom(seq)` so no envelope is lost, and the peer replays from its buffer.

**Reconnect backoff (client):** 1 s, 2 s, 4 s, 8 s, 15 s, 30 s cap, ±20 % jitter.
A 401/403 on the relay credential is terminal (do not retry; force re-enroll).

### 4.3 Relay HTTP API (public surface)

All endpoints are HTTPS + JSON. All authenticated endpoints carry
`Authorization: Bearer <relayCredential>` (device) or
`Authorization: Bearer <connCredential>` (connector). These are *relay*
credentials and are never the host's Basic auth.

| Method | Path | Role | Request | Response |
|---|---|---|---|---|
| `POST` | `/v1/devices/register` | device | `{v, devicePublicKey, apnsToken?, appVersion, platform}` | `{v, deviceID, relayCredential, enrolledHosts:[hostID]}` |
| `POST` | `/v1/devices/rotate-credential` | device | `{v}` | `{v, relayCredential}` (old valid 5 min) |
| `DELETE` | `/v1/devices/{deviceID}` | device | — | `204`. Also invoked on account deletion. |
| `POST` | `/v1/hosts/enroll` | connector | `{v, hostPublicKey, hostDisplayName?}` | `{v, hostID}` |
| `POST` | `/v1/hosts/{hostID}/revoke-device` | connector | `{v, devicePublicKey}` | `204` — revokes a device |
| `POST` | `/v1/envelopes` | both | `{v, hostID, to:"device"\|"host", seq, class, blob}` | `202` |
| `GET` | `/v1/stream?hostID=&role=` | both | WebSocket upgrade | frames of `{seq, class, blob}` |
| `POST` | `/v1/push/register` | device | `{v, hostID, apnsToken, environment}` | `204` |
| `DELETE` | `/v1/push/{token}` | device | — | `204` |
| `GET` | `/v1/account` | device | — | `{v, plan, quota, enrolledHosts, relayRegion}` |

Note `POST /v1/envelopes` (HTTP) and `GET /v1/stream` (WebSocket) are
interchangeable: the HTTP form is a fallback when WebSockets are blocked (some
carriers, some enterprise Wi-Fi). Both carry the same envelope body.

### 4.4 Inner framing (inside the sealed envelope)

Device → connector:

```json
{
  "v": 1,
  "kind": "request",
  "id": "<uuid v4>",
  "method": "POST",
  "path": "/api/session/ses_abc/prompt",
  "query": "",
  "headers": { "content-type": "application/json" },
  "body": "<base64url>"
}
```

Connector → device:

```json
{ "v": 1, "kind": "response", "id": "<same uuid>", "status": 200, "headers": {...}, "body": "<base64url>" }
{ "v": 1, "kind": "event",   "id": "<same uuid>", "stream": "sse", "chunk": "<base64url>" }
{ "v": 1, "kind": "error",   "id": "<same uuid>", "code": "host_unreachable", "message": "..." }
```

The connector translates the inner request into a local HTTP call against its
own OpenCode server and translates the response back. It performs the
`Authorization: Basic opencode:<token>` header **locally**, inside the sealed
envelope. The relay never sees it.

**This is deliberately a byte-level proxy of the existing OpenCode HTTP API, not
a new API surface.** That is what makes the client change small (see §8.3).

### 4.5 Enrollment and revocation

**Enroll a host.** The connector reads its own host key and enrollment secret
from the user's server config and calls `POST /v1/hosts/enroll`. The relay
records `hostID` (random) and the connector's credential. The relay never
receives `K_host_static`.

**Enroll a device.** Two paths, and the difference matters for the threat model:

1. **QR path (MVP).** The phone scans the extended pairing QR. The phone
   extracts `hostKey.pk` and pins it. The phone sends `hostKey.pk` to the relay
   as its `devicePublicKey`… no — this is wrong and must be stated precisely:
   the *device* has its own key pair. The QR carries the **host's** public key
   and an **enrollment blob** that lets the connector recognise the enrollment
   request. The phone generates `K_device_static`, registers it with the relay
   alongside the host ID, and sends the relay a `devicePublicKey` plus a
   `pairingProof` = `HMAC(K_host_static, devicePublicKey || hostID)`. The relay
   forwards the proof to the connector; the connector verifies it with its
   private key. A relay that fabricates a proof cannot pass verification.
2. **Re-pair path.** Over an existing sealed channel, the device proves
   possession of the old static key; the connector swaps the enrolled key.

**Revoke.** Three independent levers, all required:

| Lever | Effect | Where |
|---|---|---|
| Relay deletes the device route | The relay refuses to route to/from the device | `DELETE /v1/devices/{deviceID}` |
| Connector drops the device public key | The handshake fails; the connector refuses to serve | `POST /v1/hosts/{hostID}/revoke-device` |
| APNs token deleted | Pushes stop | APNs `410`, or `DELETE /v1/push/{token}` |

**Revocation must propagate within one keepalive interval (≤90 s)** for the
connector-side lever, and immediately for the relay-side lever.

**Gap to close:** today `opencode pair` issues a token with **no human
confirmation on the server side** — `PairingClient.redeem` is a single
unauthenticated `GET /auth/connect/<code>` that returns a token immediately
(verified in `PairingClient.swift`). Whether the *server* also prompts the user
to approve the device is **unverified — needs check** (requires an
`opencode-official` checkout, which is not present in this workspace). For the
relay, a server-side approval step is **required**: the connector must display
the incoming device's fingerprint and require an explicit confirmation before
enrolling it. Without that step, anyone who can photograph the QR for five
minutes enrolls a device.

### 4.6 Multiplexing several hosts

**The relay supports N hosts per account and N devices per host. The iOS
client does not need both, today.**

The client's current model is explicitly **one active host at a time**:
`currentHostProfileID` drives a single `APIClient` and a single SSE connection,
and `beginHostTransportTransition` tears everything down on a switch
(`disconnectSSE()`, `sshTunnelManager.disconnect()`, `hostRequestGeneration &+= 1`,
plus a full runtime reset in `resetConnectionRuntimeForHostSwitch`).

The design therefore has two levels:

| Layer | Capability | When |
|---|---|---|
| **Wire** | One relay connection carries frames for **any** `hostID`. Switching hosts does not tear down the relay session; only the inner route changes. | Now (free — it falls out of `hostID` being in the envelope) |
| **Client** | The app still shows one host at a time. `HostProfilesView` lists relay hosts; selecting one switches the inner route. | MVP |
| **Client (later)** | Concurrent multi-host subscriptions: one connection, N inner SSE streams, a per-host badge in the session list. | Deferred — it is a UI and state-model change, not a protocol change |

**The relay-side fan-out is where cost multiplies.** If 2 devices are subscribed
to the same host, the relay egress doubles for that host's stream. Mitigation:
the relay fans out only to devices with a **live subscription or a push
subscription**, and applies per-device backpressure (a slow device's queue is
dropped, never the whole host's).

### 4.7 Offline queueing

**Two different queues, and the difference is a design decision, not an
implementation detail.**

| Queue | Where | Holds | TTL | Rationale |
|---|---|---|---|---|
| **Relay → device** | Relay | Sealed inbound envelopes for an offline device | Attention events: 24 h. Ordinary responses: 5 min (a stale HTTP response is worthless). | Lets a phone that was asleep still get the "the agent needs you" ping. Sealed, so the relay can't read it and the operator can't be asked for it. |
| **Device → host** | *(none in MVP)* | — | — | See below. |

**The MVP has no client-side request queue.** If the app cannot reach the host,
the send fails visibly and reuses today's existing path: `MessageStore.markSendFailed(messageID:reason:)`
and the inline failure banner (`failedSendReasonsByID`). This is deliberate:

- The existing outbound queue (`MessageStore.outboundSends`) is **in-memory
  only** — `MessageStore` persists only `stepTimings` to `UserDefaults`
  (verified). There is no durable client-side outbox to extend.
- A durable client-side outbox would have to seal a request under a key that
  survives the session, i.e. the long-term `K_pair`, which is weaker than the
  ephemeral `K_chan` and creates a new on-disk store of user content.
- The MVP's value is *push*, not *offline sending*. A user whose agent asks a
  question while they are on the subway wants the ping, not the queue.

**Deferred:** a durable encrypted outbox, modelled on
`ClientCapabilityCallbackStore`'s conventions (Application Support directory,
`Pending/` + `Outbox/`, atomic temp-file-then-move writes, bounded record
count, TTL-based cleanup) — the pattern already exists in this codebase and
should be copied rather than reinvented.

### 4.8 Client API surface the app needs

New Swift types and seams (none of these exist today):

```swift
// Transport seam — the app currently has one only for SSE.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(_ request: URLRequest) -> AsyncThrowingStream<UInt8, Error>
}

// New client for the relay side.
actor RelayClient {
    func register(devicePublicKey: Data, apnsToken: String?) async throws -> RelayRegistration
    func connect(hostID: String) async throws -> RelaySession      // WebSocket + handshake
    func enroll(host: RelayHostEnrollment) async throws -> String  // hostID
    func revokeDevice(hostID: String, devicePublicKey: Data) async throws
    func push(token: String, hostID: String) async throws
    func unregister() async throws
}

// The envelope codec — must be unit-testable with saved bodies, like V2Mapper.
struct RelayEnvelope: Codable { /* v, kind, id, seq, class, blob */ }
struct RelaySealer { /* seal/open with K_pair and K_chan */ }
```

**Why a transport seam and not a `URLProtocol`:**

- `SSEClient` already has one: `protocol SSEHTTPOpener` with
  `init(opener:)` (`SSEClient.swift:110-158`). `URLSessionSSEHTTPOpener` uses
  `URLSession.shared`, hardcoded — so making SSE work through the relay
  requires either injecting a `URLSession` into that opener or adding an
  `HTTPTransport` conformance.
- `APIClient` has **no** transport seam: `makeRequest` calls
  `session.data(for: request)` directly (`APIClient.swift:117-164`). The
  `session` is injectable via `init(baseURL:username:password:session:generation:)`,
  so a custom `URLProtocol` registered on that session would work with **zero
  changes to `APIClient`** — but `URLProtocol` must strip the `Authorization`
  header (it carries the host Basic auth) and move it into the sealed envelope.
- **Risk:** `URLSession.bytes(for:)` streaming behaviour under a custom
  `URLProtocol` is **unverified — needs check**. If it does not stream, the SSE
  path needs a raw TLS socket (`Network.framework` `NWConnection`) instead.
  This is the single biggest implementation unknown in the client plan and it
  should be spiked in R0, before the protocol is frozen.

The recommendation: **introduce the `HTTPTransport` seam** (one protocol, two
implementations — `URLSessionTransport` for today's behaviour,
`RelayTransport` for the relay) and route by host profile. The precedent
already exists in the codebase: `APIClient.makeWatchClient()` returns a second
`APIClient` with a different `URLSession` for the watch, and `AppState` holds
`let apiClient: APIClientProtocol`.

**Behavioural requirement for the relay transport:** the inner request's
`Authorization: Basic …` header must be moved *inside* the sealed envelope and
must not appear on the wire to the relay. A test must assert that the bytes
sent to the relay contain no `Basic ` string.

---

## 5. Push transport

### 5.1 Shape

```
Connector (on the user's server)
  │  sees: question.asked, permission.asked, session.error, turn complete
  │  builds a content-free envelope, seals it to the device's push key
  ▼
Relay  ── stores the sealed blob, and sends an APNs push with a generic body
  │
  ▼ APNs
iPhone ── receives the push, decrypts the blob locally, routes to the session
```

This is exactly the push research's "Notification Bridge" topology, with one
change: the envelope that crosses the relay is **sealed**, so the relay cannot
read the event type, the session id, or anything else. The push research's
recommended envelope (`schema_version`, installation id, event id/type, session
id, request id, timestamp) becomes the *plaintext inside* the seal.

### 5.2 The APNs payload

```json
{
  "aps": {
    "alert": { "title": "OpenCode", "body": "Your agent needs your input." },
    "sound": "default",
    "interruption-level": "active",
    "badge": 1
  },
  "relay": { "v": 1, "op": "<sealed blob, base64url>" }
}
```

- `aps.alert.body` is **generic**. It must not contain the host name, the
  session title, the question text, or the file path — the notification is
  rendered by iOS on the lock screen, where any of those is a leak onto the
  lock screen of a device that may be shared or observed.
- `relay.op` is the sealed blob. The relay cannot read it. The app decrypts it
  after the user taps, and only then resolves the session and shows detail.
- `badge` is updated by the same path. The app clears it when the attention
  item is resolved, reusing the existing attention-count model in `AppState`
  (the `sessionsIndicatorNeedsYou` state).

### 5.3 Token handling

| Item | Rule |
|---|---|
| Registration | The app calls `UIApplication.registerForRemoteNotifications()` and, on every `didRegisterForRemoteNotificationsWithDeviceToken` callback, re-POSTs the token to the relay. **APNs tokens rotate; the app must re-register every time it is handed one.** |
| Storage | The relay stores `(deviceID, token, environment, updatedAt)`. The app stores nothing about APNs beyond the OS. |
| Token deletion | On APNs `410 Gone` / `Unregistered` → delete the token immediately and stop sending to it. |
| Environment | `sandbox` vs `production` must match the build. A TestFlight build (production) must not be sent to a sandbox token. |
| Multiple devices | One APNs token per device install. The relay keys by `deviceID`, not by token, so a token rotation is not a new device. |
| Not a user identifier | The relay never receives an Apple ID. The APNs token is opaque to the relay and meaningless outside the APNs ecosystem. |

### 5.4 Delivery guarantees — stated honestly

**APNs does not guarantee delivery.** It is a best-effort, at-most-once store
and forward. The design therefore treats push as an *accelerator*, never as the
source of truth:

| Property | Behaviour |
|---|---|
| Delivery guarantee | **None.** A push can be dropped by APNs, by the relay, or by the device's network. |
| Priority | `apns-priority: 10` (immediate) for `question.asked` / `permission.asked` / `session.error`. `10` for turn-complete too — a turn-complete that arrives 20 minutes late is noise, so consider `5` (power-efficient). |
| Expiry | `apns-expiration` = 1 h for attention events, 5 min for turn-complete. The relay drops anything past expiry rather than delivering a stale notification. |
| Collapse | `apns-collapse-id` = `relay-<hostID>` so a burst of attention events for one host collapses to the latest. |
| Dedupe | Key = `HMAC(K_dedupe, hostID || eventType || requestID)`, computed by the connector and carried in clear. The relay compares keys and suppresses duplicates. `K_dedupe` is **not** the seal key. |
| Retry | On APNs 5xx / timeout: exponential backoff, 3 attempts, 60 s total. Then drop. |
| Ordering | Not guaranteed. The app must not assume event order from a push. |

**Honest caveat on the dedupe key:** `eventType` is a small enum. A relay that
holds `K_dedupe` can brute-force it (a handful of candidate HMACs) and thus
learn *that* a permission was requested on a host at a time. That is metadata,
not content, and it is the price of giving the relay the ability to dedupe and
rate-limit. The alternative — a fully opaque key — would leave the relay unable
to do either job. This tradeoff is accepted and must be stated in the privacy
policy, not hidden.

**The real guarantee is the pull path.** The app already reconciles pending
permissions and questions from the server: `AppState+SSE.swift:201-203` calls
`refreshPendingPermissions()` and `refreshPendingQuestions()` in the SSE
reconciliation set, and session selection loads them too
(`AppState+Permissions.swift:40,92` → `APIClient.pendingPermissions()` /
`pendingQuestions()`). That reconciliation, not the push, is what makes the
system correct. The push only makes it *fast*.

### 5.5 When the relay is down

| Situation | Behaviour |
|---|---|
| Relay process down | Pushes stop. The connector's outbox accumulates sealed envelopes and retries with backoff, bounded (24 h, 100 envelopes). |
| Relay reachable, device offline | The relay queues the sealed blob until the device reconnects or the TTL expires. |
| Device offline, host unreachable | Nothing to push — the host itself is down. |
| **Relay down, and the relay is the user's only route to the host** | **Total loss of access.** This is the design's main availability risk and it is the reason invariant 2 exists. A self-hosted path (direct / SSH tunnel) must remain a supported, free, first-class option. The host card must show a "relay offline" state, and the app must fall back to a direct attempt when the relay fails. |
| Relay down, the user has a direct route | No impact. The app behaves exactly as today. |

The relay must publish a status page and expose a `GET /v1/health`. The app
should surface relay health separately from host health — today `ConnectionPhase`
covers the *host* connection only (`idle`, `sshGateway`, `sshAuth`,
`localTunnel`, `health`, `bootstrap`, `connected`, `failed`), and a relay adds
new phases.

---

## 6. Threat model

Actors: **R** = the relay operator (honest-but-curious, or malicious, or
compelled by a legal order); **D** = the device owner; **A** = an attacker with
the unlocked phone; **M** = a malicious app on the phone; **H** = an attacker
who has compromised the user's own server.

### 6.1 Attack paths and mitigations

| # | Path | Impact | Mitigation | Residual |
|---|---|---|---|---|
| T1 | **R reads the traffic** | Full disclosure of prompts, replies, code | E2E seal with `K_pair`/`K_chan`; R holds no key. Verified by construction: the relay's endpoints only ever accept and forward `blob`. | R still sees routing metadata and volume/timing (§3.3). |
| T2 | **R replays a captured envelope** | Re-delivering an old prompt or an old attention event | Monotonic per-direction `seq`; receiver rejects `seq <= lastSeen`; envelope AAD binds `hostID`/`deviceID`/`class`; replay window. | R can still *suppress* (see T3). |
| T3 | **R drops or delays envelopes** | Denial of service; a missed "agent needs you" | Sequence-gap detection → `resync(from:)` from the peer; the host is authoritative so state is recoverable via the REST reconciliation path the app already has. | R can stall indefinitely. The app must time out and surface it. |
| T4 | **R MITMs the handshake** | Reads or rewrites content | The handshake is `X25519(device_ephemeral, host_pub)` where `host_pub` was pinned from the QR, out of band. R cannot substitute a key. | If the *user* scans a hostile QR, the whole anchor is lost. |
| T5 | **R serves a stale host key to a device** | Downgrade / impersonation | The phone pins `host_pub` at pairing; a change requires an explicit re-pair and shows the fingerprint diff (same pattern as `SSHKnownHostStore`). | Requires the user to actually read the fingerprint. |
| T6 | **R enrolls a rogue device** | Receives all traffic for a host | The connector verifies `pairingProof = HMAC(K_host_static, devicePublicKey || hostID)` with its private key. R cannot forge it. **Plus** the connector requires human approval of the device fingerprint. | If the user approves a hostile QR, R gets in. |
| T7 | **A steals the unlocked phone** | Full read/write of that host | The phone holds the host Basic auth in the Keychain today, so this is a pre-existing exposure. The relay adds: **remote, fast revocation** (relay route deleted, connector drops the device key, APNs token deleted) effective within ≤90 s. Optional hardening: biometry-gated `kSecAccessControl` on the relay credential — `KeychainHelper` currently uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` with no access control, so this is a change. | An unlocked stolen phone is compromised until revoked. |
| T8 | **M is a malicious app on the phone** | (a) Hijacks the `opencode://` scheme to fake a notification tap; (b) registers a rogue APNs token; (c) harvests the pairing code from the clipboard | (a) is a **known, accepted** gap already documented in the push research; fix is Universal Links / Associated Domains — deferred. (b) is low impact: a rogue token only wakes the attacker's phone with a generic body. (c) the pairing code is single-use and 5-minute-lived, but clipboard harvesting is generic; the connector-side human approval step is the real mitigation. | M cannot read the app's Keychain items (no shared access group), so it cannot steal the seal keys or the host Basic auth directly. |
| T9 | **H compromises the user's server** | Full disclosure of everything for that host; can impersonate the host to enrolled devices | **None available.** The host is the trust anchor. Devices pin the host key, so H cannot impersonate the host to a device without also changing the pinned key — but H *is* the host, so it can serve a fake key at pairing time. | The relay cannot help. This is by construction: the user's server holds the data and the model credentials. |
| T10 | **H steals only the pairing token** | Impersonates the phone to the host | The token is a bearer credential accepted as the Basic-auth password. Out of scope for the relay; the relay's own credential is separate and revocable. | Pre-existing exposure of the `opencode pair` design. |
| T11 | **R serves a malicious APNs payload** | Spoofed notification | The APNs provider key lives only on the relay; R is the APNs provider, so R *can* push arbitrary content to the device. The sealed `relay.op` does not help — R controls the outer payload too. Mitigation: the app must treat a push as a *hint*, never as authority. It must not act on a push payload; it must connect and re-read state from the host. The app already has this discipline for the deep-link path (it re-pulls state rather than trusting the payload). | **R can send arbitrary notification text to the device.** Documented honestly: the relay's push channel is a trusted-by-construction channel, because R is the APNs provider. The mitigation is that a push never *authorises* anything. |
| T12 | **R compels the operator to disclose** | Legal process | The relay holds no decryptable content, so a disclosure request yields metadata only. This is a genuine, checkable property of the design and the reason to build it this way. | Metadata (IPs, timestamps, ids) is still disclosable personal data. |

### 6.2 What this design cannot protect against

- **An unlocked stolen phone** (until the device is revoked; revocation is the
  mitigation, not encryption).
- **A compromised host.** The host holds the data, the model credentials, and
  the truth. The relay is downstream of the trust anchor and cannot help.
- **A malicious app on the device** with the user's cooperation (QR capture,
  clipboard, notification-tap spoofing).
- **Traffic analysis.** Volume, timing, and who-talked-to-whom.
- **Denial of service by the relay.**
- **The relay learning the connector's home IP** if the connector dials out
  directly (§3.3).
- **The relay sending arbitrary notification text** (T11).
- **The user's own operator.** They own the server and the data.
- **Legal compulsion of the relay.** Only metadata is disclosable — which is the
  intended property, not a protection against the process itself.

---

## 7. Unit economics

### 7.1 Assumptions (stated, so they can be argued with)

| # | Assumption | Value | Basis |
|---|---|---|---|
| A1 | Accounts per active user | 1 | One phone, 1–2 hosts |
| A2 | Agent turns per day | 40 | PRD §2: heavy users open the app repeatedly; 8 sessions/day × ~5 turns |
| A3 | Inner payload per turn | 44 KB | prompt 0.5 KB + reply 3 KB + SSE tool/delta events 40 KB |
| A4 | Foreground reconciliation | 6 refreshes/day | session list 20 KB + message page 60 KB |
| A5 | File/diff browsing | 10 opens/day × 150 KB, 30 % of users | Files are a minority interaction (PRD: the chat window is primary) |
| A6 | SSE share of traffic | 60 % | Deltas dominate a coding-agent session |
| A7 | Connector duty cycle | 50 % | The connector only uploads events while a device is subscribed or a push window is open |
| A8 | Envelope coalescing | 16 KB or 50 ms | Bounds sealing overhead; see below |
| A9 | Sealing overhead | 1.1 % | 16-byte tag + 12-byte nonce + ~150 B envelope JSON per coalesced envelope |
| A10 | Egress price | $0.09/GB | Cloudflare / AWS-class egress. **unverified — needs check** for 2026 rates |
| A11 | APNs pricing | $0 per iOS push | Apple charges only for Safari push destinations. **unverified — needs check** for 2026 pricing |
| A12 | Fixed relay cost | $60/month | One always-on service + a small DB + observability, sized for ~2,000 active users |

**On A8/A9.** Sealing each SSE frame individually costs ~180 bytes per frame;
at ~100 frames per 40 KB turn that is ~45 % overhead. Coalescing frames into
16 KB / 50 ms envelopes cuts overhead to ~1 %. This is a protocol requirement,
not an optimisation: without it the relay's bandwidth bill and the phone's
battery both roughly double.

### 7.2 Per-user monthly volume

| Line | Computation | MB/month |
|---|---|---|
| Agent turns | 44 KB × 40 × 30 | 52.8 |
| Foreground reconciliation | 0.48 MB × 30 | 14.4 |
| Files/diff | 0.45 MB × 30 | 13.5 |
| **Inner payload** | | **80.7** |
| Sealing overhead (A9) | ×1.011 | +0.9 |
| **Ciphertext, relay → device** | | **≈ 81.6** |
| Connector → relay ingress | 81.6 × A7 (50 %) | 40.8 (ingress) |

### 7.3 Cost per active user per month

| Cost item | Basis | $/user/month |
|---|---|---|
| Egress, relay → device | 0.0816 GB × $0.09/GB | **$0.0073** |
| Ingress, connector → relay | usually free or ~$0.005/GB | ~$0.0002 |
| Storage | ~21 KB/user (0.5 KB device + 0.3 KB host + ~20 KB queued envelopes), 30-day retention | **<$0.001** |
| APNs delivery | free for iOS (A11); egress to APNs 30 KB/mo | **$0.000** |
| APNs provider-token compute | 1 JWT signature/hour | ~$0.000 |
| Relay compute | 2 long-lived connections/user; ~$0.003/user at $60/2,000 users (A12) | **$0.003** |
| **Marginal total** | | **≈ $0.011** |
| Fixed-cost allocation at 2,000 users | $60 / 2,000 | **$0.030** |
| **All-in COGS per active user** | | **≈ $0.04** |

**Heavy-user tail (10×):** 816 MB/month → egress $0.073 + compute $0.003 →
**$0.08/month**. Even a 100× user is under $0.80/month. **Bandwidth is
essentially free; it is not the reason to price anything.**

### 7.4 What actually determines the price band

Because COGS is ~$0.04/user/month, the price is set by three things, none of
which is bandwidth:

1. **Payment channel.** App Store IAP takes 15 % (Small Business Program, ≤ $1 M
   annual proceeds) or 30 %. At $4.99/month that is $0.75–$1.50/month of pure
   commission — 12–30× the entire COGS. The choice between IAP and external
   purchase therefore moves the *net* by more than the entire infrastructure
   cost. This is OQ-1 and it is the most consequential open question in the
   document.
2. **Support and trust.** A relay outage is a total loss of access for a paying
   user whose only route is the relay. Support cost, not bandwidth, is the
   marginal cost driver. Mitigation: the free tier must keep direct/SSH
   working, and the paid tier must fall back to direct automatically.
3. **Fixed compliance surface.** Accounts, account deletion, ToS, privacy
   policy, DPA, tax handling. One-time, not per-user, but it must be funded
   before the first paying user.

### 7.5 Recommended price band

**$4.99/month or $39/year**, flat per account, unlimited hosts, no metering.

| | $39/year | $4.99/month |
|---|---|---|
| Gross revenue | $39.00 | $59.88/yr |
| Net of 30 % IAP | $27.30 | $41.92/yr |
| Net of 15 % IAP | $33.15 | $50.90/yr |
| Net COGS (12 × $0.04) | $0.48 | $0.48 |
| **Gross margin** | **≥ 98 %** | **≥ 99 %** |

Rationale: the relay replaces a $5–10/month VPS-or-tunnel for the user and
delivers a workflow the free tier cannot (the PRD's core gap: *"when the AI
pauses and waits for a human decision… the user receives no notification while
away from the App"*). It is priced against **that** alternative, not against its
own cost.

**Explicitly not offered:** per-GB tiers, per-turn metering, per-host pricing
(hosts cost ~$0, so unlimited removes a support question rather than costing
revenue), model-credit bundles, stored balances. This is invariant 3.

**Byte quotas exist, but as abuse control, not as a revenue lever.** The relay
is a general-purpose TCP forwarder by construction; without a per-account byte
cap, one account can be used as an open proxy. Cap at, say, 10 GB/month
(≈ 120× the median user) and treat the cap as a safety limit.

### 7.6 The number that is actually unknown

**Willingness to pay**, not unit cost. COGS is $0.04; if the market will not
pay $4.99/month for "my home agent pings my phone and I can answer it", no
pricing discipline saves the product. The MVP should therefore be validated
against willingness-to-pay *before* the relay is built for scale — i.e. R1–R3
ship to a small cohort, with the free tier untouched.

---

## 8. MVP scope

### 8.1 The smallest slice a user would actually pay for

> **"My agent asked me something while I was away, my phone buzzed, and I
> answered it from the sofa."**

One host. One phone. The relay carries:

- **Attention push** for `question.asked`, `permission.asked`, `session.error`,
  and turn-complete.
- **A sealed text channel** to the host: health check, session list, get
  session, send prompt, poll messages.

Explicitly **not** in the MVP: file content, diffs, SSE delta streaming,
concurrent multi-host subscriptions, presence.

Rationale for cutting the file/diff/SSE surface: the PRD is unambiguous that
the phone is a *steering terminal*, not an editor ("This App explicitly does
not: edit code on the phone"). Text steering is the product. File browsing is
a minority interaction and is usually available over a LAN/VPN anyway.

### 8.2 Milestones

| # | Milestone | Contents | Exit criterion | Size |
|---|---|---|---|---|
| **R0** | Contract freeze | Relay wire spec (envelope, seal, routing, coalescing), connector API, threat model sign-off, App Store payment position decided (OQ-1), **the `URLSession.bytes(for:)` + `URLProtocol` streaming spike** | A written spec; a connector stub can register against a local relay and exchange one sealed envelope | S |
| **R1** | Relay skeleton | Device + host enrollment, credential issuance, envelope routing, per-route sequence counters, TTL + size caps, revocation, `GET /v1/health` | Two processes exchange sealed envelopes; revocation drops the route within 90 s | M |
| **R2** | APNs leg | Device token registration/rotation/deletion, provider auth (p8 JWT cached ≤1 h), send with priority/expiry/collapse-id, `410` handling, retry + backoff, dedupe key | A push reaches a real device from a fake connector; a revoked token stops receiving pushes | S |
| **R3** | Connector | An OpenCode plugin **or** companion daemon on the user's server: outbound connection to the relay, emits attention envelopes, serves the sealed request/response channel against `127.0.0.1:4096`, enforces device-approval + fingerprint display | `opencode pair` + relay → a real `question.asked` produces a push on a real phone | **L** |
| **R4** | iOS client | `.relay` transport, enrollment UI, `HTTPTransport` seam, sealed request/response, push registration, notification tap → session, en+zh localization | The phone, on cellular, sends a prompt to a home server through the relay and shows the reply | **L** |
| **R5** | Accounts + billing | Relay account, plan, purchase flow, **in-app account deletion**, App Privacy answers rewritten, privacy policy + ToS, DPA | A real purchase works; deletion removes every relay-side record | M |
| **R6** | Hardening | Rate limits, byte quotas, abuse controls, metadata-only audit log, status page, relay kill switch, backup/restore of relay state | A kill switch drops all traffic; a deleted account leaves nothing behind | M |

S/M/L are rough relative sizes, not calendar estimates.

### 8.3 Client-side change inventory (R4)

| File | Change | Risk |
|---|---|---|
| `Models/HostProfile.swift` | Add `HostTransport.relay`; add `relay: RelayHostConfig?` (`hostID`, `pinnedHostPublicKey`, `pinnedHostFingerprint`); `HostProfile.init(from:)` must default the new field | **HIGH** — see below |
| `AppState+HostProfiles.swift` | `applyCurrentHostProfileToRuntime` must route relay hosts to the relay transport; `beginHostTransportTransition` must `relayManager.disconnect()`; `saveHostProfile` must not clear `apiGeneration` when the *relay* URL is unchanged but the *host* changed | MEDIUM |
| `Services/APIClient.swift` | Introduce the `HTTPTransport` seam; move the inner `Authorization: Basic` header into the sealed envelope | MEDIUM |
| `Services/SSEClient.swift` | `URLSessionSSEHTTPOpener` must accept an injected `URLSession` (it hardcodes `URLSession.shared`) | LOW |
| New `Services/RelayClient.swift`, `Services/RelaySealer.swift`, `Models/RelayEnvelope.swift` | New code | M |
| `Views/HostProfilesView.swift` | Relay section: enroll, show host fingerprint, list + revoke devices, relay health | LOW |
| `Support/L10n.swift` | New `Key` cases **plus** `en` and `zh` entries — `L10n.missingEnglishKeys` / `missingChineseKeys` enumerate the gaps and will fail a localization audit | LOW |
| `Models/ConnectionPhase` | New phases: `.relayHandshake`, `.relayKeyExchange` | LOW |

**HIGH risk, concretely.** `HostTransport` today has exactly two cases
(`direct`, `sshTunnel`) and `HostProfile.init(from:)` does
`transport = try c.decode(HostTransport.self, forKey: .transport)` — a
**non-optional** decode with no fallback. `loadHostProfilesFromStorageOrLegacy`
decodes the whole array in one shot:

```swift
if let decoded = try? JSONDecoder().decode([HostProfile].self, from: data) { ... }
else { hostProfileBlobUnreadable = true; ...; installLegacyHostProfile(persist: false) }
```

Therefore: adding a `.relay` raw value means a host list written by the new app
**fails to decode entirely on an older app**, the blob is marked unreadable,
and the user silently loses their whole host list (replaced by the legacy
migration path). This is an all-or-nothing decode and it is the single most
likely way to ship a data-loss bug.

Mitigation: introduce a versioned container — `HostProfileBlob { version: Int,
hosts: [HostProfile] }` — and decode hosts **individually**, dropping only the
hosts that fail, with the rest preserved. This is required before `.relay`
ships, regardless of the relay itself.

**Second concrete risk.** `apiGeneration` is currently bound to `serverURL`
("changing the URL clears it" — `HostProfile.apiGeneration`, and
`saveHostProfile` resets it when `serverURL` changes). For a relay host,
`serverURL` is the *relay's* address, but the generation belongs to the *host
behind the relay*. Two relay hosts behind the same relay URL would share one
cached generation → one of them speaks the wrong API dialect (V1 vs V2) →
silent breakage. For `.relay` hosts, `apiGeneration` must be bound to `hostID`.

---

## 9. Explicitly deferred

| Deferred | Why not in the MVP | When |
|---|---|---|
| File content and diff streaming through the relay | Large payloads, minority interaction, usually available over LAN/VPN | After WTP validation |
| SSE delta streaming through the relay | Requires the `URLProtocol`/socket streaming answer (R0 spike) and multiplies egress | After R4 |
| Concurrent multi-host subscriptions | The client is single-active-host by design today | Product decision |
| Presence / online indicators | Metadata cost, no proven demand | — |
| Relay-hosted web dashboard | Only if needed for the external-purchase escape hatch (OQ-1) | See OQ-1 |
| Sharing one host across two phones | Multiplies fan-out egress; not requested | — |
| Any OpenCode server core change | The connector should be a plugin or companion daemon (per the push research), so upstream upgrades do not break it | — |
| Bundling model credits / provider keys | Invariant 3 | Never |
| Relay-side request logging, analytics, crash reports | Would reintroduce metadata into durable storage | Never, unless the privacy policy is rewritten to match |
| End-to-end-encrypted file transfer separate from the text channel | Same reason as file streaming | After R4 |
| Windows / Android / macOS clients | The relay protocol is client-agnostic; only the iOS client exists | — |

---

## 10. Open questions

Each question names the decision it blocks. **OQ-1, OQ-2 and OQ-3 are the
blocking trio.**

### OQ-1 — App Store payment route and review posture (blocks the entire revenue design)

*Can the relay be sold outside the App Store?*

Guideline 3.1.1 requires IAP for digital services consumed in the app. A relay
subscription consumed by the iOS app is a digital service, so IAP is the default
answer. Guideline 3.1.3(b) permits external purchase for a "multiplatform
service" that is also usable on other platforms — which would require a web
dashboard or a companion CLI that manages the same relay account.

Separately: does a service that tunnels a phone to arbitrary user-controlled
servers raise 2.5.4 (VPN) or 4.3 (spam) concerns for a reviewer? This design
uses plain TLS, not the Network Extension VPN API, and is scoped to enrolled
devices — but a reviewer may not read it that way.

**Blocks:** pricing, the account model, IAP integration and its 15–30 %
commission, whether R5 needs a web dashboard, and the App Privacy rewrite.
**unverified — needs check** against current App Store Review Guidelines and,
ideally, an App Review pre-submission conversation.

### OQ-2 — Connector distribution and the server-side approval step (blocks the encryption anchor)

*How does the connector get onto the user's server, and does the enrollment
require human approval?*

The pairing exchange today issues a token immediately and unconditionally
(`PairingClient.redeem` → `GET /auth/connect/<code>`, single unauthenticated
GET, 5-minute single-use code). For the relay, the connector must:

1. Display the incoming device's fingerprint and require an explicit approval
   before enrolling it (otherwise a photographed QR is a permanent compromise).
2. Carry `K_host_static` and publish `K_host_pub` in the pairing QR.

That means either (a) an OpenCode plugin can print the extended QR and approve
devices, (b) a companion daemon does, or (c) the server core is forked. Option
(c) breaks the "no server source changes" property the push research prizes.

**Blocks:** the encryption anchor (§3.1), the enrollment threat model (T6),
whether we can ship without forking the server, and R3's shape.
**unverified — needs check** whether `opencode pair` can already print an
arbitrary payload and prompt for approval (requires an `opencode-official`
checkout, not present in this workspace).

### OQ-3 — Does the user have to verify the host fingerprint, or is TOFU acceptable? (blocks the enrollment UX and the MITM claim)

*Out-of-band comparison, or trust-on-first-use like SSH?*

The codebase already has the TOFU precedent (`SSHKnownHostStore` pins the first
host key and prompts on mismatch). But TOFU means a hostile QR is trusted
silently, and the relay's entire value proposition is "the relay cannot see
your traffic" — which is only true if the *host* key is genuinely pinned.
Signal-style safety numbers require a comparable channel on the server side
(the web UI or the TUI), which raises the connector's cost.

**Blocks:** the strength of the §3.1 anchor, the enrollment UI, whether the
connector needs a TUI/web-UI surface (OQ-2), and whether T5 is honestly
mitigated.

### OQ-4 — Metadata budget (blocks the privacy policy and the App Privacy answers)

*What is the relay contractually allowed to see?*

Currently the answer is "ids, sizes, timings, IPs". That includes the
connector's home IP (§3.3), which is a strong identifier. Options: mandate a
user-provided egress (Tailscale/WireGuard) for the connector, shorten IP
retention, or forbid long-term correlation of IP with `hostID`.

**Blocks:** the privacy policy, the App Privacy questionnaire, the GDPR/DPA
posture, and the marketing claim.

### OQ-5 — Keychain protection for the relay credentials

*Should the relay credential and the device static key be biometry-gated?*

`KeychainHelper` uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` with
no access control. A relay credential gated by `kSecAccessControl` with
`.biometryCurrentSet` would mean a stolen-but-unlocked phone still cannot use
the relay — but it would also break background push-triggered wakeups and
force a biometric prompt on every reconnect, which is hostile for a
"notification wakes me up" workflow.

**Blocks:** the stolen-device mitigation depth (T7), and whether the device
static key can live in the Secure Enclave (which would make it
non-exportable but also non-backup-able and harder to re-enroll).

### OQ-6 — SSE streaming through a custom transport

*Does `URLSession.bytes(for:)` stream under a custom `URLProtocol`?*

If not, the SSE path needs a raw TLS socket. **unverified — needs check.** This
is R0's spike and it gates the choice between the `URLProtocol` shortcut and the
`HTTPTransport` seam.

### OQ-7 — Regulatory classification of the relay

*Does routing a user's traffic through a hosted service make the operator an
electronic communications provider in the EU/UK?*

Unencrypted-to-the-operator but sealed payloads, with a clear "we hold no
content" position, is the best available posture, but the classification is a
legal question, not an engineering one. **unverified — needs legal review.**

### OQ-8 — Deployment target

*A container service, or a Cloudflare Worker with Durable Objects?*

Workers + Durable Objects give per-connection isolation and cheap idle
connections, but their pricing model and connection limits differ from a
container. Egress pricing differs too, which moves §7.3 by a small amount.
Not blocking, but it should be decided before R1 because it constrains the
envelope-queue implementation (Durable Object storage vs a database).

### OQ-9 — When does the host key fingerprint change become routine?

*If the connector regenerates `K_host_static` on every server restart, every
device must re-pair — unacceptable. If it never rotates, one long-lived key is
the crown jewel on the user's server.*

Mitigation: persist `K_host_static` in the server's config directory; rotate
only on explicit user action, with a re-pair prompt for every device. This
needs a product decision about how much friction a rotation is allowed to
cause.

### OQ-10 — What does "no subscription" mean for the free tier, exactly?

The free app must keep every `.direct` and `.sshTunnel` capability, including
SSH tunnel hosts. But the relay's *connector* (R3) is the thing that produces
push. Does the connector ship free (as an open-source plugin) with the relay
being the paid part, or is the connector itself the paid artifact? If the
connector is free, a user can run it against their own bridge and skip the
relay entirely — which is fine, and is in fact a trust argument, but it means
the relay's revenue comes only from users who want someone else to run it.

---

## 11. Verification notes

Claims in this document that are **not** verified against the repository and
need a check:

| Claim | Where | How to check |
|---|---|---|
| `opencode pair` issues a token with no server-side human approval | §4.5 | Read the `opencode pair` implementation in an `opencode-official` checkout (not present in this workspace) |
| Whether `opencode pair` can print an extended payload containing the host's public key | §3.1, OQ-2 | Same |
| APNs pricing for iOS destinations in 2026 | §7.1 A11 | Apple's published APNs pricing |
| Egress pricing in 2026 | §7.1 A10 | Cloudflare / AWS rate cards |
| Apple IAP commission tiers and Small Business Program eligibility | §7.5 | Apple's App Store Small Business Program terms |
| App Store Review Guidelines 2.5.4 / 3.1.1 / 3.1.3 / 4.3 / 5.1.1(v) applicability | OQ-1 | Current guidelines + App Review pre-submission |
| `URLSession.bytes(for:)` streaming under a custom `URLProtocol` | §4.8, OQ-6 | A ~50-line spike |
| Standalone HKDF-SHA256 over a static key in CryptoKit | §3.4 | Check `SharedSecret.hkdfDerivedSymmetricKey` applicability |
| Whether an OpenCode plugin can reach the server's own HTTP API from inside the server process | R3 | `opencode-official` plugin API docs |
| Legal classification of the relay as an electronic communications provider | OQ-7 | Legal review |

Claims that **are** grounded in this repository:

| Claim | Source |
|---|---|
| Pairing code is single-use, 5-minute TTL, 22-char base64url from 16 random bytes | `PairingClient.swift:4-9`, `PairingLink.swift:118-136` |
| Redemption is `GET /auth/connect/<code>`; the token becomes the Basic-auth password with username `opencode` | `PairingClient.swift:77-99`, `HostProfilesView.swift:637-649` |
| `PairingLink.parse` accepts only an exact `/auth/connect/<code>` path | `PairingLink.swift:34-92` |
| `HostTransport` has two cases; `HostProfile.init(from:)` decodes `transport` non-optionally | `HostProfile.swift:3-15`, `HostProfile.swift:107-118` |
| The host-profile blob is decoded all-or-nothing; failure marks it unreadable and installs the legacy profile | `AppState+HostProfiles.swift:35-68` |
| `apiGeneration` is bound to `serverURL` and is cleared when the URL changes | `HostProfile.swift:79-81`, `AppState+HostProfiles.swift:263-267` |
| The client is single-active-host; switching tears down SSE, the SSH tunnel, and the runtime | `AppState+HostProfiles.swift:335-358`, `resetConnectionRuntimeForHostSwitch` |
| `APIClient.makeRequest` calls `session.data(for:)` directly — no transport seam | `APIClient.swift:117-164` |
| `APIClient.init` accepts an injected `URLSession` | `APIClient.swift:47-57` |
| `SSEClient` has an `SSEHTTPOpener` seam; `URLSessionSSEHTTPOpener` hardcodes `URLSession.shared` | `SSEClient.swift:110-159` |
| `APIClient.makeWatchClient()` is the existing precedent for two transports behind one interface | `APIClient.swift:91-97` |
| The outbound-send queue is in-memory only; only `stepTimings` persist | `MessageStore.swift:43-44`, `MessageStore.swift:62-66` |
| Failed sends already surface inline via `markSendFailed` | `MessageStore.swift:261-266`, `AppState+Messages.swift:259` |
| `ClientCapabilityCallbackStore` provides the durable outbox pattern (Pending/Outbox, atomic writes, TTL, record cap) to copy | `ClientCapabilityCallbackStore.swift` |
| `SSHKnownHostStore` provides the TOFU host-key fingerprint pattern to reuse | `SSHTunnelManager.swift:38-86` |
| `ConnectionPhase` enumerates the connection phases a relay would extend | `HostProfile.swift:17-55` |
| `L10n.missingEnglishKeys` / `missingChineseKeys` enumerate localization gaps | `L10n.swift` tail |
| The App Privacy answer is "Data Not Collected", justified by the app operating no service | `docs/appstore/app-privacy.md` |
| The push research recommends an outbound-only Bridge/Plugin and a content-free push envelope | `docs/features/push_notifications/research.md` |
| The PRD identifies background push as the missing capability in the Steer loop | `docs/OpenCode_iOS_Client_PRD.md` §1.2, §3.3 |
| Pending permissions/questions are reconciled from the server (the pull path behind push) | `AppState+SSE.swift:201-203`, `AppState+Permissions.swift:40,92` |
