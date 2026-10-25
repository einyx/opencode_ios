# Decision Record — Subscription Tiers for OpenCode Remote

| Field | Value |
|---|---|
| Status | **Proposed** — implementation blocked on §4 (App Store / legal) and §6 V1–V3 |
| Date | 2026-10-25 |
| Scope | Pricing and tier boundaries for the iOS/watch client and the hosted surface it may sell |
| Decision owner | product owner |
| Companion records | `../hosted_relay/design.md` (relay architecture — this record is the revenue answer to its OQ-1) · `../push_notifications/research.md` (push transport) · `../client_capabilities/protocol.md` (connector/plugin surface) |
| Supersedes | nothing |
| Caveat | §4 states App Store constraints *as understood*. **This is not legal advice** — §4.3 lists what counsel must confirm. |

---

## 1. The question and the decision

**Question:** The client is free, has no push notifications, no accounts and no hosted service, and the team is weighing GitHub Copilot support plus a paid tier — so what could a subscription legitimately be sold on?

**Decision:** Ship three tiers — a free, account-free, BYO-server **Community** tier that stays complete and permanent; a **Connect** subscription at **$9.99/month or $89/year** that sells only *glue* (hosted relay reachability, attention push, multi-device continuity) and never model access, credits, or message history; and a capped, web-only **Founding Supporter** one-time purchase at **$49** that grants no in-app entitlement — with Copilot and every other provider shipping to all tiers and never appearing in a paywall.

---

## 2. What this product is actually worth

### 2.1 Ranked value to a paying user

Ranked by (value × willingness to pay) ÷ build cost.

**1 — Never-missed approvals (push).**
The PRD calls this the top gap twice (§1.2 and §9: "mutually waiting *idle spin*"). The payload already exists in the client: `PermissionCardView` and `QuestionCardView` consume `permission.asked` / `question.asked`. The delivery does not: no `.entitlements` file, no `aps-environment`, no `UNUserNotificationCenter` usage anywhere in `OpenCodeClient/`, and `Info.plist` declares only `UIBackgroundModes = [audio]`. Worse, the event is *lost*, not delayed — `applyBackgroundDisconnect()` (`AppState+BackgroundVoice.swift:169,173`) drops both the SSE stream **and** the SSH tunnel the moment the app backgrounds. A permission request raised while the phone is in a pocket blocks the agent indefinitely and the user never learns. **The user is not paying for an agent; they are paying to not lose twenty minutes to a blocked agent.**

**2 — Reachability that does not depend on the phone.**
Remote use today requires one of: a public HTTPS server, a phone-held SSH tunnel (`SSHTunnelManager`, `NWListener` on `127.0.0.1`), or a user-managed VPN/Tailscale. `Info.plist` ATS allows only local networking plus `ts.net`, so plain HTTP on the public internet is already blocked. Every path costs the user money, ops, or foreground time — and the tunnel path dies on backgrounding by design. A hosted relay turns "can I reach my server right now?" into a constant. Per `../hosted_relay/design.md` the connector dials **out**, so the user's server needs no public IP, no inbound port, and no firewall change.

