# Privacy policy — the device-only voice

> This is the **Voice transcription** section for the release that carries the
> device-only voice. The published policy
> (`https://einyx.github.io/opencodex/appstore/privacy-policy`) still
> describes the hosted voice path, because version 1.0 ships build 33. Replace
> the section in `docs/appstore/privacy-policy.md` with this one, and
> republish, before the build that removes the hosted path is submitted.

## Voice transcription

Voice input runs entirely on the device, and there is nothing to configure:

- **On-device recognition.** Speech recognition uses Apple's frameworks on the
  device itself. The audio is not uploaded anywhere, and no cloud speech
  service is used.
- **Your own server is the only destination.** The recognised text is sent to
  the OpenCode server you configured — the same server that answers your
  messages. There is no account, no access token and no third-party voice
  service anywhere in the app.
- **Ambient mode** (the hands-free surface) follows the same rule: the app
  recognises your speech on the device, asks your server, and speaks the answer
  with the device's own speech synthesiser.
- **Apple Watch.** The watch has no speech-recognition framework of its own, so
  your watch's microphone audio travels over the private
  Apple-to-iPhone connection to the paired iPhone, which recognises it on the
  device. The answer is spoken by the watch. No audio reaches a server or a
  third party as audio.
