# OpenCode iOS Push Notification Research

Updated: 2026-07-24

## Conclusion

We can implement notifications without modifying the source of every OpenCode Server, but relying on iOS client changes alone cannot achieve timely and reliable background message delivery.

When the iOS app is running in the foreground, the existing code already consumes the `/global/event` event stream in real time, precisely identifies the `question.asked` and `permission.asked` events, and classifies them as a Needs Attention state that requires human intervention. However, once the app moves to the background, the system actively tears down the SSE long connection and the SSH tunnel; even when it does not tear them down proactively, the underlying iOS system suspends ordinary network connections within a short time. Therefore, in order to still reach the user while the app is not in the foreground, a resident side service must be introduced that keeps listening to the server event stream and wakes or pushes a notification to the phone through Apple's official APNs channel.

On balance, we recommend introducing an independent Notification Bridge sidecar service rather than invasively modifying the core code of OpenCode Server:

```text
Multiple OpenCode servers
        │ existing SSE / REST, protocol unchanged
        ▼
Always-on notification bridge
        │ decides question / permission / done / error
        ▼
       APNs
        ▼
OpenCode iOS, tapping the notification opens the matching session
```

With this architecture we achieve the goal of "zero server-side changes", and the only cost is the introduction of an extremely lightweight resident sidecar service. If even this sidecar service is not allowed to be deployed, then the system can only degrade to background intermittent polling that is subject to system scheduling and cannot guarantee timeliness, which is not acceptable as a formally deliverable real-time push solution.

## The Current Client Already Has Half of the Capability

First, the client's existing `SSEClient` is already stably connected to the `GET /global/event` endpoint, so there is no need for the OpenCode server to specifically develop a new notification interface (see `OpenCodeClient/OpenCodeClient/Services/SSEClient.swift:51-137`).

Second, the client already has the business-layer capability to recognize the two core human-blocking event types: `permission.asked` and `question.asked` (see `OpenCodeClient/OpenCodeClient/AppState+SSE.swift:125-138`), and `AppState` already aggregates an Attention todo count by Session (see `OpenCodeClient/OpenCodeClient/AppState.swift:487-503`).

Third, the server's existing REST API system supports reconciliation fetches of pending Permission and Question data after a reconnect, so the Bridge service or the client does not need to depend heavily on the fragile transient SSE event stream (see `OpenCodeClient/OpenCodeClient/Services/APIClient.swift:386-423`).

Fourth, the routing and navigation groundwork for notification-tap wakeup is already complete. The client natively supports the `opencode://session/<session_id>` deep link (configuration in `OpenCodeClient/Info.plist:5-15`).

The one piece that is genuinely missing today is background delivery capability (Background Delivery). The app actively disconnects SSE and the SSH tunnel when it moves to the background (see `OpenCodeClient/OpenCodeClient/ContentView.swift:738-746`), and the current Xcode project has not yet configured the `aps-environment` entitlement signature, nor enabled Remote Notifications background mode support.

## Why a Client-Only Approach Does Not Work

### Local Notifications Only Cover Events Received While the App Is Still Running

If the app receives a `question.asked` event while running in the foreground, the client can of course schedule a Local Notification immediately. But the core scenario users actually depend on push notifications for is precisely the one where the app has already switched to the background or the phone is locked; during that period no network event can reach the phone at all, so the client naturally has no opportunity to trigger a local notification.

### Background Polling Can Serve as a Fallback but Cannot Carry Real-Time Notifications

The iOS `BGAppRefreshTask` mechanism can indeed wake the app up intermittently in the background so that it can call the `/permission`, `/question`, and `/session/status` endpoints, but its trigger timing is entirely determined by a black-box system policy, which easily produces delays or even outright skips, and Apple only provides an extremely brief execution window. This mechanism is suitable for calibrating the Badge count or acting as a fallback reconciliation, but it is completely unable to carry the immediate delivery need of "the AI has stopped and is waiting for the user to confirm" (see [Apple: Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)).

Moreover, under the current product architecture there is a second layer of obstruction: a host connected over SSH requires the app to proactively negotiate and establish the tunnel, and the existing background policy actively closes the tunnel when the app moves to the background. Even if the system occasionally grants a background wakeup opportunity, having the app complete an SSH handshake in the background, run a full poll across multiple hosts, and then trigger a local notification is engineering-wise extremely unstable and prone to timeouts and failures.

