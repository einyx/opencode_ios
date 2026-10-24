# RFC-002: OpenCode iOS Client Technical Design

> Request for Comments · Working Draft · Mar 2026

## Metadata

| Field | Value |
|------|------|
| **RFC Number** | RFC-002 |
| **Title** | OpenCode iOS Client Technical Design |
| **Status** | Working Draft |
| **Created** | 2026-03 |
| **PRD Reference** | [OpenCode_iOS_Client_PRD.md](OpenCode_iOS_Client_PRD.md) |
| **API Reference** | [OpenCode_Web_API.md](OpenCode_Web_API.md) |

---

## Abstract

This RFC proposes the technical implementation plan for the OpenCode iOS Client, delivering the product goals defined in the PRD. The core of the plan is to build a lightweight, SwiftUI-first native client on iOS 17+ that talks to the OpenCode server over HTTP REST and SSE, providing remote monitoring, message sending, and document review. This document focuses on technology selection, architecture design, and key implementation details, serving as the basis for a pre-development review and for reaching a shared understanding.

---

## Background

### Problem

When developers use OpenCode, they often have to sit in front of their computer while the AI completes long-running tasks; once they leave their desk, they can neither keep track of the progress nor correct course quickly. The existing web client relies on a browser and offers a poor mobile experience, while the TUI is bound to a terminal environment and cannot be used directly on a phone.

### Goals

Provide a native iOS client that lets users do the following on a phone or tablet:
- Monitor the progress of AI work
- Send messages and switch models
- View Markdown diffs, primarily for document review
- Abort tasks when necessary, or queue new instructions

### Constraints

- Minimum supported version is iOS 17 (uses the Observation framework)
- The client itself introduces no local AI inference, file system access, or shell execution capabilities
- Supports direct LAN connections, Tailscale MagicDNS, and SSH tunnel remote access; public network environments (non-Tailscale) require HTTPS or SSH forwarding. Tailscale (`*.ts.net`) is configured with an ATS exception exemption and is allowed to use HTTP; in Settings the Tailscale + HTTP protocol label is shown in gray, while every other WAN + HTTP label is shown in red, and the info icon tooltip provides a bilingual (Chinese and English) explanation

---

## Solution

### 1. Overall Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS Client (SwiftUI)                       │
├─────────────────────────────────────────────────────────────────┤
│  Views                 │  State                   │  Services     │
│  ─────────             │  ─────────               │  ─────────    │
│  ChatTab (Views/Chat/) │  AppState (@Observable)   │  APIClient    │
│  FilesTab              │  SessionStore, etc.      │  SSEClient    │
│  SettingsTab           │  (held by one AppState)   │               │
│  MessageRow, DiffView  │                          │               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ URLSession (REST + SSE)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     OpenCode Server (Mac/Linux)                   │
│  GET /global/event  │  POST /session/:id/prompt_async  │  ...    │
└─────────────────────────────────────────────────────────────────┘
```

- **Views**: the SwiftUI view layer, split into Chat / Files / Settings / Split View modules
- **State**: manages connection, session, message, and file state on top of `@Observable`
- **Controllers / Services / Stores / Models / Utils**: a decoupled organization of event control, the network layer, state storage, data models, and the utility layer

### 2. Technology Selection

| Layer | Choice | Rationale |
|------|------|------|
| UI | SwiftUI | A native declarative framework, the best fit for iOS 17+ |
| State | Observation (@Observable) | Replaces ObservableObject and dramatically reduces boilerplate |
| Networking | URLSession | A system-native capability, with no need to pull in Alamofire; SSE is implemented on top of the `Delegate` or `AsyncSequence` of `URLSession` |
| SSH library | Citadel | A wrapper on top of Apple SwiftNIO SSH, supporting Swift 5.10+, with a friendlier API design |
| Markdown | MarkdownUI + custom image provider / resolver | Full support for code blocks, links, and lists, plus resolution of relative-path images inside the workspace |
| Diff | Custom View (preferring native iOS capabilities) | Unified diff rendering with line-level highlighting based on `before`/`after` |
| Persistence | UserDefaults + Keychain | Stores connection configuration and model presets; sensitive passwords go into the Keychain |

#### 2.1 SSH Library Choice: Citadel

Used to implement remote access over an SSH tunnel.

| Library | Language | Maintenance status | Swift version | Recommendation |
|----|------|----------|------------|--------|
| **Citadel** | Swift (built on SwiftNIO SSH) | Active (0.12.0, 2026-01) | 5.10+ | ★★★★★ |
| SwiftNIO SSH | Swift (official Apple) | Active | 6.0+ | ★★★★ |
| NMSSH | Obj-C wrapper of libssh2 | Active | 5.0+ | ★★★ |

**Why Citadel**:

1. **No need to upgrade to Swift 6.0**: it supports Swift 5.10+, avoiding the breaking changes brought by the Swift 6 concurrency-safety checks
2. **High-level API**: it wraps Apple's SwiftNIO SSH, making the calling experience simpler and more intuitive than using SwiftNIO SSH directly
3. **Complete feature set**: full support for Ed25519 key authentication, DirectTCPIP port forwarding, and SFTP
4. **Actively maintained**: 44 releases have been published, with stable support for SSH direct-tcpip port forwarding
5. **Well documented**: it provides clear README examples and [official documentation](https://swiftpackageindex.com/orlandos-nl/Citadel/0.12.0/documentation/citadel)

**Usage example**:

```swift
import Citadel

let settings = SSHClientSettings(
    host: "your-vps.com",
    port: 22,
    authenticationMethod: .publicKey(username: "user", privateKey: ed25519Key),
    hostKeyValidator: .acceptAnything()
)
let client = try await SSHClient.connect(to: settings)

// Local port forwarding: iOS:4096 -> SSH gateway assigned port -> OpenCode
let channel = try await client.createDirectTCPIPChannel(
    using: .init(
        targetHost: "127.0.0.1",
        targetPort: 19001,
        originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 4096)
    )
)
```

### 3. Network Layer Design

#### 3.1 REST API

- A unified `APIClient` is built on top of `URLSession`
- The unified Base URL format is `http://<ip>:<port>` or `https://<host>:<port>`, defaulting to `127.0.0.1:4096`, and is read from the Settings configuration
- When Basic Auth is configured, every request automatically carries the corresponding authentication headers
- Sending messages is recommended via `POST /session/:id/prompt_async`; when the session is busy, the server takes care of the queueing

#### 3.1.1 Message Pagination Fetch (implemented)