**3 — Continuity across devices and across sleep.**
Today's continuity is accidental: it depends on the phone being connected when the event arrives. The relay's session fan-out (one host's event stream to iPhone + iPad + watch-bridge) and its TTL-bounded sealed queue (an attention event survives an asleep phone) are real, additive value — and they cost the relay almost nothing beyond the connection it already holds.

**4 — Recall: real, but not sellable inside this product's privacy envelope.**
The OpenCode API has no full-text search over session messages — PRD §6.2 lists `GET /find?pattern=...` as optional/unimplemented; only file search (`GET /find/file`) is required. Transcripts live on the user's server plus a device-local cache (`MessageStore`, `SessionStore`). So "what did the agent do last Tuesday about the auth refactor?" is unanswerable today. **But the only way to answer it is for somebody to hold and index the user's prompts and tool output** — which falsifies the app's single strongest claim ("the developer of the app operates no service and receives none of it", `docs/appstore/review-notes.md`; `docs/appstore/app-privacy.md` currently answers the whole privacy questionnaire "Data Not Collected"). A hosted index is therefore **excluded from Connect** (§3.3, §5.9). Recall must be delivered on the user's own server or on-device, where it is free.

**5 — Reliability of the surfaces that already exist.**
The Watch app (`../watch_ambient/prd.md`: *Experimental*, drops mid-answer), car mode / ambient voice (`CarLiveController`, `BackgroundVoicePolicy`), and the typed device-capability protocol (`../client_capabilities/protocol.md`) are the app's differentiators and are not yet dependable. If a hosted live gateway is ever needed to make them dependable, the *service* can be sold — the client features stay free (§3.2).

**6 — Multi-device orchestration.**
Watch→phone bridge, phone-as-tool-executor, client capabilities. Future team value; no monetization until the surfaces are solid.

### 2.2 What is NOT worth paying for

- **Model access, model choice, context size, agent catalogue.** The server owns all of it (`/config/providers`, `/agent`, `ModelPreset`). The app holds no provider credentials and cannot grant inference. Selling this means reselling somebody else's units.
- **The chat UI.** Markdown rendering, streaming bubbles, tool cards — commodity; every AI client has it and the open-source web UI is the competitor. Charging for it means charging for the thing the market gives away.
- **Files, diffs, markdown preview, file tree.** The PRD itself calls the Files tab a "fallback entry point", not the main workflow.
- **More sessions / more agents / more tool calls / longer transcripts.** Server-side, already unlimited on the free tier.
- **Voice minutes and transcription quality.** The server's provider does transcription; minutes are the same reseller trap as credits (§3.6).
- **"Premium" model presets.** There is no such thing; the catalogue is the server's.
- **A hosted copy of your transcripts.** Beyond the privacy inversion (§2.1 #4), the user's own server already stores them; a second copy is redundant surface area, not product.

### 2.3 The blunt version

> The user is not paying for an agent and not paying for a chat app. They are paying for three things: **to be woken when the agent needs them**, **to reach their machine from anywhere without thinking about it**, and **to still get the message when their phone was asleep**. Anything behind the paywall that is not one of those three is a tax on a free tier whose only job is to get the app installed — and anything we put behind the paywall that requires holding the user's prompts is a betrayal of the one thing this app is for.

---

## 3. Tier structure

### 3.1 The three tiers

| | **Community** (free) | **Connect** (subscription) | **Founding Supporter** (one-time) |
|---|---|---|---|
| Price | $0, forever | **$9.99/mo or $89/yr** | **$49**, capped at 100 seats |
| Account | none | none in v1 (device-scoped relay credential; StoreKit 2 entitlement) | none |
| Servers | your own, unlimited | your own, unlimited (relay limited to 5 hosts / 5 devices) | your own |
| Reachability | LAN / HTTPS public / SSH tunnel / VPN | **+ hosted relay** (always-on, phone-free, no public IP needed) | own setup |
| Push | none (or your own APNs provider) | **attention push** — question, permission, error, opt-in idle | none |
| Continuity | device-local only | **+ multi-device fan-out, sealed offline queue (TTL)** | own setup |
| Client surfaces (chat, files, diffs, markdown, quota dashboard, car, watch, capabilities, task cards, deep links) | all | all | all |
| Support | community (GitHub issues) | email, 1 business day first-response target | community |

### 3.2 Free forever — the list and the rationale for each boundary

Free forever: chat/streaming/markdown · tool cards and patches/diffs · file tree + preview · QR pairing (`opencode pair`) · host profiles · Basic Auth · SSH tunnel · Tailscale/VPN hosts · AI usage quota dashboard (`AIUsageQuotaClient`) · car mode · ambient voice · watch app · client-capability protocol · task-notification cards · deep links (`opencode://`) · local transcript cache, session finder, drafts · **any relay-independent way to reach or message the user's own server, including one the user runs themselves**.

**The boundary rule (one sentence, and the whole policy):**

> A feature may be paid **only** if satisfying it requires us to keep a machine awake on the user's behalf. If it runs on the device, on the user's own server, or on a server the user chooses to run, it is free forever.

Each paid item in §3.3 satisfies it; each free item above violates it. This rule is testable in one sentence at every future pricing discussion, and it is what keeps Community defensible rather than a trial. It also mirrors the companion design's invariant: *the app works fully self-hosted with no subscription; a relay host is additive and `.direct` / `.sshTunnel` hosts keep every current feature* (`../hosted_relay/design.md` §1.1).

### 3.3 Paid: Connect — sells glue, not tokens, not content

**Includes:**

1. **Hosted relay (reachability)** — the phone reaches a NAT-bound server through our always-on relay. Per `../hosted_relay/design.md`: a **sealed message bus**, not a reverse proxy — the connector dials out, the relay routes end-to-end-encrypted envelopes and never terminates the seal, so we cannot read prompts, replies, tool output, or the host's credentials. Limits: 5 hosts, 5 devices, 20 GB/mo egress included (a cost control, see Appendix A.5).
2. **Attention push** — `permission.asked`, `question.asked`, `session.error`, plus opt-in `busy → idle`. The **connector** on the user's own server detects the event locally and reports a **metadata-only envelope** (install id, session id, event type, timestamp); the relay carries it to APNs. No prompt text, no paths, no tool output ever enters the relay's plaintext path.
3. **Multi-device continuity** — one host's event stream fanned out to every enrolled device, each sealed to that device's key, plus a TTL-bounded sealed queue so an attention event survives an asleep phone.

**Explicitly NOT in Connect:** model access, credits, minute bundles, extra agents, themes, the capability protocol, anything on the free list, **and any relay-side storage or index of session messages, prompts, or file content**. The relay holds metadata only (device ids, host ids, IPs, timestamps, APNs tokens, routing tables) — see §4.2.

**One-line rationale per boundary:**

- *Relay:* it is the only component whose value and cost both scale with being always-on, and it removes the user's ops burden entirely (no public IP, no inbound port, no tunnel to hold open).
- *Push:* the client structurally cannot notify today (no entitlement, no notification code, no background mode) — closing the "blocked agent" loop requires a party that stays connected to APNs on the user's behalf.
- *Continuity:* fan-out and the sealed queue are free riders on the connection the relay already holds; they turn a single-device client into a multi-device one without touching the privacy envelope.

### 3.4 The Founding Supporter tier — yes, but narrow, and it unlocks nothing in-app

- **$49 one-time, capped at 100 seats** (~$4,900 total). Sold on the **web** (Tipjar / GitHub Sponsors / Patreon), deliberately **not** as an App Store IAP.
- **Grants:** public acknowledgement (name/site list), roadmap-priority votes, early access to experimental surfaces *by build/TestFlight*, and standing to say "I funded this" in the tracker.
- **Grants no in-app entitlement, on purpose.** An off-platform purchase that unlocks in-app functionality is precisely the App Store question in §4; a badge is not worth that exposure. The supporter tier's job is to fund the free tier and capture the purist segment — not to be a tier.
- **Why it exists:** the audience is technical and subscription-hostile, the client is Apache 2.0 and free forever, and some fraction will want to fund it but will never buy a relay. It also creates a launch cohort that de-risks Connect (V1/V2).
- **Why it is capped:** a one-time tier with no marginal cost is pure margin and would cannibalize Connect for exactly the users most likely to convert. The cap turns it from a revenue line into a launch instrument.
- **Kill criterion:** fewer than 15 of 100 seats sold within 60 days of launch ⇒ drop the tier; it is marketing overhead, not a business.

### 3.5 Provider support (incl. GitHub Copilot) is not a pricing axis

Background (verified, Oct 2026): GitHub has **no public Copilot model/completion API**; an SDK for embedding the agent runtime is in public preview (Apr 2026); on **1 Jun 2026 Copilot moved from premium requests to usage-based AI Credits (1 credit = $0.01)** and Individual sign-ups were paused with limits tightened.

- If Copilot integration happens, it happens through the **user's own Copilot subscription** (BYO) on their server, or via the runtime SDK as a *server-side* provider. Either way the client holds no provider credential, so **Copilot ships to Community like every other provider** and never appears in a paywall.
- Copilot's switch to AI Credits is a live demonstration of the risk in reselling inference (§3.6): the upstream unit economics moved once in 2026, and vendor sign-ups were paused.
- If a future integration *requires* a hosted service we operate (because no BYO path exists), that is a digital service consumed in-app and lands in §4's IAP analysis — it does not become part of Connect's value proposition without a separate decision.

### 3.6 Why we do not resell AI credits

Reselling credits is the one option that looks like revenue and is actually a liability. The app holds **no** provider credentials and adds **zero** value to inference: keys, model catalogue and metering all live on the user's server, so a "credit" we sell is a pass-through of somebody else's units at somebody else's rate — cost of goods is 100% of face value and our margin is a spread we do not control. Copilot's own 1 Jun 2026 move to AI Credits (1 credit = $0.01), plus paused Individual sign-ups, shows how fast the upstream rate and policy move; a reseller is the most exposed party to that move and the party the user blames when a provider rate-limits. Support load is the killer: "my tokens didn't work" is a pure pass-through dispute with no resolution path on our side, converting a $10/month account into engineering hours with no revenue. It also breaks the product's core neutrality — the server can hold *any* provider's key today, and reselling one provider's credits would turn the client into a vendor-specific storefront, a different company than the one we want to be. **We sell the reliability of access, not the access's units.** Users buy credits from their provider; the app must work identically when they do.

---

## 4. App Store constraint (needs legal review — not legal advice)

### 4.1 The constraint as we understand it

- Selling access to a hosted service **inside** the app is the sale of a digital service → generally requires in-app purchase.
- If the app remains **fully functional without any purchase**, selling the hosted tier elsewhere may be permissible.
- Apple typically takes **15%** under the Small Business Program (≤ $1M annual proceeds — *verify current terms*) or **30%** standard.

### 4.2 What the recommendation implies

1. **Community must stay complete and account-free.** Not only the growth engine and the "no accounts, no analytics, no advertising" claim in `docs/appstore/metadata.md` and `docs/appstore/privacy-policy.md` — it is the fact that keeps the external-sale route open. Concretely: no sign-in wall, no feature that becomes unusable without a purchase, no license check on any shipped client feature.
2. **Connect ships as an App Store IAP subscription (auto-renewable), entitlement read via StoreKit 2** (`Transaction.currentEntitlements` + `AppStore.sync()`), so purchases restore across devices **without a user account**. The relay authorizes a device from the signed transaction JWS validated server-side; the relay credential is device-scoped and opaque, so no email, no login, no PII. *This is the most important implementation decision in this record: it preserves the no-account posture while still letting us verify entitlement.*
3. **Margin implication.** IAP costs **$1.50**/user/month at 15% on $9.99 versus **$0.59** for a 3% web checkout — a **$0.91/user/month gap ≈ $1,100/year per 1,000 paying users**. Against a paid tier's support cost of **$2.75–$5.50**/user/month, the store cut is not what decides this business. **Take the 15%; do not contort the product to avoid it.** If a web checkout is later used for team/annual sales, treat it as one price, not two — and it must not be *linked* from the app in a way that steers (Q3).
4. **The compliance consequence is bigger than the store cut, and it is not optional.** `docs/appstore/app-privacy.md` currently answers the entire App Privacy questionnaire with **"Data Not Collected"** on the stated basis that "the developer of the app operates no service and receives none of it." A relay falsifies that sentence: the relay holds accounts/credentials, IP addresses, device identifiers, APNs tokens, host↔device routing tables and timestamps. Consequences that must be *planned*, not discovered:
   - The App Privacy answers flip to **Yes** for identifiers, purchases, usage data and diagnostics. User content stays "not collected" **only because the E2E seal holds** — which becomes the app's strongest privacy claim *and* its strongest marketing message.
   - `docs/appstore/privacy-policy.md` needs a rewrite and a Terms of Service is needed.
   - If a relay-hosted web dashboard is ever required (for the external-purchase route in Q3), accounts exist → **Guideline 5.1.1(v) in-app account deletion** applies, and the deletion surface must cover account, relay credential, device records including APNs tokens, host enrollments, queued envelopes and audit rows.
   - If the relay is EU-hosted, it is a processor of personal data (IPs, timestamps, opaque identifiers) — metadata is personal data under GDPR.
   - A reviewer may read a relay that tunnels device↔host traffic as a VPN and reach for **Guideline 2.5.4** (the companion design flags this explicitly, using plain TLS rather than Network Extension to stay clear of the VPN API, but the perception risk is real).

### 4.3 What must be confirmed with counsel

1. Does the Community tier as scoped satisfy "fully functional without purchase" under Apple's current guidelines, and does an **external** purchase that unlocks **in-app** digital functionality (push, relay access, continuity) create rejection risk? Which current rule and wording?
2. May a **web checkout** coexist with IAP for the same entitlement, and what in-app presentation is permitted (price display, manage-subscription link, support link) without steering (3.1.3(e)-type rules)?
3. Does the **Founding Supporter** purchase, granting no in-app entitlement, need an IAP option; and if a badge is later added to the app, does that convert it into a digital unlock that must use IAP?
4. **Guideline 2.5.4** — does a sealed message bus that routes traffic between a device and the user's own server read as tunneling/VPN functionality to a reviewer?
5. **Guideline 5.1.1(v)** — if any account (or a relay-hosted dashboard) is introduced, what is the minimum in-app deletion surface, and does a device-scoped opaque relay credential with no user identity escape the rule entirely?
6. If Connect is later sold to **teams** on the web with per-seat entitlements and a console, does that qualify as a business/reader-style sale exempt from IAP? (Determines whether the deferred B2B route in §5.4 is worth designing.)
7. App Privacy: given the seal, which identifiers/usage/diagnostics must be declared, and does the "user content not collected" answer survive the relay's metadata handling?

---

## 5. Alternatives considered and rejected

| # | Alternative | Verdict | Why |
|---|---|---|---|
| 1 | **Paid app download** ($4.99–$9.99, one-time) | Rejected | (a) kills the free distribution funnel (TestFlight, source builds, the Android sibling sharing the core) and makes the app "not functional without purchase" — exactly the risk §4 exists to avoid; (b) $9 one-time buys ~1.7 months of the paid tier's *support* cost, so it cannot fund the service it implies; (c) it prices the client, and our own thesis (§2) is that the client is not the thing worth paying for. The client stays free and Apache 2.0 forever. |
| 2 | **Ads / sponsored content** | Rejected | (a) "no ads, no tracking, no accounts" is a real differentiator for a tool that reads your source code and prompts; (b) ad revenue for a developer-tools audience is cents per user-month (band $0.05–$0.50) — irrelevant next to $9.99; (c) ads force an ATT prompt and a data-collection posture that contradicts the listing and the App Privacy answers. |
| 3 | **Reselling AI credits / tokens** | Rejected | §3.6 — margin inversion, vendor-rate dependency, pure pass-through support load, loss of provider neutrality. |
| 4 | **Enterprise / B2B seat licensing** | Deferred, not rejected | Requires an org model, per-seat entitlements, an admin console and a web console — none exist, and there is no demand signal. The B2B-shaped artifact worth building later is a **hosted team relay with a web console**, which is also the natural home for a web-only checkout — and the first thing that forces accounts (5.1.1(v), §4.2). Revisit only on a named inbound request (Q7). Do not pre-build the org model. |
| 5 | **White-label / OEM licensing** | Rejected | The app's value is deep, specific OpenCode protocol knowledge (V1/V2 wire formats, SSE event shapes, the client-capability protocol, the watch bridge, task-notification cards). White-labeling means maintaining a compatibility matrix against servers we do not control — the same burden that left the Watch app *Experimental*. It is also a services business that would consume the capacity needed for the relay and push. Revisit only for a specific partner with budget. |
| 6 | **Re-license the client** (Apache 2.0 → proprietary/BUSL) | Rejected | The free, open client is the distribution engine; the audience would revolt and the network effect dies. Monetize the service; the code stays Apache 2.0 permanently. |
| 7 | **A paid "Pro" unlock of app features** (no service) | Rejected | Sells nothing the user cannot already have, forces an IAP for things that should be free (App Review optics), and discourages the server-side connector install the real product needs. |
| 8 | **One-time purchase bundling a relay month** | Rejected | Bundling a service into a one-time purchase converts a variable-cost service into a fixed-price liability and destroys the ability to price support. Services are subscriptions; one-time purchases acknowledge the project. |
| 9 | **Hosted sync / archive of transcripts and session history** | Rejected *for now* — the strongest near-term revenue idea we are choosing not to build | It requires the operator to hold or index user content, which falsifies "no cloud service of ours involved" (`docs/appstore/review-notes.md`), flips the App Privacy questionnaire away from "Data Not Collected", and creates a second copy of data the user's server already has. It also converts the relay from "blind bus" into "data product", which is the single change most likely to destroy the trust advantage the relay is bought for. Revisit only as a **separate product with its own privacy posture** (Q10), never as a line item bolted onto Connect. |

---

## 6. What would have to be true

Falsifiable. Each test is designed to cost a weekend and <$50, and none require shipping the app.

| # | Question | Cheapest test | Pass criterion | Cost |
|---|---|---|---|---|
| V1 | Will users pay for **reachability** at all, or is the free substitute (Tailscale + a $5 VPS) enough? | Concierge relay: one $6 VPS + hand-managed tunnels for 10 recruited users; landing page with a Stripe link at $9.99; no app build | ≥3 of 10 say yes at $9.99 **and** ≥2 pay a deposit | ~$20 + a page |
| V2 | Is **push** the #1 hook or a nice-to-have? | Build the single-host spike the push research already scopes (`../push_notifications/research.md`): connector → relay → APNs → device token; run 2 weeks with 5–10 users | ≥60% of participants unblocked ≥1 agent by push that would otherwise have stalled ≥30 min | 1 dev-week + $12/mo |
| V3 | **Can support be funded at this price?** (gates the annual plan) | Run the V1 concierge for 4 weeks with a public status page, a fixed onboarding doc and a contact log | ≤0.25 contacts/user/quarter, median resolution ≤30 min, ≥80% of sessions need no human | ~$0 on top of V1 |
| V4 | Does Community stay a complete, desirable product (i.e. can we never move a shipped feature behind the paywall)? | Cohort the beta: 30-day retention of free users who enroll no connector vs those who do; ship nothing behind the paywall for 60 days | Free-cohort 30-day retention ≥ paid-cohort − 5 pts; zero "I upgraded for this" complaints | $0 |
| V5 | Is **recall/search** wanted at all, and if so **where must it live** to stay sellable? | On-device prototype: index session messages locally, answer "what did the agent do about X last week?"; 5 users, 1 week | ≥3 of 5 ask a question the current app cannot answer, ≥1×/week — **and** ≥3 of 5 would refuse a hosted index that reads their transcripts | ≤3 dev-days |
| V6 | Will users tolerate **installing a connector on their server**? (gates the push design) | Onboarding test with 5 OpenCode users who have never installed one: time-to-first-push | Median < 15 min, zero support contacts | 1 day |
| V7 | Is **$9.99** the right number, and is it demand-elastic? | Landing page, three price points ($6.99 / $9.99 / $14.99), split traffic, no app build | ≥5% visitor→paid at $9.99, **or** $14.99 converting better than $9.99 (then price up) | $0 |
| V8 | Does Community survive App Review as "fully functional without purchase", and does the relay trip 2.5.4? | Pre-submission review request, or a TestFlight review cycle with the Connect code compiled out | Review passes with no IAP or VPN questions | 1 build + 1 review cycle |
| V9 | Does the **supporter tier** find buyers? | Offer $49 to 100 people on the launch page (no in-app involvement) | ≥15 sales in 60 days | $0 |

**Kill criterion.** If **V1 and V2 both fail**, Connect is not built. The app stays free forever, the supporter tier (V9) becomes the only monetization, and this record is closed as *"the product is free; we did not find a business."* That outcome must be decided in advance, not after a quarter of unpaid infra.

---

## 7. Open questions and the decision each blocks

| # | Open question | Blocks | Recommendation / default |
|---|---|---|---|
| Q1 | **Payment route** — App Store IAP only, or IAP + an external (web) checkout? | The entire revenue design — this is the companion design's OQ-1 | **IAP-first.** One price, sold through the App Store; no external purchase links inside the app. Revisit only if V7 shows a large annual/team segment that IAP cannot serve. |
| Q2 | **Identity** — zero-account (device-scoped relay credential) or Sign in with Apple / an account? | Relay auth, the PII surface, the privacy label, 5.1.1(v) deletion scope, whether an external checkout is even possible | **Zero account in v1**: StoreKit 2 JWS → entitlement service → device-scoped relay credential in the Keychain, mirroring the existing `opencode pair` → Keychain flow (`PairingClient`, `KeychainHelper`). Accounts arrive only with a web console (Q7). |
| Q3 | May an external purchase **coexist** with IAP, and what in-app presentation is allowed without steering? | The pricing architecture and the paywall screen design | §4.3(2). Default: single IAP price, no external purchase links in the app, only a "manage subscription" deep link. |
| Q4 | **Do we build a hosted service at all?** | Everything downstream | V1 + V2 are the gate; if they fail, stop (§6 kill criterion). |
| Q5 | Which price point survives contact with a **real support load**? | The annual price and the depth of the annual discount | Launch monthly-only at $9.99; add $89/yr only after V3 measures ≤0.5 contacts/user/quarter. $79/yr is below the support-neutral line at that load. |
| Q6 | Can Watch/Car reach "reliable" **without** a hosted live gateway? | Whether reliable hands-free steering can ever be a paid hook | Treat client features as free; if a hosted live gateway is needed for reliability, sell *that* as a separate Connect component, not the watch app. |
| Q7 | Is there real **team/organization demand** (multi-host fleet, shared archive, per-seat)? | B2B seat licensing, the web console, the org data model, and the first account requirement | Deferred (§5.4). Revisit on the first inbound request with budget; do not pre-build. |
| Q8 | Does Community **ever** need to lose a feature? | The "Community stays complete forever" promise | Rule (§3.2): only features that require us to keep a machine awake on the user's behalf may ever be paid. Changing that rule re-opens this record. |
| Q9 | Does the App Store accept a relay whose **service is consumed in-app** but provisioned off-platform, and does it read as tunneling (2.5.4)? | Whether Connect can exist in the App Store build at all | §4.3(1) and (4). Until answered, design Connect **IAP-first** and keep the relay a plain-TLS sealed bus (no Network Extension), so either answer is shippable. |
| Q10 | Where must **recall/search** live — on-device, on the user's own server, or in a hosted index with a different privacy posture? | Whether §2.1 #4 ever becomes revenue, and whether the "blind bus" invariant survives | Default: **not hosted.** Ship the on-device index free (V5) and keep the relay content-blind. A hosted index is a separate product decision with its own privacy policy, terms and account deletion — not a Connect line item. |
| Q11 | What does "**sync**" mean here — session fan-out, the sealed offline queue, or device state? | The relay wire spec, the archive schema, the cost model | v1 = fan-out + sealed TTL queue only (Connect component 3). Device state, drafts and host profiles stay local unless V5 says otherwise. |

---

## Appendix A — Cost model and price arithmetic

### A.1 Assumptions register

| ID | Assumption | Value | Falsified by |
|---|---|---|---|
| A1 | Loaded support cost | $80/h | — |
| A2 | Handling time per paid-tier contact | 25 min → **$33/contact** | V3 |
| A3 | Support load at launch | **0.5 contacts/user/quarter** (band 0.25–1.0) | V3 |
| A4 | Relay compute (2 × $24/mo for HA) + APNs gateway ($12/mo) + metadata DB ($10/mo) | **$0.07/user/mo** at 1,000 payers | — |
| A5 | Egress (relay fan-out + sealed queue), ~1 h/day of agent streaming for ~30% of users | **$0.05–$0.25/user/mo** | first 100 payers |
| A6 | **Planning figure for infra** | **$0.25/user/mo** | — |
| A7 | Payment | IAP 15% → $1.50 on $9.99; web 2.9% + $0.30 → $0.59 | — |
| A8 | Target margin after support + infra | ≥65% | — |

### A.2 Unit economics at $9.99/mo (IAP 15% → net $8.49)

| Support load | Support $/user/mo | Infra | Profit/user/mo | Margin |
|---|---|---|---|---|
| 0.25 contacts/qtr | $2.75 | $0.25 | **$5.49** | 65% |
| 0.50 contacts/qtr | $5.50 | $0.25 | **$2.74** | 32% |
| 1.00 contacts/qtr | $11.00 | $0.25 | −$2.76 | −33% |

### A.3 Floor, ceiling, annual

- **Floor:** to cover support + infra at 0.5 contacts/quarter, net must be ≥ $5.75 ⇒ price ≥ $6.76 ⇒ **$6.99/mo is the hard floor** (≈3% margin at that load). Below $6.99 every additional payer loses money.
- **Ceiling:** a motivated user can already reach their server for ~$0–5/mo (Tailscale personal free tier — *unverified, needs check* — or a $4–6 VPS plus a free tunnel). **Connect therefore cannot be sold on capability**; it must be sold on "it just works, plus push." Recommend **$9.99/mo**.
- **Annual:** support-neutral annual price at 0.5 contacts/quarter = 12 × $5.75 ÷ 0.85 = **$81.2** ⇒ recommend **$89/yr (26% off)**. At a measured 0.25 contacts/quarter the floor falls to $40.6 and $79/yr (34% off) becomes affordable. **Do not ship an annual plan before V3.**
- **One-line economics:** Connect is a *support* business with a cost of goods of ~$0.25/user/month. The margin is won in the error-message layer and in self-serve diagnostics, not in the price.

### A.4 What this decision will touch later (nothing modified by this record)

`docs/appstore/app-privacy.md` (rewrite: "Data Not Collected" no longer holds) · `docs/appstore/privacy-policy.md` + a new Terms of Service · `docs/appstore/metadata.md` ("In-app purchases: No") · `docs/appstore/review-notes.md` · `docs/appstore/submission-checklist.md` · `../hosted_relay/design.md` (OQ-1 answered by §4) · `../push_notifications/research.md` (the spike to build) · `../client_capabilities/protocol.md` (connector surface) · `docs/README.md` (features index — **this directory must be added; not modified by this record**) · `docs/WORKING.md` (decision-log entry — **not modified by this record**).