### Live Activity Is Not a Substitute for APNs

Live Activity is very well suited to presenting the continuous progress of a known long-running task, but even after the app enters the suspended state, updating the Dynamic Island or the lock screen widget remotely still fundamentally depends on the ActivityKit Push channel. At the same time, it is not suitable for carrying discrete, sporadic, high-priority human decision requests such as Permission or Question. The first-phase solution should focus on getting the standard Remote Push working; if there is a later need for long-task progress display, Live Activity can be evaluated separately.

### Do Not Borrow PushKit or Pretend to Be a Background Mode

PushKit is a channel Apple created specifically for strongly real-time scenarios such as VoIP calls. Borrowing it to keep an ordinary OpenCode event stream alive not only violates platform guidelines, it also carries an extremely high risk of being rejected during App Store review. Likewise, pretending to play audio or track location in the background does not apply to this business and must not be used as a technical solution.

## Recommended Architecture: Zero Server Source Changes, Add a Sidecar Bridge

The Notification Bridge has four core responsibilities:

1. Uniformly maintain the APNs Device Token reported by each iOS client installation, plus the Host and Session scopes that installation subscribes to.
2. Keep a long-lived connection to the `/global/event` SSE events of every configured OpenCode Host; after a disconnect, call the `/permission`, `/question`, and `/session/status` endpoints to complete a state reconciliation.
3. Rely on centralized filtering and deduplication rules to precisely decide which key events need to trigger a push.
4. Call the APNs API to deliver user-visible notification messages; the push Payload carries only the non-sensitive Host Profile ID, Session ID, and event enum, and the notification body strictly avoids the user's Prompt, source code paths, and server-side authentication credentials.

The standard APNs architecture itself requires the client to register the Device Token with the Provider, and then the Provider establishes a bidirectional secure connection with APNs to deliver the message (see [Apple: Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)).

### Where to Put the Bridge

In the initial landing phase with minimal changes, the Bridge can be deployed on a machine that stays powered on and can directly connect to all OpenCode Hosts. It can run as a standalone Daemon process, a Docker container, or a lightweight cloud service, and it does not need any compile-time dependency on the OpenCode server process code whatsoever.

If the servers are deployed inside mutually isolated LANs and there is globally no central node that can connect directly to every SSE stream, there is still no need to modify the server source; instead deploy a lightweight Watcher proxy inside each network domain, which reports the cleaned and normalized Attention events to a central APNs Gateway. The APNs push private key is held only by the central Gateway and never needs to be distributed to the edge nodes.

Compared to "invasively writing push logic inside every server", this deployment boundary fits the current multi-Host architecture far better: regular upgrades of the official OpenCode version do not break the push mechanism, and the push filtering rules can evolve centrally in a single location.

## A Multi-User Product Should Prefer an OpenCode Plugin

Having the central Bridge directly hold access to all users' Hosts only applies to personal private deployments. In a multi-user commercial product, the center must never collect users' OpenCode URLs, Basic Auth credentials, SSH private keys, or intranet penetration credentials. A more reasonable topology is a Plugin that listens for events inside the user's local OpenCode process and, only when triggered, sends a lightweight event digest to the central APNs Gateway over outbound HTTPS:

```text
User machine: OpenCode + notification plugin
                    │ uploads only a minimal attention envelope
                    ▼
              APNs gateway
                    ▼
                 iPhone
```

