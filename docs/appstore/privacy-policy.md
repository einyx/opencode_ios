# Privacy policy

Publish this as a web page (GitHub Pages over this repository is the simplest
option) and put its URL in App Store Connect. Apple requires the policy to be
reachable without a login.

---

# Privacy Policy for OpenCode Remote

_Last updated: 2026-10-25_

OpenCode Remote is an iOS, iPadOS and visionOS client for
[OpenCode](https://github.com/anomalyco/opencode), the open-source AI coding
agent. This policy explains what the app does with your data.

## The short version

OpenCode Remote has **no accounts, no analytics, no advertising and no
tracking**. It talks to the OpenCode server **you** choose, and to nothing else.
The developers of the app never receive your prompts, your replies, your code or
your credentials.

## What the app stores on your device

The app stores the configuration needed to reach the servers you add:

- the server address, transport (direct or SSH tunnel) and SSH settings;
- the username and a reference to the credential you provide;
- your server password or pairing token, stored in the system keychain;
- the selected model and agent per server, your draft messages, and the
  transcripts the server has sent you, so the app can show them again;
- your language preference and other interface settings.

## What the app sends where

Everything the app sends goes to the OpenCode server you added:

- your messages, the images you attach, and the agent or model you pick;
- the tool calls an agent makes and their results, which the app displays;
- the name of the file or folder you open in the file browser.

If you use the AI Usage Dashboard integration, the app also asks that dashboard
for your provider's quota. It points at the dashboard you configure yourself.

## Camera and microphone

- The **camera** is used only when you scan a pairing QR code, and only when
  you tap the scan button.
- The **microphone** is used when you dictate a message, or when you use
  Ambient mode to talk to the assistant. The recording is sent to the
  transcription service behind your own OpenCode server.

## Voice transcription

When the app transcribes speech, the audio is sent to the transcription
provider configured in your OpenCode server (the same one the server uses for
its own voice input). The app has no built-in speech service of its own.

## Local network

The app asks for permission to reach devices on your local network so it can
connect to an OpenCode server running on your computer.

## Background audio

Ambient mode can keep recording while the app is in the background so a
conversation is not cut off. The recording stops when you end the conversation.

## No data collection by the developers

The developers of OpenCode Remote do not operate a server for the app, do not
collect analytics, and do not receive anything you type. Your data stays
between your device and the servers you configured.

## Children's privacy

The app is not directed at children and collects no data from anyone,
including children.

## Third-party open source

The app links open-source packages under permissive licences. Their licences
are listed in the app under Settings → About → Open source licences.

## Changes

If this policy changes, the updated version will be published at the same URL
and the date above will change.

## Contact

Questions about this policy can go to the issue tracker of the app's
repository: `https://github.com/einyx/opencode_ios/issues`.