- When calling `GET /session/:id/message`, pagination is driven by the `limit` parameter; by default the 6 most recent messages are loaded (equivalent to 3 rounds of user/assistant conversation)
- When the user pulls down at the top of Chat to "load more history", `limit` increases by 6 each time and a new fetch request is issued
- The core goal of this design is to converge the first-screen wait time on weak networks from fetching the "full history" down to loading the "most recent actionable context"
- Note that the unit counted by `limit` is a **message**, not a tool call count; a single assistant message may contain multiple tool/text/reasoning parts

#### 3.1.2 Edit from here / message revert (implemented MVP)

The iOS client supports the message revert MVP, which is shared with the web client, allowing the user to roll back to a given user message in history, refill the original message content into the composer, and send it again after editing.

- Data model: the `Session` model parses the `revert` field returned by the server; its minimal core field set includes `messageID`, `partID`, `snapshot`, and `diff`
- API interaction: `APIClient.revertSession(sessionID:messageID:partID:)` calls `POST /session/:id/revert` with the body `{ messageID, partID? }`, and returns the updated `Session` object
- UI entry point: a new `Edit from here` option is added to the user message menu of `MessageRowView`; when the session is busy this action is disabled automatically, avoiding conflicts with the server-side `assertNotBusy`
- State orchestration: `AppState.editFromMessage(messageID:)` handles only user messages, concatenates the associated text parts and writes them back into the per-session draft of the matching session, updates and inserts the returned session instance, and then refreshes the messages, diff, and file status
- Message visibility: `AppState.visibleMessages(_:revertMessageID:)` follows the display semantics of OpenCode Web, hiding the rolled-back messages where `message.id >= revert.messageID`, while keeping temporary optimistic messages
- Non-goals: the current MVP does not offer `unrevert`, a restore dock, or part-level revert; these may evolve later as needed

#### 3.1.3 Image attachments (Phase 1/2 implemented)

Image support on iOS is designed to be isomorphic with OpenCode Web: images are sent as a `file` part inside the prompt, and the `url` field directly carries `data:<mime>;base64,...`, with no need to introduce a separate file upload endpoint.

- Sending model: `APIClient.promptAsync` supports mixed text and image parts; plain text produces `type: "text"`, while an image produces a structure containing `type: "file"`, `mime`, `filename`, and `url`
- Input control (Composer): `ChatTabView` integrates `PhotosPicker` so users can pick images, up to 4 at a time; the selected images are compressed locally into a JPEG data URL (the longest edge is limited to 2048 pixels, JPEG quality is 0.82), with a 5MB cap per image after compression
- Failure recovery: if the send fails, the composer text and the pending attachments are automatically restored; the optimistic user message also carries the corresponding text part and file part
- Rendering model: the `Part` model is responsible for parsing the `mime`, `filename`, `url`, and `source` fields; `MessageRowView` renders an image thumbnail or a fallback file card for entries where `type == "file"`
- Image preview: tapping an image attachment in a historical message reuses the existing `ImageView` for a zoom and pan preview
- Non-goals: this stage does not cover picking files from the Files App, PDF/text attachment support, persisting attachment drafts across app restarts, or a dedicated server-side upload or chunked transfer of large payloads

#### 3.2 SSE Connection

- Connect to the server event stream endpoint `GET /global/event`
- Perform the streaming read via the `dataTask` of `URLSession` or `URLSession.AsyncBytes`
- Parse the lines that start with `data:`, splitting independent events by line or by the double newline `\n\n`
- The event data format is: `{ directory, payload: { type, properties } }`

**Lifecycle management**:
- Foreground state: establish or resume the SSE connection
- Background state: proactively disconnect to comply with the iOS background execution limits
- Resume flow: on returning to the foreground, first pull the latest data in full through the REST API (health, sessions, messages, status), and then rebuild the SSE connection

#### 3.3 Errors and Reconnection

- Network exception: show a Toast to inform the user; never cause an app crash
- Unexpected SSE disconnect: attempt to reconnect using exponential backoff, with the reconnection interval capped at 30s
- Server unreachable: the Settings page shows the status Disconnected, and the Chat and Files pages show the corresponding placeholder hints

#### 3.4 SSE Robustness

- Data parsing: the server API currently uses the single-line `data:` output format, and the existing parsing logic already satisfies the requirement
- Header configuration: it is recommended to explicitly specify `Accept: text/event-stream` and `Cache-Control: no-cache` in the request
- Reconnection: optional — the existing polling and foreground resume already cover the main scenarios

### 3.5 Host Profiles and Transport Abstraction

The purpose of introducing multi-host support is to decouple "which OpenCode environment to connect to" from "what path is used to reach that environment". A Host represents a specific OpenCode runtime environment, while a Transport represents the underlying network transport path. The Direct transport covers direct LAN connections, Tailscale / VPN, and public HTTPS services; the SSH Tunnel transport is used to reach an internally isolated OpenCode container through an SSH gateway and an assigned remote port.

**Data model (design draft)**:

```swift
struct HostProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var transport: HostTransport
    var serverURL: String
    var basicAuth: BasicAuthConfig?
    var ssh: SSHTunnelConfig?
    var lastUsedAt: Date?
}

enum HostTransport: String, Codable {
    case direct
    case sshTunnel
}

struct BasicAuthConfig: Codable, Equatable {
    var username: String
    var keychainPasswordID: String
}
```

**Persistence boundaries**:

- The `HostProfile` list is kept in UserDefaults or in a lightweight JSON store; sensitive passwords are stored only as a Keychain reference identifier and are never written directly into the JSON data.
- The SSH private key defaults to a device-level key managed centrally by the existing `SSHKeyManager`, with multiple SSH profiles sharing the same public key. The private key is a long-term device identity: it is generated only during the first-run bootstrap (when the Keychain entry is genuinely missing) and when the user explicitly rotates it; the read path fails closed, raising an error instead of regenerating when the Keychain is temporarily unreadable, and the cached public key is validated by deriving it from the private key. If a higher isolation level is needed in the future, a per-profile key override configuration can be layered on top of this.
- The TOFU (Trust On First Use) known host records remain strictly bound to the `host:port` of the SSH gateway rather than to the profile name. When several profiles point at the same gateway, they share one set of trusted host fingerprints.

**Switching flow**:

1. Record and save the current profile's `lastUsedAt` together with the necessary runtime state.
2. Stop the currently active SSE event stream.
3. If the current profile has SSH enabled, proactively tear down the existing SSH tunnel.
4. Load and apply the target profile's `serverURL`, Basic Auth credentials, and transport configuration.
5. Clear the current session selection, then re-fetch the health, projects, and sessions data for the new host.
6. If the new profile uses the SSH Tunnel transport, try to establish the tunnel automatically; if the connection fails it enters the `.error` state, but the Settings interface stays interactive and does not block the user.

