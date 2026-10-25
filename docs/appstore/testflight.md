# TestFlight release

Everything needed to get a build onto TestFlight, in the order it has to happen.

## 1. Signing (the only thing blocking us right now)

An archive of the current tree fails with exactly two errors:

```
error: User interaction is not allowed. (in target 'OpenCodeWatch')
error: Provisioning profile "iOS Team Provisioning Profile: com.prysm.opencode.watchkitapp"
       doesn't include signing certificate "Apple Development: Alessio Garofalo (V3Y7XPBU37)"
```

Both say the same thing: the build wants a **distribution** certificate, and
every profile on this machine belongs to the **personal** team (`9DBH2A7KB8`),
whose certificates expired in July 2026.

To fix it, in Xcode → Settings → Accounts → (your team) → Manage Certificates:

1. **Revoke** the expired ones with the "−" button: the stale
   "Apple Development Certificate" and the revoked `V3Y7XPBU37` one. Xcode's
   error "You already have a current Development certificate or a pending
   certificate request" comes from trying to add a second *development*
   certificate — Apple allows one per machine per team.
2. **Create** an **Apple Distribution** certificate (the "+" dropdown →
   *Apple Distribution*, not *Apple Development*). That is the certificate an
   App Store/TestFlight build is signed with.
3. In the project → Signing & Capabilities, set the **Team** to that
   organisation team and the signing style to *Automatically manage signing*.
   Xcode then creates a distribution profile that includes the new
   certificate. Alternatively do it on the Apple Developer portal: register
   `com.prysm.opencode` and `com.prysm.opencode.watchkitapp` as explicit App
   IDs and create "App Store" distribution profiles for both.

The team id appears in the certificate's name in the keychain
(`Apple Distribution: <name> (<TEAMID>)`) — read it with:

```bash
security find-identity -v -p codesigning
```

and set it in the project with one replace-all:

```bash
sed -i '' 's/DEVELOPMENT_TEAM = 9DBH2A7KB8;/DEVELOPMENT_TEAM = <TEAMID>;/' \
  OpenCodeClient/OpenCodeClient.xcodeproj/project.pbxproj
```

## 2. Archive

```bash
./scripts/archive_appstore.sh
```

The script archives the Release configuration to
`.occlient/AppStore/OpenCodeClient.xcarchive` and prints the bundle id, the
version and the build number out of the archive.

`CURRENT_PROJECT_VERSION` is **29** and `MARKETING_VERSION` is **1.0**. Every
upload needs a build number **higher** than the last one uploaded, so check
App Store Connect for the highest uploaded build of `com.prysm.opencode` and
raise the build number if 29 is taken.

## 3. Upload

Any one of these works:

- **An App Store Connect API key** (App Store Connect → Users and Access →
  Integrations → App Store Connect API → team key). Download the `.p8`, then:
  ```bash
  export ASC_KEY_ID=XXXXXXXXXX
  export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
  ./scripts/archive_appstore.sh --upload
  ```
- **Transporter** (download from the App Store Connect site): open the
  archive and drag it in.
- **altool with an app-specific password** (App Store Connect → Users and
  Access → Users → your account → *App Store Connect* → *Create Password*):
  ```bash
  xcrun altool --upload-app -f .occlient/AppStore/OpenCodeClient.xcarchive \
    -u alessio@example.com -p "@keychain:AC_PASSWORD"
  ```

## 4. TestFlight setup

**Internal testing first.** Up to 100 App Store Connect users, and **no Beta
App Review**: the build is available to your team within minutes.

- App Store Connect → your app → TestFlight → **Internal Testing** → create
  the group, add the testers, then add the uploaded build.
- Export compliance: the build declares `ITSAppUsesNonExemptEncryption = NO`
  (standard TLS only), so the only question left in the "Manage Build" dialog
  is the annual one.
- Nothing else is required for internal testing.

**External testing** is what a public TestFlight link needs. It requires
**Beta App Review** for the first build of the external group (each later
build of an approved group usually goes straight through), and each external
group needs:

| Field | Value |
|---|---|
| Beta name | `OpenCode Remote` |
| What to test | see below |
| Feedback email | your address |
| Sign-in required | **No** — the app has no account |

**What to test** (paste this into the build's notes):

> Connect this app to your own OpenCode server and watch an agent work.
>
> 1. Install OpenCode on a machine and run `opencode serve`.
> 2. On that machine run `opencode pair` — it prints a link and a QR code.
> 3. In OpenCode Remote: Settings → Hosts → Add Host, then either scan the QR
>    code or paste the link. The credentials fill in themselves.
> 4. Pick a session and send a message. Replies, reasoning and tool calls
>    stream in; open the Files tab to see the working copy and the diff of the
>    session.
>
> There is no account to create and nothing to sign in to.

**Privacy policy URL** (required before the first external tester can
install): publish the text in `docs/appstore/privacy-policy.md` and put the
URL in App Store Connect → App Information → Privacy Policy URL. GitHub Pages
over this repository is the quickest route, and it is done — the site publishes
`main` / `/docs`, so the policy is live at
`https://einyx.github.io/opencode_ios/appstore/privacy-policy`.

## 5. After the upload

- [ ] The build finishes processing (a few minutes).
- [ ] Attach it to the version in App Store Connect.
- [ ] Fill in the export compliance question.
- [ ] Publish the internal group (or submit the external group for beta
      review).
- [ ] Confirm the on-device name reads "OpenCode Remote" (the binary's display
      name is set to that; before this change it read "OpenCodeClient").
