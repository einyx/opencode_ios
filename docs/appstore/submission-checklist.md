# App Store submission checklist

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
- [ ] Publish the privacy policy as a web page and put the URL in App Store
      Connect (text: `docs/appstore/privacy-policy.md`).
- [ ] Fill in the listing metadata (`docs/appstore/metadata.md`): the support
      URL, the marketing URL, the privacy policy URL, and the screenshots.
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