**Import Host Config format (no secrets)**:

```json
{
  "version": 1,
  "name": "Yage Private OpenCode",
  "transport": "sshTunnel",
  "serverURL": "127.0.0.1:4096",
  "ssh": {
    "host": "example.com",
    "port": 8006,
    "username": "opencode",
    "remotePort": 19001
  }
}
```

Direct example:

```json
{
  "version": 1,
  "name": "Home Mac via Tailscale",
  "transport": "direct",
  "serverURL": "http://macbook.ts.net:4096"
}
```

The import configuration contains no private key, provider token, or Basic Auth password. After the SSH configuration has been imported, the user is still required to copy this device's public key and submit it to the administrator.

**Host Config export format**:

The Host Config JSON is generated dynamically from the persisted `HostProfile`; the system always treats `HostProfile` as the single source of truth for persistence, and the client never keeps the originally imported JSON as a second copy of state. The exported JSON mainly helps the user and the administrator cross-check the network parameters, so every sensitive key and runtime transient field must be strictly stripped out: the Basic Auth password, the Keychain password ID, the SSH private key, and `SSHTunnelConfig.isEnabled` must not appear in the export result.

**Runtime connection diagnostics**:

```swift
struct ConnectionDiagnostic: Codable, Equatable {
    var hostProfileID: UUID?
    var phase: ConnectionPhase
    var message: String
    var recoveryHint: String?
    var timestamp: Date
}

enum ConnectionPhase: String, Codable {
    case idle
    case sshGateway
    case sshAuth
    case localTunnel
    case health
    case bootstrap
    case connected
    case failed
}
```

`ConnectionDiagnostic` is pure App runtime state and requires no local persistence. It resets automatically on every host switch; afterwards the `testConnection()` test flow and the overall refresh/bootstrap initialization flow are responsible for updating the phase, message, and recovery hint. In the UI, low-level errors must be translated into hints that the user can understand and act on; raw low-level error strings such as `APIError error 0` or `NSURLErrorDomain -1004` must never be shown directly. The common mapping rules include: a Basic Auth 401/403 maps to checking the username and password; connection refused / cannot connect maps to checking the server address, the current network connection, or the local tunnel state; and an SSH tunnel error maps to checking the gateway status, the device public key configuration, and the assigned remote port.

**Host Detail interaction contract**:

The primary interaction when tapping an item in the Hosts list is to enter the Host Detail page, rather than directly triggering a host switch. Switching hosts must be done explicitly on the detail page by tapping the `Use This Host` button. Host Detail fully displays the key parameters of Direct or SSH Tunnel according to the current `HostProfile` configuration, and offers a `Copy Host Config JSON` action; for SSH Tunnel profiles the page additionally provides a convenient `Copy This Device Public Key` entry point.

### 3.6 SSH Tunnel Architecture

Primarily used in remote access scenarios, using an SSH gateway as an intermediate hop to securely forward to the user's own OpenCode instance.

**Network topology**:

```
┌─────────────┐      SSH Tunnel       ┌─────────────┐      internal      ┌─────────────┐
│  iOS App    │ ───────────────────▶  │  Gateway    │ ─────────────────▶ │  OpenCode   │
│ 127.0.0.1   │   DirectTCPIP         │ 127.0.0.1   │ (pre-established)  │ OpenCode    │
│   :4096     │   :4096 → :19001      │   :19001    │                    │   :4096     │
└─────────────┘                       └─────────────┘                    └─────────────┘
```

**Data model**:

```swift
struct SSHTunnelConfig: Codable {
    var isEnabled: Bool = false
    var host: String = ""           // SSH gateway address
    var port: Int = 8006            // SSH port
    var username: String = "opencode" // SSH username
    var remotePort: Int = 19001     // admin-assigned remote port
}

enum SSHConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

**Key management**:

```swift
enum SSHKeyManager {
    // Generate an Ed25519 key pair
    static func generateKeyPair() throws -> (privateKey: Data, publicKey: String)
    
    // The private key is stored in the Keychain (both read and write propagate OSStatus; loadData returns nil only on errSecItemNotFound)
    static func savePrivateKey(_ key: Data) throws
    static func loadPrivateKey() throws -> Data?
    
    // The public key is used for display/copying (read-only, never generated; a consistency check runs first)
    static func getPublicKey() -> String?
    
    // Read-only accessor: validates that the cached public key is really derived from the private key, and repairs the cache from the private key when they do not match;
    // throws SSHError.keyUnavailable when the Keychain is temporarily unreadable, and SSHError.keyNotFound when the private key does not exist
    static func getKeyPair() throws -> String

    // Bootstrap: generates a new key pair only when the private key entry is genuinely missing (errSecItemNotFound);
    // other Keychain errors throw SSHError.keyUnavailable and leave the stored key untouched
    static func ensureKeyPair() throws -> String

    // Key rotation (the only generation path triggered explicitly by the user)
    static func rotateKey() throws -> String  // returns the new public key
}
```

**Security considerations**:

1. **Private key protection**: it is stored with the `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` strategy and is readable after the first unlock (including while the screen is locked), which supports background connections after a reboot, and it does not migrate to other devices through iCloud Keychain; the save/load of `KeychainHelper` propagate OSStatus, and write failures are no longer silently swallowed
2. **Public key transfer**: it relies on the user copying and pasting manually; the app never uploads the public key through any network interface
3. **TOFU**: the first connection automatically trusts and stores the server fingerprint (bound by host:port); a later mismatch fails immediately with a prompt to reset the trusted host
4. **Timeout**: a 30 second connection timeout, after which the connection is dropped automatically with a prompt

**Error handling**:

| Error | Cause | User-facing message |
|------|------|----------|
| Key not authorized | The public key has not been added to the VPS | "Please add the public key to the server's authorized_keys first" |
| Connection timeout | A network problem or a wrong address | "Connection timed out, please check your network and the server address" |
| Authentication failed | The private key does not match | "Authentication failed, please make sure the public key has been added correctly" |
| Key temporarily unavailable | The Keychain is temporarily unreadable (e.g. while the device is locked) | "The SSH key is temporarily unavailable. Please unlock the device and try again" |

**SSH UX additions**:
- Provide a setup guide inside the Settings page: it walks the user through copying the device public key to the administrator and entering the assigned remote port returned by the administrator
- The public key copy entry point is always present and does not depend on the tunnel enable state
- The `Test Connection` of an SSH Host Profile first establishes the SSH tunnel and waits for the local `127.0.0.1:4096` listener to become ready; only after the tunnel is ready does it request `/global/health`
- When the tunnel fails to be established, the SSH error is written into the connection error, so that only "disconnected" is not shown

### 3.7 Markdown Image Resolution Contract

Images referenced in Markdown text usually fall into two categories:

1. **Public URLs**: those starting with `https://...` can be handed straight to the system's standard network image loading path
2. **Relative images inside the workspace**: for example `../assets/timeline_40d.png`; these must be path-resolved and fetched by the client itself

