# App Store listing metadata

Everything the App Store Connect listing needs for **OpenCode Remote**. Fill in
the `TODO` items and paste the rest into App Store Connect.

## Identity

| Field | Value |
|---|---|
| App name (30 chars max) | `OpenCode Remote` |
| Subtitle (30 chars max) | `Your OpenCode server, on your phone` |
| Bundle id | `com.prysm.opencode` |
| SKU | `opencode-ios` |
| Primary category | Developer Tools |
| Secondary category | Productivity |
| Age rating | 17+ — the app displays source code, shell output and tool results from an AI agent that can run commands on your own machine |
| Copyright | `2026 Alessio Garofalo` |
| Encryption | `ITSAppUsesNonExemptEncryption = NO` (HTTPS/TLS only, no custom cryptography) |
| Contains ads | No |
| In-app purchases | No |

## Promotional text (170 chars max)

> Chat with your OpenCode agents from your phone. Connect to your own server over
> the network or an SSH tunnel, scan a pairing QR code, and follow every tool call.

## Description (4000 chars max)

```
OpenCode Remote is the native iPhone, iPad and Apple Vision Pro client for
OpenCode, the open-source AI coding agent.

Your OpenCode server runs on your own machine; this app is the way to reach it
from wherever you are.

CONNECT
• Scan the QR code printed by `opencode pair`, or paste the link, to add a
  server in seconds. The pairing code is exchanged for a session token that
  works anywhere the server password does.
• Add a server manually, with a username and password, over plain HTTP on your
  local network, over HTTPS, or through an SSH tunnel to a remote machine.
• Every server keeps its own credentials, model and agent selection.

WORK WITH YOUR AGENTS
• Chat with a session and watch the reply stream in, including its reasoning.
• Follow every tool call as it happens: shell commands, file reads and edits,
  patches and diffs.
• Switch the agent and the model mid-session, and see the model catalogue of
  the server you are connected to.
• Answer the questions an agent asks you, approve the permissions it requests,
  and cancel a run that is taking the wrong turn.
• Keep several servers side by side and jump between them.

READ AND REVIEW
• Browse the file tree of the project the agent is working in, with the working
  copy marked against the last commit.
• Read the unified diff of a session, and preview Markdown, images and source
  files with syntax highlighting.
• Track the usage quota of your model provider from the usage dashboard.

AMBIENT MODE AND APPLE WATCH
• Ambient mode keeps a read-only live surface on your phone and speaks to the
  assistant hands-free while you drive, with the car display and your watch in
  the loop.
• The Apple Watch app talks to the same sessions and asks the phone to run the
• tools, so a question asked on the watch still lands in your project.

PRIVACY
OpenCode Remote has no accounts, no analytics and no advertising. It talks only
to the servers you add. Your prompts, replies and tool output travel between
your device and your server and are never sent anywhere else.

OpenCode Remote is licensed under the Apache License 2.0. The licences of the
open-source packages it links are shown in the app under Settings → About →
Open source licences.
```

## Keywords (100 chars max, comma separated)

> opencode,ai,agent,code,chat,terminal,developer,llm,ssh,pair,watch

## What's new in this version (4000 chars max)

First release. Connect to an OpenCode server, chat with your agents, follow
their tool calls, and review the changes they make.

## Support and marketing URLs

| Field | Value |
|---|---|
| Support URL | `TODO` (a GitHub issue tracker works: `https://github.com/einyx/opencode_ios/issues`) |
| Marketing URL | `TODO` (`https://github.com/einyx/opencode_ios`) |
| Privacy policy URL | `TODO` — must be a publicly reachable web page, not a file in the repo. See `privacy-policy.md` for the text. |

## Screenshots

Required for the submission, and the App Store rejects an upload without them:

| Size | Device | Count |
|---|---|---|
| 1320 × 2868 or 1290 × 2796 | iPhone 6.9" / 6.7" | 3–10 (the first two are the App Store's "first two" slots) |
| 2048 × 2732 | iPad 13" | 3–10, if the app is offered for iPad |
| 416 × 496 | Apple Watch | optional, but the app ships a watch app |

The simulator can produce them: launch the app on the pinned simulator and
capture with `xcrun simctl io <udid> screenshot`. Suggested shots:

1. The chat with a streamed reply and a tool card.
2. The Files tab showing the working copy against the last commit.
3. A session diff.
4. Settings → Hosts with a paired server.
5. Ambient mode on the car display.
