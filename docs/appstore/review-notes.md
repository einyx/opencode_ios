# App Review notes

Paste this into **App Store Connect → App Review Information → Notes for
Review**. It tells the reviewer what the app does, how to exercise it, and what
the reviewer is likely to trip over.

---

OpenCode Remote is a native client for OpenCode, the open-source AI coding
agent. The user runs an OpenCode server on their own computer and this app
connects to it.

**ACCOUNT SIGN-IN IS NOT REQUIRED.** There is no account, no login and no
subscription. The app is usable immediately; every server is added by the user.

**HOW TO TEST IT.** The app needs a reachable OpenCode server, which the
reviewer may not have. Any OpenCode server works; the fastest way is to run
`opencode serve` on a machine on the same network and add its address. Two
paths:

1. *Add a server manually*: Settings → Hosts → Add Host, fill in the name, the
   server URL (for example `http://192.168.1.10:4096`), the username `opencode`
   and the password, then Save. The host detail shows the connection phase.
2. *Pairing*: on the machine running the server, run `opencode pair`. It prints
   a one-time link and a QR code. In the app, Settings → Hosts → Add Host →
   "Scan QR code", or paste the link. The credentials fill in themselves and
   the username and password fields disappear, because the pairing token takes
   their place.

The app also supports an SSH tunnel to a remote server (Settings → Hosts → Add
Host → connection type "SSH tunnel"), where the app opens a tunnel to the
remote machine and reaches the OpenCode server through it.

**WHAT THE APP DOES WITH THE CONNECTION.** Everything the app sends goes to
that server: your messages, the images you attach, and the tool calls an agent
makes. The replies, the reasoning and the tool results come back over the same
connection and are shown on the device. There is no cloud service of ours
involved, no analytics and no advertising.

**PERMISSIONS.**
* Camera — only for the optional QR scan of a pairing code.
* Microphone — only when you dictate a message or use Ambient mode.
* Local network — to reach an OpenCode server running on your own network.
* Background audio — Ambient mode can keep the microphone open while the app is
  in the background so a conversation is not cut short.

**AMBIENT MODE.** An experimental hands-free surface for the car: the app reads
the conversation aloud, takes voice input and shows the live state of the
session. It is behind a switch in Settings → About → Ambient Mode, and it is
off by default.

**APPLE WATCH.** The app ships a watch app that shows the current session and
lets you ask a question. The watch does not run tools itself: it forwards the
request to the phone, which runs the tool against your server and sends the
result back. The watch needs the phone to be reachable.

**APPLE VISION PRO.** The app runs on visionOS with the iPad-style three
column layout.

**NOTES.** The app is licensed under the Apache License 2.0. The licences of the
open-source packages it links are listed in the app under Settings → About →
Open source licences, and the notice text is bundled with the binary.