For the second category, the RFC imposes the following constraints:

- Both the Files preview and the Chat message rendering must support relative images inside the repo; the dual semantics of "visible in the file preview but invisible in the chat" is not allowed
- When resolving a relative image path, the calculation must combine the current document path `markdownFilePath` with the workspace root directory `workspaceDirectory`
- The final request parameter after the path normalization must be a **workspace-relative path**, which is then passed to the `/file/content` API to fetch the content
- In the Chat rendering scenario it is allowed to pre-convert the image content into a `data:` URI before handing it to MarkdownUI; but if that approach is taken, the rendering side must explicitly mount an image provider that can handle `data:` URLs
- If the Files preview uses `imageBaseURL`, the workspace-relative normalization must still be applied in the image provider, so that absolute paths do not leak into the API layer

The goal of this contract is that whether the same Markdown report is opened from Files or output directly by the AI in Chat, it should yield consistent image results.

### 4. State Management

```swift
@Observable
final class AppState {
    var hostProfiles: [HostProfile]
    var currentHostProfileID: UUID
    var serverURL: String          // the runtime URL after the current profile is expanded
    var isConnected: Bool
    var sessions: [Session]
    var currentSessionID: String?
    var sessionStatuses: [String: SessionStatus]
    var messages: [MessageWithParts]
    var partsByMessage: [String: [Part]]
    var selectedModelIndex: Int
    
    // Agent selection (added 2026-02)
    var agents: [AgentInfo]           // fetched from GET /agent
    var selectedAgentIndex: Int       // the currently selected agent
    
    // SessionStore, MessageStore, FileStore, TodoStore, etc.
}
```

- A single `AppState` holds the global state, while the individual business sub-stores take over the domain logic for session/message/file/todo and so on
- SSE events are dispatched by their `type`, updating the related state fields in real time
- The SwiftUI View layer can access the state objects through `@Environment` dependency injection or explicit parameter passing

#### 4.1 Agent Data Model

```swift
struct AgentInfo: Codable, Identifiable {
    var id: String { name }
    let name: String              // agent name, e.g. "Sisyphus (Ultraworker)"
    let description: String?      // description
    let mode: String?             // "primary" or "subagent"
    let hidden: Bool?             // whether it is hidden (hidden agents are not shown in the UI)
}
```

#### 4.2 Agent API

| Method | Path | Description | Response |
|------|------|------|------|
| GET | `/agent` | List all agents | `AgentInfo[]` |

- This API is called in the background at app startup to fetch the agent list
- The agents with `hidden != true` are filtered out before being shown in the UI
- The first primary agent is selected by default (usually `Sisyphus`)

#### 4.3 Project Selection (Workspace Filter)

**Background**: OpenCode Server supports multiple projects, and `GET /session` returns the sessions of the server's current project by default. The web client can switch projects, so the iOS client needs to support filtering by project; otherwise it can only see the sessions of the server's current project.

**API**：

| Method | Path | Description | Response |
|------|------|------|------|
| GET | `/project` | List the projects known to the server | `Project[]` |
| GET | `/project/current` | Current project | `Project` |
| GET | `/session?directory=<path>&limit=<n>` | Filter the sessions by worktree | `Session[]` |

**Data model**:

```swift
struct Project: Codable, Identifiable {
    let id: String           // usually a git commit hash
    let worktree: String     // absolute path, e.g. /Users/xxx/co/knowledge_working
    let vcs: String?         // "git" etc.
    let time: ProjectTime?
}

// Display name: the last segment of the worktree, e.g. knowledge_working
func projectDisplayName(_ worktree: String) -> String {
    (worktree as NSString).lastPathComponent
}
```

**State**:

```swift
var projects: [Project] = []              // fetched from GET /project
var selectedProjectWorktree: String?      // nil = use the server default (do not pass directory)
var customProjectPath: String = ""        // the path entered by the user when "Custom path" is selected
```

**Flow**:
1. After a successful connection, call `GET /project` to populate the Picker
2. User selection: pick from the list → `selectedProjectWorktree = project.worktree`; pick "Custom path" → expand the TextField, `selectedProjectWorktree = customProjectPath`
3. When calling `loadSessions()`: if `selectedProjectWorktree != nil`, request `GET /session?directory=xxx&limit=100`; otherwise issue a parameterless `GET /session` request
4. Persistence: `selectedProjectWorktree` and `customProjectPath` are stored in UserDefaults

#### 4.3.1 Session Creation Limited to the Server Default

**Background**: `POST /session` does not accept a directory, and the server creates the session under its current project (determined by the launch location or by the last use in Web/TUI). The Project selector on iOS only affects list filtering and does not change the creation target. If creation were allowed while a specific project was selected, the new session would land in the server default and would not appear in the filtered results, making it disappear.

**Implementation**: creation is allowed only when `effectiveProjectDirectory == nil` (the user selected Server default). When the user has selected a specific project, the new-session button is greyed out and an info icon is placed next to it; tapping it shows a hint: you need to launch OpenCode from the command line with a different working directory, and then select Server default here and create the session. `canCreateSession` controls whether the button is enabled.

#### 4.4 Session Deep Link

**Protocol**: V1 only accepts `opencode://session/<session_id>`. `OpenCodeDeepLinkParser` is a pure function with no side effects, requiring the scheme and host to be `opencode` and `session` respectively, the path to consist of exactly one segment, and the session ID to start with `ses_` followed only by ASCII letters, digits, underscores, or hyphens. The parser rejects userinfo, port, query, fragment, multi-level paths, control characters, Unicode, duplicate percent encoding, and overlong IDs. Unknown schemes are not handled by the deep-link router.

**Implementation layering**:

