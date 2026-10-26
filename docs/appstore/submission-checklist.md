# App Store submission checklist

## Current preparation status — 2026-10-26

This section supersedes the historical signing/version notes below. Build 33
is uploaded, validated, attached to version 1.0, and **submitted to App Review**
on 2026-10-26 (status: Waiting for Review).

- [x] Saved listing description, promotional text, keywords, support/marketing URLs and copyright.
- [x] Saved subtitle and Developer Tools / Productivity categories; preserved the store name OpenCodeX.
- [x] Selected manual release, so approval does not publish the app automatically.
- [x] Uploaded three iPhone screenshots (1206×2622) and one iPad screenshot (2064×2752), captured from production views using debug-only illustrative sample data.
- [x] Uploaded the product-page header (3840×1646) and search-results asset (1920×1280) built from the icon and real UI captures. See `creative-assets.md`.
- [x] Uploaded an Apple Watch screenshot (416×496) captured from the watch app on an Apple Watch Series 11 simulator.
- [x] Replaced the legacy Watch icon with opaque 1024×1024 artwork matching the iOS icon. `swift scripts/sync_watch_icon.swift --check` verifies pixel agreement.
- [x] Built and uploaded build 33; selected it in the submission draft, which also updated the Apple Watch asset to the corrected artwork.
- [x] Native unit suite: 1,177 tests passed, with six pre-existing known design-token issues. Screenshot capture UI tests passed on iPhone 17 Pro and iPad Pro 13-inch.
- [x] App Privacy: Data Not Collected, published; privacy policy URL set to `https://einyx.github.io/opencodex/appstore/privacy-policy`.
- [x] Rewrote and published the privacy policy on the `einyx/opencodex` Pages site: it names OpenCodeX, describes the optional cloud speech and Health export paths, and points at the current issue tracker.
- [x] Age rating: 18+ (override of the 9+ calculation) with profanity marked infrequent, matching `metadata.md`.
- [x] Content rights: answered that the app has the necessary rights to the third-party content it displays.
- [x] Pricing (free, 175 regions, base Spain) and app availability (all countries or regions) configured.
- [x] App Review contact details and notes saved, including how a reviewer reaches a server and what the optional services do.
- [x] Build 33 metadata verified in App Store Connect: bundle `com.prysm.opencode`, binary validated, `App Uses Non-Exempt Encryption: No`, watch app embedded.
- [x] Submitted to App Review on 2026-10-26. Watch the App Review → Submissions page for Apple's messages and the decision.
- [ ] Provide a dedicated, externally reachable demo server with safe credentials. The review notes explain how to run one, but the reviewer needs a reachable instance if they cannot start their own.
- [ ] After approval, release manually and verify the listing on the App Store.

### Open after the submission: the Settings "Checking…" spinner could get stuck

Reported from the device after build 33 was submitted. The Settings connection
row said "Checking…" next to a server version it already knew, and never
resolved. Three defects, all fixed after the submission:

1. The row's spinner was bound to the whole `state.refresh()` — health check
   plus the workspace reload behind it (sessions, messages, diffs, todos, file
   tree, status poll). The connection had been proven in the first few hundred
   milliseconds, but the row kept claiming otherwise for the entire reload, and
   forever when one load stalled.
2. A connection check that was superseded (the user switched hosts mid-check)
   published its "checking health" phase without the host-request guard the
   rest of the function used, so it could strand the *new* host on a phase that
   never finishes.
3. The app's API client used `URLSession.shared`, whose `waitsForConnectivity`
   is on: a request to an unreachable host waited for a network that may never
   come instead of failing, so a check could hang outright.

The status now follows the check itself (`AppState.isConnectionCheckInFlight`),
diagnostic writes are scoped to the request that produced them, and the client's
session fails fast instead of waiting for connectivity. Covered by three new
unit tests; the native unit suite is at 1,180 tests passing with the six
pre-existing known design-token issues.

**Build 33 still carries the bug.** Shipping the fix needs a new build (34),
uploaded and attached to version 1.0. Decide whether to withdraw the current
submission first or to upload build 34 while it is still waiting for review.

Optional cloud speech sends audio to the configured speech service, rather than
necessarily through the OpenCode server. The Health export action can launch
the separate Health Quantification app to export to its configured server;
the callback link does not contain health details. The questionnaire answers
above treat these as user-operated services the developer does not receive,
which is why Data Not Collected was chosen. The owner should confirm that the
speech provider's terms match that description.

Screenshots and result bundles remain ignored under `.occlient/appstore-prep/`
and `.occlient/test-runs/`. The capture workflow is
`AppStoreScreenshotUITests`, with `UITEST_APP_STORE_SCREENSHOTS` in Debug only.

## Historical preparation notes

Everything that has to happen between "the code is ready" and "the app is in
the App Store", with the current state of each item.

## 1. Blocker: the signing team

**The app cannot be uploaded from the team that is configured on this machine.**

The only team in the local Xcode account is:

```
Alessio Garofalo (Personal Team)   9DBH2A7KB8   isFreeProvisioningTeam = 1
```

A *Personal Team* is the free tier: it can build, install on your own devices
and run a development profile, but it **cannot create an App Store Connect
record, upload a build or use TestFlight**. To publish, the Apple Developer
Program ($99/year) has to be enrolled, and the organisation team used for the
submission has to be selected in the project.

The project currently has two teams in it:

| Where | Team |
|---|---|
| `OpenCodeClient` app target, `OpenCodeWatch` target | `9DBH2A7KB8` (personal) |
| project-level and test targets | `Y2T99LVU9E` (not in the local Xcode account) |

Before archiving, set `DEVELOPMENT_TEAM` for the app and watch targets to the
enrolled organisation team, and register the bundle ids there:

| Bundle id | Used for |
|---|---|
| `com.prysm.opencode` | the app (device build) |
| `com.prysm.opencode.watchkitapp` | the watch app (device build) |

The simulator builds keep `com.grapeot.OpenCodeClient`, which is why the two
values differ per SDK.

**Getting the organisation team onto this machine.** Xcode only knows the
Personal Team until the organisation team is added to the account:

```
~/Library/Preferences/com.apple.dt.Xcode.plist
  IDEProvisioningTeamByIdentifier → 6811CF31-3DC6-484D-9707-0A8B02BBE355
    isFreeProvisioningTeam = true
    teamName = Alessio Garofalo (Personal Team)
```

`6811CF31-…` is the Personal Team's modern identifier; the legacy 10-character
id `9DBH2A7KB8` in the same keychain certificates and provisioning profiles
belongs to the same team. The organisation team appears in the same place with
`isFreeProvisioningTeam = false` once the Apple ID that holds the organisation
membership is signed in (Xcode → Settings → Accounts → + → Apple ID, or sign in
with that Apple ID instead). When it does, copy its legacy 10-character team id
into `DEVELOPMENT_TEAM` and create the two App Store identifiers and their
distribution profiles from the Xcode account window.

The project currently has two teams in it:

| Where | Team |
|---|---|
| `OpenCodeClient` app target, `OpenCodeWatch` target | `9DBH2A7KB8` (personal) |
| project-level and test targets | `Y2T99LVU9E` (not in the local Xcode account) |

The `build(signing): use one signing team everywhere` commit unified every
configuration onto `9DBH2A7KB8` so a fresh clone can sign at all, which is why
the table above no longer matches the project.

## 2. Done: the `voiceflow` dependency is licensed

`grapeot/voiceflow` (the `VoiceFlowKit` package the voice input is built on)
shipped **no licence file**, so there was no grant to redistribute it.

The package is now forked to `einyx/voiceflow`, which carries the Apache
License 2.0 and a NOTICE that credits the upstream authorship and records the
fork's origin. The app pins that fork at the tagged `0.4.1`, which is the
commit that adds the licence, so the pinned source carries it too.

`scripts/generate_third_party_notices.py` exits non-zero while a resolved
package has no licence metadata, and lists it under "Packages without a
licence" in `THIRD_PARTY_NOTICES.md`.

One thing to settle with the upstream author: relicensing a repository that
had no licence is only covered by their permission. A short note to them (the
repository is public) closes that.

## 3. Done in this repository

- [x] `LICENSE` — Apache License 2.0.
- [x] `NOTICE` — attribution, and where the third-party notices live.
- [x] `THIRD_PARTY_NOTICES.md` + the bundled `ThirdPartyNotices.txt`, generated
      from `Package.resolved` by `scripts/generate_third_party_notices.py`.
- [x] An in-app screen: Settings → About → Open source licences.
- [x] `Info.plist` / build settings: `NSCameraUsageDescription`,
      `NSMicrophoneUsageDescription`, `NSLocalNetworkUsageDescription` and
      `ITSAppUsesNonExemptEncryption = NO`. Two of the usage strings were
      **empty**, which would have denied the permission at runtime.
- [x] The 1024×1024 marketing icon is in `AppIcon.appiconset`.
- [x] `PrivacyInfo.xcprivacy` (required-reason APIs).
- [x] Version `1.0 (29)`.

## 4. Still to do

- [ ] Enroll the organisation team and point the targets at it (section 1).
- [x] Resolve the `voiceflow` licence (section 2).
- [x] Publish the privacy policy as a web page and put the URL in App Store
      Connect (text: `docs/appstore/privacy-policy.md`). GitHub Pages is enabled
      on this repository, publishing `main` / `/docs`, so the policy is live at
      `https://einyx.github.io/opencodex/appstore/privacy-policy`, and the
      URL is filled in in `metadata.md` along with the support and marketing
      URLs.
- [ ] Fill in the listing metadata (`docs/appstore/metadata.md`): the screenshots
      are still missing.
- [ ] Capture the screenshots from the simulator.
- [ ] Create the App Store Connect record: name, bundle id, SKU, category,
      age rating, export compliance.
- [ ] Fill in the App Privacy questionnaire (`docs/appstore/app-privacy.md`).
- [ ] Paste the review notes (`docs/appstore/review-notes.md`).

## 5. Build and upload

See `docs/appstore/testflight.md` for the full flow. In short:

```bash
./scripts/archive_appstore.sh              # archive
./scripts/archive_appstore.sh --upload     # archive, then upload
```

The upload needs an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`),
or Transporter, or an altool app-specific password.

The archive currently fails with two signing errors — a distribution
certificate and a profile that includes it are missing — which section 1 of
`testflight.md` covers.

## 6. After the upload

- [ ] Answer the export compliance prompts (the app is `NO` for non-exempt
      encryption, so the only question left is the annual one).
- [ ] Wait for the processing email, then attach the build to the version.
- [ ] Submit for review.
- [ ] Watch for a rejection on the missing privacy policy URL or on the
      permission prompts — the two usage strings that were empty are exactly
      what a reviewer taps.