This approach requires no patch to the OpenCode Core source; users only need to install a Plugin on the host machine. OpenCode officially supports auto-loading locally written JS/TS Plugins from `~/.config/opencode/plugins/`, and also supports declaring npm package dependencies in the `plugin` list of `opencode.json`, which are automatically fetched and installed at server startup (see [OpenCode Plugins](https://opencode.ai/docs/plugins)).

### The Current Plugin API Is Sufficient for Notifications

The publicly exposed `Hooks.event` interface of OpenCode natively supports receiving strongly typed `Event` objects (see `opencode-official/packages/plugin/src/index.ts:222-225`). The stable events declared in the official documentation fully cover the core scenarios needed by the first phase of push notifications:

- `question.asked` / `question.replied` / `question.rejected`
- `permission.asked` / `permission.replied`
- `session.error`
- `session.idle` or `session.status`

The `serve` command layer of the server explicitly mounts `Plugin.node` (see `opencode-official/packages/opencode/src/server/routes/instance/httpapi/server.ts:212-225`), so this Hook definitely does not only work in terminal TUI mode. In addition, a Server Plugin can also obtain the SDK Client instance of the same process, the current Working Directory, and the Server URL (see `opencode-official/packages/plugin/src/index.ts:56-65`).

The current underlying event dispatch mechanism of OpenCode uses a fire-and-forget asynchronous calling strategy for Plugins (see `opencode-official/packages/opencode/src/plugin/index.ts:251-257`), so the time cost of the push network request will never block the normal inference and tool execution of an OpenCode Session. The Plugin itself must tightly capture all network exceptions and fall into a local Outbox for retries, preventing an uncaught Rejected Promise from turning into an unhandled process crash.

### Difficulty Assessment

If we only implement the basic Plugin that "issues one POST request to a Webhook upon receiving a `question.asked` event", the development effort is extremely small, and the core code only involves event filtering, Payload trimming, and signing the request. Notification plugins for platforms such as Pushover, Discord, and Slack already exist in the community, which strongly confirms the maturity and feasibility of this extension path.

Building a complete production-ready closed loop is a medium amount of work, and its core complexity lies mainly on the platform side and the network side, rather than in OpenCode itself:

| Module | Difficulty | Main work |
|---|---|---|
| OpenCode plugin | Small | Event filtering, privacy trimming, signing, outbox |
| User pairing | Medium | Securely binding a host installation to an iOS device |
| APNs gateway | Medium | Device token lifecycle, authentication, rate limiting, invalid token cleanup |
| Reliability | Medium | Local persistence, retries, deduplication, resolving event-revoked badges |
| Version compatibility | Small to medium | Tracking version changes of public event names and payloads |

### Preconditions for a Manageable Maintenance Cost

The Plugin itself should stay "lightweight and lean": strictly limited to consuming the public `event` Hook, without calling OpenCode's internal unpublished modules, without invasively modifying the normal flow of Permission or Question, and without synchronously blocking inside the Hook callback while waiting for a Gateway response. Assemble the push copy, the user's do-not-disturb preference, frequency control and rate limiting, and all APNs interaction logic in the Gateway; the Plugin only delivers a minimal Envelope payload carrying a version number.

The Envelope is recommended to contain only metadata such as `schema_version`, the Plugin/OpenCode version, Installation ID, Event ID/Type, Session ID, Request ID, and a timestamp. Uploading the Question body text, the Permission rule match item, the user's Prompt content, or concrete physical file paths is strictly forbidden by default.

For version management, a lightweight compatibility matrix must be maintained, covering at least the current latest version and the previous generation of the official OpenCode Release. Given that OpenCode has historically gone through v1/v2 event renames, the design must not assume that the Payload format stays unchanged forever; however, because we rely on the officially published standardized API, its maintenance and upgrade cost is significantly lower than directly maintaining a Fork branch or invasively parsing text logs.

### Recommended Pairing Flow

1. The iOS app reports and registers the APNs Device Token with the central Gateway and generates a short-lived temporary pairing code (Pairing Code).
2. The user runs the Setup configuration command provided by the Plugin package on the Host terminal and enters the pairing code; the command completes the Plugin installation and configuration and locally persists a generated Installation Secret key.
3. The Plugin subsequently uses only that Secret to sign structured Attention events sent to the Gateway. The Gateway side does not need to hold the user's OpenCode login credentials and does not have the network permission to access the Host in reverse.
4. When a push is delivered, the Payload carries only the Installation ID and the Session ID. After the iOS client receives the push, it looks up the local Host Profile by Installation ID and reuses the existing credentials stored in the Keychain to establish the connection and open the matching Session.

Therefore, the rigorous wording for "zero server-side changes" in a real product evolution should be: there is no need to fork or patch the OpenCode server source, but users are required to install a standard official Plugin on the host machine. If even a Plugin or companion process is completely disallowed from being deployed, then the only path is to push OpenCode officially to support Webhook capability natively at the Core level; relying on the iOS client alone cannot build a highly available background push system.

## First-Version Notification Rules

The first release must never indiscriminately push all server events to the phone; keep the coverage strictly narrow:

| Event | Default behavior | Reason |
|---|---|---|
| `question.asked` | Notify immediately | The AI is explicitly blocked, waiting for input |
| `permission.asked` | Notify immediately | The AI is explicitly blocked, waiting for approval |
| `session.error` | Notify | Human recovery or judgment is required |
| busy/retry → idle | Configurable notification | Valuable, but high-frequency tasks easily create noise |
| message/todo updates | Do not notify | Not attention events, they only update in-app state |

The deduplication key is recommended to be generated from the `host_id + event_type + request_id` composite. When the SSE connection drops and a REST compensating reconciliation is triggered, if the same pending request is scanned again, the system can accurately identify and suppress the duplicate push. After the user finishes handling a Permission or Question, the client should promptly clear the corresponding Badge count; when a notification tap triggers navigation, reuse the existing Session deep link uniformly, and after the app is activated, pull the latest request state from the server in real time — never blindly trust the stale context carried in the push Payload.

## Scope of Change and Difficulty

### iOS client: Medium to small

Within the project we need to configure the Push Notifications capability and the notification permission request flow, complete the generation and reporting of the APNs Device Token, define the foreground notification presentation policy, wire up the notification-tap session routing and Badge cleanup logic, and fill in automated tests. Since the existing Deep Link mechanism and the Attention state model can both be reused directly, the client side is not where the main difficulty lies.

### OpenCode server: Can be zero

By consuming the existing SSE and REST endpoints directly in the Bridge model, there is no need to change OpenCode's interface definitions, event Schema, or the business implementation of any Server node.

### New bridge: Medium

The core workload is concentrated in the long-connection lifecycle management across multiple Hosts, the secure storage of host authentication credentials, the SSE disconnect/reconnect and REST state reconciliation mechanism, event idempotency and deduplication, as well as APNs Token registration and invalidation maintenance. Getting a single-Host validation Demo running is very lightweight, but building a highly available, multi-Host isolated production-grade service is the bulk of the engineering effort for this module.

## Approaches Not Recommended

| Approach | Verdict |
|---|---|
| Only add local notifications on iOS | Can only notify events already received in the foreground, does not solve the problem |
| Use BGTaskScheduler on iOS to poll all servers | Usable as a low-frequency fallback, but untimely, not guaranteed to run, and especially fragile for SSH hosts |
| Connect each OpenCode server directly to APNs | Works, but duplicates the token, private key, and notification rules onto every server, with the highest upgrade and operations cost |
| Modify the OpenCode core to add a push endpoint | Not necessary today; the existing SSE/REST is enough as an event source |
| Replace ordinary push with Live Activity | Does not hold up; remote updates still require push, and question/permission are better suited to ordinary notifications |

## Recommended Validation Order

Step one: first build a single-Host, single-device validation prototype (Spike): the Bridge listens to the existing SSE event stream, filters specifically for `question.asked` events, and successfully delivers one notification carrying a Session deep link to the phone via APNs. This step closes the most critical business loop at the lowest cost, while requiring absolutely no change to the OpenCode server.

Step two: on that basis, extend the notifications to `permission.asked`, `session.error`, task completion, and other events, improve the REST compensating reconciliation and the deduplication logic, and gradually expand support to multiple directly connected Host nodes.

Step three: run dedicated validation for Host topologies that use SSH tunneling or sit in an isolated private network. If the central Bridge cannot connect directly to private-network nodes, deploy a LAN Watcher proxy, and rule out the fragile approach of forcing the iOS client to temporarily establish an SSH tunnel in the background.

Once the step-one prototype runs through, the business scenario can decide whether the Bridge is positioned as a daemon on a user's always-on local Mac, or hosted as a centralized cloud service. This decision only affects the subsequent deployment topology and credential management strategy, and is completely transparent to the communication protocol design between the iOS side and APNs.

## Apple Platform Basis

- [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server): the provider stores the device token and sends requests to APNs.
- [Sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns): the provider sends the payload to `/3/device/<token>` over HTTP/2/TLS.
- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app): background tasks are scheduled by the system, and the background execution window for remote notifications is limited and may be rate limited.
- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes): an ordinary app is usually suspended in the background; remote notifications are just one of the supported, limited background entry points.