- `Utils/OpenCodeDeepLink.swift` defines the URI contract and the parser.
- `AppState+DeepLinks.swift` holds `pendingDeepLink`, `deepLinkRouteState`, the global error, and the route generation token.
- `ContentView.onOpenURL` handles the system cold/warm launch; the `OpenURLAction` of `MessageRowView` first recognizes OpenCode links and then falls back to the existing HTTP/workspace link resolver.
- `Info.plist` registers the `opencode` scheme through `CFBundleURLTypes`; Debug and Release share the same configuration.

**Parsing state machine**:

```text
receive URL
  -> strict parse
  -> store latest pending route
  -> wait while disconnected
  -> GET /session/:id on current Host
  -> apply target directory + upsert session
  -> select session + hydrate Chat + reload Files
```

The client must preserve the original `currentSessionID` and messages until `GET /session/:id` succeeds. The target session is not required to be inside the current 100-entry list window; after validation, first set the known project or the custom project according to `Session.directory`, then upsert and call the existing session hydration. Refreshing the session list must retain the currently validated session, and the Files root/children requests use `effectiveProjectDirectory`.

**Lifecycle and concurrency**: during a cold launch or an SSH recovery, only the pending route is stored and is consumed once the connection succeeds. When the app enters the background or the Host is switched, the generation token is updated so that the in-flight responses of the old Host become invalid, while the last pending link is preserved for the new connection to handle. A new link overwrites an old one instead of forming a queue; repeatedly tapping the same session is idempotent. A 404 shows "the current Host is unavailable", while other network errors show a generic open failure; neither of them switches the context.

**Security boundary**: the URL accepts no server, Host Profile, credentials, model, prompt, tool action, or arbitrary command. A deep link can only be triggered by a user tap or an explicit system invocation, and must never be auto-executed as a result of Markdown rendering. V1 does not search across Hosts, does not restore an offline archive DB, and does not support `?message=`.

**Verification**: unit tests cover the parser allowlist, 404/disconnect, project switching, list window retention, and route invalidation; a fixture XCUITest covers the assistant Markdown tap and the cold pending route. Full system acceptance uses the Simulator `simctl openurl` and an independent temporary server, without touching the live `4096`. The agent search output is separately verified with a synthetic archive covering the source, the frontmatter session ID, candidate de-duplication, and evidence adjacency; the real agent acceptance stays opt-in and is not part of every unit test.

### 5. Messages and Document UI

#### 5.1 Message Stream

- **Layout**: OpenCode style, with no left/right bubbles; human messages have a gray background, AI messages are white/transparent
- **Unit semantics**: one message may contain multiple parts (tool/reasoning/text etc.). A tool call counts as a part and is not counted as a separate message
- **Part rendering**: text (Markdown), reasoning (collapsed), tool (card), patch (jump to Files). If a tool/patch contains a file path, tapping it opens a preview via "Open in File Tree"; the `todowrite` tool in particular must be rendered as a Task List (todo) view and must respond to the SSE `todo.updated` event. Todos are shown only inside the tool card and are not pinned at the top of Chat (option B)
- **Image-like tool output**: if the tool result is linked to an image file, render an inline thumbnail rather than the raw base64; tapping it opens a zoomable full-screen preview
- **iPad large-screen density**: when `horizontalSizeClass == .regular`, the tool/patch/permission cards may fill the width in a three-column grid; the text parts still span the full row (to avoid breaking up the reading)
- **Streaming (Think Streaming)**: when `message.part.updated` carries a `delta`, append it to the corresponding Part to get a typewriter effect; without a delta, reload in full. Tool cards: expanded while running, collapsed by default when completed
- **Auto-scroll**: follow the new streaming text and card updates only when the user is currently near the bottom; stop auto-following when the user scrolls up, so that the reading position is not stolen
- **Activity Row convergence**: the status display follows "running evidence first". If a running/pending tool or a streaming delta is detected, the state stays running even if `session.status=idle` arrives momentarily, avoiding a premature completed state
- **Theme**: follows `@Environment(\.colorScheme)`, Light/Dark

#### 5.1.1 Chat Text Selection (textSelection) — Design

**Principle**: enable the selection only for two kinds of content and disable it everywhere else, to avoid gesture conflicts and to narrow the selectable range.

| Area | Selectable | Description |
|------|----------|------|
| User message body | ✅ | The messages the user sent, which can be copied |
| AI final reply (text part) | ✅ | The AI's response text, which can be copied |
| Reasoning | ❌ | Including the think output while streaming |
| Tool calls (tool cards) | ❌ | Reason, Command/Input, Output, Path, todo, etc. |
| Patch cards | ❌ | Mostly buttons, no need for a selection |

**Implementation**: the `markdownText` of `MessageRowView` uses `.textSelection(.enabled)` for the user messages and the AI text parts; the `ScrollView` sets no global textSelection; `ToolPartView`, `StreamingReasoningView`, and `TodoListInlineView` do not enable textSelection.

#### 5.1.2 Think Streaming Implementation

- **Delta handling**: when `handleSSEEvent` receives `message.part.updated`, if `properties.delta` exists it locates the Part matching `messageID`/`partID` and appends the delta to the text; otherwise it performs a full refresh through `loadMessages()`
- **Tool collapse**: `ToolPartView` follows `part.state.status`: `isExpanded = true` while `running`, and `isExpanded = false` (the default) when `completed`; the user can toggle it manually
- **Limitation**: real-time streaming of the tool output (terminal, line by line) is not supported by the current API; see the PRD research

#### 5.2 Document Review

- **Markdown display**: Preview by default, with a switch to the Markdown source
- **Diff highlighting**: prefer highlighting the changes inside the Preview; if that turns out to be hard to implement, highlight them inside the Markdown instead
- **Entry point**: Files Tab → select a file → preview
- **Image preview**: the file preview and the tool output share a single image branch; it starts fit-to-screen and supports pinch, drag, double-tap zoom, and the system share sheet

### 6. Permissions and Input

