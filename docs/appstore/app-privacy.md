# App Store Connect: App Privacy answers

> The current app has no cloud speech: every voice surface — dictation, Ambient
> mode and the Apple Watch — recognises and speaks on the device, and the only
> thing it sends is text to the OpenCode server the user configured. The
> questionnaire below was completed as **Data Not Collected** and no longer
> depends on the optional companion Health export, which the user approves
> explicitly and which runs in a separate app.

Update for 2026-10-26: the questionnaire was completed as **Data Not
Collected**, with the privacy policy URL set to
`https://einyx.github.io/opencodex/appstore/privacy-policy`. The published
page was updated afterwards to describe the on-device voice and the optional
Health export path.

Fill these into the **App Privacy** section of the App Store Connect record.

The key point: the app is a *client*. Everything it sends goes to the OpenCode
server the user configured; the developer of the app operates no service and
receives none of it. So the honest answer is **Data Not Collected**.

## Data type questionnaire

| Question | Answer | Why |
|---|---|---|
| Do you or your third-party partners collect data from this app? | **No — Data Not Collected** | The app has no backend, no analytics SDK, no advertising SDK and no crash reporter. It opens connections only to the servers the user adds, and the responses are shown to the user on their own device. |
| Do you use data for tracking? | **No** | No identifier is read for advertising, no data is joined with third-party data, and nothing leaves the device except to the user's own server. |
| Third-party SDKs | Declare the ones you actually ship | The app links open-source packages; none of them collect data (they are rendering, networking, crypto and SSH libraries). If you ship a crash reporter later, it changes this section. |

## The questions App Store Connect still asks

| Question | Answer |
|---|---|
| Does your app collect **User Content** (e.g. emails, photos, audio)? | **No** — the app *transmits* the user's own content to the user's own server, which is not collection by the developer. Say so explicitly in the notes below. |
| Does your app collect **Health & Fitness**? | No |
| Does your app collect **Financial Info**? | No |
| Does your app collect **Location**? | No — the app asks for the *local network* permission, not a location permission. |
| Does your app collect **Contacts**? | No |
| Does your app collect **Sensitive Info**? | No |
| Does your app collect **Browsing History**? | No |
| Does your app collect **Search History**? | No |
| Does your app collect **Identifiers**? | No |
| Does your app collect **Purchases**? | No |
| Does your app collect **Usage Data**? | No |
| Does your app collect **Diagnostics**? | No |

## Notes to paste into the questionnaire

> OpenCode Remote is a client for the user's own OpenCode server. The app has
> no backend of its own: it contains no analytics, advertising, attribution or
> crash-reporting SDK, and the developers receive nothing the user types or
> files. Messages, attachments and tool results travel directly between the
> user's device and the OpenCode server the user configured; the server is run
> by the user, not by us.
>
> The app stores its configuration and the server credentials in the device
> keychain. The camera is used only for the optional QR scan of a pairing code,
> and the microphone only when the user dictates a message or uses Ambient mode.

## Privacy policy

The policy text is in `docs/appstore/privacy-policy.md`. Publish it as a web
page and enter that URL in App Store Connect. Apple rejects a listing whose
policy URL is unreachable.

## Account deletion

Not applicable: the app has no accounts and no developer-side data, so there is
nothing to delete. State that in the notes if the form asks.