- **Session list**: lists all the existing Sessions under the workspace, serving as a means of validating the connection and the parsing
- **Session list styling**: avoid the system default link blue; use neutral colors for the text, and highlight the current Session with a background
- **Permissions**: when `permission.asked` arrives, show a card for the user to manually approve/reject by calling `POST /session/:id/permissions/:permissionID`
- **Question**: when `question.asked` arrives, show a question card; at startup, pull the pending questions through `GET /question`; answering and rejecting call `/question/{id}/reply` and `/question/{id}/reject` respectively
- **Composer**: uses a two-row `voice rail + text review field` structure. The voice rail on top carries the voice transport, the waveform/status, the transcription wait recovery, and the preserved-audio retry; the text review field below carries the transcribed text, the manual corrections, the fallback typing, and the fixed send button. When the voice transcription or the preserved-audio retry streams back a partial transcript, the text review field auto-scrolls to the end so that the latest text stays visible; ordinary manual input and draft restoration do not force a scroll. When busy, the send button still calls `prompt_async`, and the message is queued by the server
- **Drafts**: the unsent input is persisted per sessionID; it can be restored when switching sessions; it is cleared after a successful send
- **Model selection**: the currently selected model is remembered per sessionID and is restored automatically when switching sessions (avoiding a global model override)
- **Agent selection**: the currently selected agent is remembered per sessionID (same as with the model); the `agent: string` field is carried in the body when sending a message
- **Voice input**: when the recording starts, a VoiceFlowKit realtime session is created and `AVAudioEngine` outputs PCM16 mono 24kHz chunks; the Kit writes each chunk into a temporary `.pcm` cache and sends it over the current WebSocket. During the recording the voice rail waveform consumes the real smoothed 0..1 mic level from `VoiceFlowMicrophone.audioLevel`. A heartbeat / send failure triggers the Kit recovery: cancel the bad session, create a new session, replay sequentially from offset 0 of the cache file to the end of the current file, and then continue sending live. When the recording stops, wait for the recovery to finish, send `commit` / `stop`, and append the transcript to the text review field. While waiting for the transcription, a processing waveform and `Stop transcription wait` are shown; tapping it calls `abortPreservingAudio()` to release the UI immediately while preserving the cache; in the preserved-audio state the left transport shows a `Retry this segment` icon button, which re-transcribes the same PCM segment through `transcribe(preservedAudio:)`, and the right action shows `Discard audio` to abandon the cache and leave the recovery state. After a failed retry the cache is preserved, and the user can retry again or discard. The Base URL and token are configured under Settings → Speech Recognition and are also kept in the Keychain
- **Agent abort**: `Interrupt agent` is a `⋯` menu item on the composer status row that calls `POST /session/:id/abort`. It is a low-frequency escape hatch and does not share the transport slot or the stop glyph with the voice transcription recovery
- **History loading interaction**: the top of Chat shows a "pull down to load more history" hint; while loading it shows "loading more history...", with Chinese and English localization. Loading more works by widening the window of `GET /session/:id/message?limit=`, and records the requested limit, the number of messages returned, and the number dropped by the fallback decoder, which makes it easier to investigate the imperceptible pagination problem caused by older message shapes. The `files` field of a message part is compatible with both string arrays and objects that lack a diff count, so that old patch/tool records do not block the display of earlier history.
- **Session Archive**: the Session List is displayed in two sections, Active / Archived. The archive semantics reuse `PATCH /session/:id`: Archive writes a positive archived timestamp, while Restore writes `-1` as the legacy restore sentinel; the client treats a session as Archived when `time.archived > 0`. The client does not treat archive as a variant of delete. After a successful Archive / Restore, the local list is updated with the returned `Session` and the Active / Archived sections are recomputed. Archive applies recursively to the session subtree, in children-first, parent-last order, which avoids the parent session being hidden first while the active children are temporarily promoted to root; Restore uses parent-first, children-after order, which avoids a child session temporarily floating free while the parent is still archived. The iPhone sheet and the iPad sidebar use the same set of rules: the leading swipe is Archive/Restore and the trailing swipe is Delete; all swipe actions disable the full swipe, and Delete shows no confirmation dialog. The session list pagination uses an explicit "Load more sessions" row instead of an automatic bottom `onAppear` load, so that collapsing the archived section by default does not pull in a large amount of invisible historical sessions. This round provides no session search, to avoid a local title filter being mistaken for a full-history search.

#### 6.1 Fork Session (session forking)

The "..." menu next to the model label at the bottom of a user message offers a "Fork from here" option. It calls `POST /session/{id}/fork` (body: `{ "messageID": "..." }`), and the server copies all the history before the given message into a new session and returns it. After receiving the new `Session`, the client inserts it at the top of the list and switches to it.

**Implementation notes**:
- Use a SwiftUI `Menu` (triggered by a tap, not by a long-press `.contextMenu`), ensuring the button is discoverable
- `MessageRowView` gains an `onForkFromMessage: ((String) -> Void)?` callback that passes `message.info.id` to `AppState.forkSession(messageID:)`
- `AppState.forkSession()` follows the `createSession()` pattern: guard `isConnected` + `currentSessionID`, call the API, insert the session, switch, load the messages
- The title of a forked session is generated by the server: "{original title} (fork #N)"

### 7. Files and Diff

- **File tree**: `GET /file?path=` displayed recursively; `GET /file/status` fetches the git status for the color marking
- **Content**: `GET /file/content?path=`; text files are shown in a monospaced code view with line numbers; Markdown uses a Preview / source toggle; image files support an interactive preview and system sharing
- **Session Diff**: not shown in the iOS client for now (the server-side diff API returns an empty array in some cases)

### 7.5 Markdown Web Preview Architecture Decision

Opening a `.md` file shows cards, SVG, and dark mode adaptation, not just plain text. All rendering happens locally on iOS, with no network access and no author code being executed.

<style>
.rfcw-stat{display:inline-block;border-radius:999px;padding:1px 8px;font-size:.78rem;font-weight:650}
.rfcw-stat.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.rfcw-stat.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

| What the user can experience | Status |
|---|---|
| Opening a markdown file shows the Web Preview by default, and the toolbar can switch back to Native / source | <span class="rfcw-stat ok">Shipped</span> |
| `<style>` / `<div class="card">` / inline SVG render correctly | <span class="rfcw-stat ok">Shipped</span> |
| Relative-path images can be loaded | <span class="rfcw-stat ok">Shipped</span> |
| The same file is readable in both light / dark modes, with no muddy cards | <span class="rfcw-stat ok">Shipped</span> |
| Dangerous HTML (scripts, forms, cross-site iframes) is stripped and not executed | <span class="rfcw-stat ok">Shipped</span> |
| Switching files refreshes the content immediately, with no manual pull-to-refresh | <span class="rfcw-stat ok">Shipped</span> |
| Very large files prompt for confirmation first, to avoid hanging | <span class="rfcw-stat ok">Shipped</span> |
| Opening standalone `.html` artifacts, Mermaid, code highlighting, and image zoom | <span class="rfcw-stat block">Next round</span> |

<details>
<summary>Implementation notes (expand for engineering readers)</summary>

- **Rendering path**: `MarkdownWebPreviewView` (a `UIViewRepresentable` wrapping `WKWebView`) loads `preview.html` from the app bundle; Swift calls `window.renderMarkdown({markdown, theme})` through `evaluateJavaScript`, and the payload goes through `JSONSerialization` instead of string-concatenating the markdown.
- **JS dependencies**: `markdown-it@14.2.0` + `DOMPurify@3.4.10` + `Temml@0.13.4` are pinned into the bundle, with zero CDN calls. Temml converts `$...$` / `$$...$$` into MathML at the markdown-it token stage, and that MathML then enters the sanitizer together with the rest of the HTML. Xcode flattens the subdirectories of a synchronized folder, so the vendored files sit next to `preview.html` and the src has no `vendor/` prefix.
- **Image resolution**: reuse `MarkdownImageResolver.resolveImages` to turn the relative images into `data:` URIs and hand them to the WebView — semantically consistent with the §3.7 Markdown Image Resolution Contract.
- **Security model**: Temml uses `trust: false` together with bounded macro/size configuration; the MathML it generates does not bypass the sanitizer. DOMPurify uses an explicit HTML/SVG/MathML allowlist and blocks `script` / `iframe` / `form` / `object` / `embed` / `on*` event attributes / `javascript:` URLs; `WKNavigationDelegate` intercepts every navigation except file / fragment; external links are handed to the system Safari, while workspace-relative links go through `state.fileToOpenInFilesTab`; `WKWebsiteDataStore` is non-persistent, with no persistent cookies / localStorage.
- **Theme adaptation**: the shell exposes CSS variables such as `--fg` / `--bg` / `--card-bg` / `--border` / `--link` / `--ok-*` / `--bad-*` / `--warn-*` / `--block-*`, with one set of definitions for light / dark. Author styles must use the `var(--x, fallback)` form; the renderers that do not support theme variables (Cursor, GitHub) fall back to the fallback. In Dark mode the chips use a saturated primary color (`--ok-bg=#10b981` etc.) to avoid sinking into the card on a dark background. A chip must use the compound selector `.vx-chip.ok`; a bare `.ok` is overridden by the card's `color:var(--fg)`.
- **Switch refresh**: `FileContentView` actively resets the content and reloads on `.onChange(of: filePath)`, so that a stale file does not linger when SwiftUI reuses a view instance.

</details>

The complete sub-project PRD / RFC is kept on disk at `docs/archive/2026-06_markdown_web_preview_prd.md` / `2026-06_markdown_web_preview_rfc.md` and has been removed from git tracking; see [`WORKING.md`](WORKING.md) for the decision process.

### 8. iPad / Vision Pro Layout (Phase 3)

- **Condition**: enabled when `horizontalSizeClass == .regular` or `userInterfaceIdiom == .pad`
- **Layout**: no Tab Bar; three columns (NavigationSplitView): the left column is Workspace (Files + Sessions), the middle column is Preview (the file preview), and the right column is Chat (the message stream + the composer)
- **Column widths**: Workspace takes about 1/6; Preview and Chat split the remaining 5/6 evenly (5/12 each)
- **Draggable**: the three column widths can be adjusted by dragging; the above are the default ideal widths
- **File preview**: no sheet is used on iPad. Selecting a file in the left column, or tapping the file path of a tool/patch in Chat, updates the Preview in the middle column with the corresponding file
- **Refresh**: the top-right of the Preview column provides a refresh button (reloading the file content) for a manual refresh after an external change
- **Toolbar**: the first row is unified: left (session list, rename, Compact, new session) + right (model dropdown, agent dropdown, Context Usage ring, **Settings button**); tapping Settings opens it as a sheet
- **Model and agent selectors**: the original horizontal chip scrolling is replaced by dropdown lists (Menu + Picker). The model list is fixed (GLM-5.1 / GPT-5.4 / GPT-5.3 Codex / DeepSeek); the agent list is fetched dynamically from `GET /agent` (filtering out the hidden ones)
- **Model labels**: on iPhone the short names are used (`GLM` / `Opus` / `GPT` / `Gemini`) to fit the narrow width; on iPad the full names are shown
- **Implementation**: the `@Environment(\.horizontalSizeClass)` branches: on regular it renders the three-column split, and on the small screens it renders a `TabView`; iPad drives the middle-column preview through `previewFilePath`, while iPhone keeps `fileToOpenInFilesTab` for the sheet / tab navigation

### 9. Context Usage

- **Display**: shown at the top right of Chat (between the model switch bar and the gear) as a ring progress indicator (a gray empty ring means there is no data).
- **Data**: the token/cost are read from `info.tokens`/`info.cost` of the most recent assistant message; the context limit comes from `limit.context` in `GET /config/providers`.
- **Interaction**: tapping the ring opens a sheet showing the provider/model, the context limit, the total tokens, the token breakdown (input/output/reasoning/cache read/cache write), and the total cost.
- **Always visible**: the ring is always displayed in every state, whether idle, busy, or streaming. `ChatTabView` does not inject a `ProgressView` into `.navigationBarTrailing`; the busy state is already conveyed by the red stop button in the input bar, and the toolbar spinner has been removed.

### 10. Car Mode Technical Design (Foreground Phase implemented)

#### 10.1 Components and Platform Gating

Car Mode is only shown on the iPhone compile path and under the iPhone runtime idiom. `isCarModeEnabled` is persisted in UserDefaults and defaults to `false`; the Settings toggle and the Car Tab use the same condition. iPad, the iPad compact window, and visionOS do not expose an entry point at all.

Main components:

- `AppState+CarMode.swift`: the session lifecycle, turn state, structured response, and exactly-once state.
- `Models/CarMode.swift`: the versioned response envelope and the JSON Schema.
- `Views/Car/CarModeView.swift`: the recording, waiting, speaking, confirmation, and failure UI.
- `CarSpeechOutputService.swift`: Apple TTS and the AudioSession switching.
- `CarClientActionDispatcher.swift`: the typed Maps action allowlist; the Health action is handled by a separate capability dispatcher.
- `APIClient.promptStructured(...)`: a synchronous `POST /session/:id/message` wrapper.

#### 10.2 Structured Prompt Contract

Every turn explicitly carries `system` and `format: json_schema`, and always uses the `build` agent together with `openai/gpt-5.6-sol-fast`. The server validates through the StructuredOutput tool and writes the result into `assistant.structured`. The client never infers an action from a natural-language text part, nor does it treat a structured assistant's `finish == tool-calls` as a failure.

Minimal envelope:

```json
{
  "version": 1,
  "status": "completed",
  "speech": "The garage door is closed, the status was just updated.",
  "confirmation": null,
  "clientActions": []
}
```

When a confirmation is needed, `status` is `needs_confirmation` and carries a stable confirmation ID; when the navigation is complete, at most one typed action is returned:

```json
{
  "version": 1,
  "status": "completed",
  "speech": "Opening the navigation to Bright Horizons.",
  "confirmation": null,
  "clientActions": [
    {
      "id": "route-1",
      "type": "open_navigation",
      "destination": "Bright Horizons, Bellevue",
      "waypoints": []
    }
  ]
}
```

The schema constrains the version, the status, the speech length, the number of actions, and the action types. The system prompt constrains the speech to lead with the conclusion, to contain no Markdown/URLs/code, to default to 8-12 seconds and never exceed 15 seconds, and declares that only user messages may authorize real-world side effects.

#### 10.3 Session Lifecycle and Archive Restoration

The Car session key is `hostProfileID + effectiveProjectDirectory`, separate from the `currentSessionID` of an ordinary Chat. Locally it records:

```text
sessionID
lastHandledAssistantMessageID
pendingConfirmationID
lastUsedAt
```

Every turn calls `ensureCarSession()`:

1. When there is no record, create a `Car Mode` session and save it.
2. When there is a record, call `GET /session/:id`; on a 404, clear the record and create one new session.
3. When the session's `time.archived > 0`, call `PATCH /session/:id` with `{ "time": { "archived": -1 } }`, using the legacy restore sentinel already accepted by the server to restore the iOS Active state, and then keep using the original session.
4. No forking, no copying of history, and no modification of the server for the Web global list. OpenCode Web may require `archived === undefined`, so the cross-client visibility of `-1` is not part of the Car Mode guarantees.

Switching to the background, switching tabs, or opening Maps stops the recording, the TTS, and the current foreground request, but does not clear the session ID. The current context mapping is removed only when the user explicitly chooses New Car Session.

#### 10.4 Turn State and Exactly-Once

```text
idle
→ recording
→ finalizing
→ waitingReply
→ speaking / awaitingConfirmation / failed
→ idle
```

Only the VoiceFlow final transcript is submitted automatically. A response must simultaneously satisfy the target session, the assistant role, `time.completed != nil`, a decodable version 1 structured envelope, and a non-empty speech. The client de-duplicates the TTS/actions by the assistant message ID and correlates the next turn by the confirmation ID. When an active turn is cancelled, the TTS is stopped and `POST /session/:id/abort` is called on a best-effort basis.

The current Foreground Phase uses a synchronous endpoint and obtains the final assistant directly; the asynchronous `prompt_async → SSE → reload` path of an ordinary Chat does not reuse this state machine. A future asynchronous version must still preserve the above completion predicate and the exactly-once IDs, and must not trigger the speech or an action based on `session.status == idle` alone.

#### 10.5 Audio and Client Action

After the VoiceFlow finalization completes, the recording AudioSession is released first, and then the TTS service switches to `.playback` + `.spokenAudio`. This avoids sound lingering on the receiver or the Bluetooth HFP route. The current playback is stopped when the recording starts or is cancelled.

`open_navigation` is validated by the Maps dispatcher for the destination/waypoints and constructs an Apple Maps URL. `health_quantification.export_all` uses a separate local authorization, a Pending/Outbox, and a callback continuation; the formal technical contract is in [`features/client_capabilities/rfc.md`](features/client_capabilities/rfc.md) and [`features/client_capabilities/protocol.md`](features/client_capabilities/protocol.md). Neither action accepts an arbitrary URL supplied by the model.

#### 10.6 Server Contract and Verification Evidence

Car Mode does not maintain an archive-list server patch. The only independent server compatibility fix is the wire schema of the structured user message `info.format`, which allows `GET /session/:id/message` to read the persisted structured turns; that fix lives in the nested checkout commit `43a4a0e53` and is unrelated to the Car session active-list behavior.

The 2026-07-13 live spike has verified: a synchronous structured speech returns a valid object; the second turn in the same session retains the destination of the previous turn; and a turn can still end with a structured final after a tool execution. It only proves the generic tool → structured chain, and does not prove that Smart Home, email, iMessage, or route-duration have been registered, authorized, or completed in a real E2E.

The client verification covers the unit state flow, the structured history fallback, the iPhone experiment toggle and the Car UI, the hidden iPad entry points, and the visionOS build. The tests consistently use a serial `xcodebuild` with `-parallel-testing-enabled NO`.

---

## Implementation Plan

| Phase | Scope | Estimated cycle |
|-------|------|----------|
| 1 | Server connection, SSE, session, message sending, streaming rendering | 2–3 weeks |
| 2 | Part rendering, manual permission approval, theming, `prompt_async` | 2 weeks |
| 3 | File tree, Markdown preview, document Diff, Think Streaming delta, **iPad/Vision Pro split layout** | 2–3 weeks |
| 4 | mDNS, Widget, etc. | Not implemented for now |

### Code Review Follow-ups (2026-02)

| Number | Status | Description |
|------|------|------|
| 2.1 | ✅ | Persist the credentials with UserDefaults + Keychain |
| 2.2 | ✅ | Chat text selection — only the user messages + AI text parts are selectable, see RFC §5.1.1 |
| 2.3 | ✅ | ChatTabView split into Views/Chat/*.swift |
| 2.4 | ✅ | Todo option B: shown only inside the tool card |
| 2.5 | ✅ | Remove the debug print |

---

## Rejected Approaches

The following approaches were dropped during the discussion:

1. **Using Alamofire**: `URLSession` is sufficient, and adding a new dependency is unnecessary
2. **A permanently resident background SSE**: iOS actively disconnects it and it drains the battery; switch to establishing it in the foreground and disconnecting it in the background
3. **A local message queue**: the server-side `prompt_async` already supports queueing while busy, so the client does not need to maintain one
4. **Automatic permission approval**: OpenCode very rarely requests a permission, so an occurrence is abnormal; switch to manual approval

---

## Decided Items

1. **Markdown library**: use MarkdownUI, preferring native iOS capabilities
2. **Large sessions**: not considered for now; no session is expected to exceed a hundred messages
3. **Diff highlighting**: implement it with native iOS capabilities first

---

## Appendix: Correspondence with the PRD

| PRD section | Corresponding part of this RFC |
|----------|-------------|
| 3. Technical architecture | §1 Overall architecture, §2 Technology selection |
| 4.2 Chat Tab | §5 Messages and document UI, §6 Permissions and input |
| 4.3 Files Tab | §7 Files and diff |
| 5. Data flow and state management | §4 State management, §3 Network layer |
| 11. Getting started guide | §Implementation Plan |
