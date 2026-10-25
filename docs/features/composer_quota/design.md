# Composer Usage / Quota Caption — Design

Status: implemented as new files; the `ChatTabView.swift` integration is
specified below but not applied (that file was owned by another session while
this feature was written).

## Bottom Line

The composer's caption row gets a small usage caption: one compact line that
says what this conversation has consumed, e.g.

```text
12.3K tokens · $0.42 used
```

The user's reference for this feature was a *remaining* meter ("74 remaining
credits"). **The OpenCode server exposes no remaining-quota information**, so
the caption cannot honestly show a remaining number today and does not invent
one: it degrades to what the host actually reported — the session's
cumulative tokens and cost — and switches to the "remaining" wording the
moment a provider allowance exists, with **no change to the call sites**.

## What the caption shows today

`ComposerQuota.caption` returns one of:

| Situation | Caption | Example |
|---|---|---|
| Provider allowance reported | remaining, plus the window when the provider names one | `74 credits left · 5h` |
| No allowance, tokens known | compact token count | `12.3K tokens used` |
| No allowance, tokens + cost known | compact token count and cost | `12.3K tokens · $0.42 used` |
| No allowance, cost only | cost | `$0.42 used` |
| Nothing reported | `nil` — the caption renders nothing at all | — |

Degradation rules (all covered by `ComposerQuotaTests`):

- **Nothing known → nothing shown.** `caption` is `nil` and the view renders
  no view at all, so the row does not gain an empty line.
- **A session that consumed nothing has nothing to report.** Tokens `0` and
  cost `0` produce no caption.
- **Malformed numbers are treated as unknown, not as data.** A negative token
  count, a negative cost, or a non-finite cost (`NaN`, `Infinity`) is dropped
  rather than printed.
- **A non-zero cost never rounds to "$0.00".** A cost below one cent prints as
  `<$0.01`.
- **An allowance outranks the consumption.** When the host reports an
  allowance, the caption is the remaining count; what the conversation
  consumed is already on screen in the session list and the context sheet.
- **An exhausted allowance is still reported.** `0 credits left` is
  information, not an absence of information.
- **The unit is never guessed.** The provider's own unit label is used; an
  allowance that arrives without a unit prints the bare count (`74 left`)
  rather than inventing "credits".

## Where the numbers come from

| Quantity | Source | Notes |
|---|---|---|
| Session tokens | `Session.tokens` (`input` / `output` / `reasoning` / `cache` / `total`) | Server-maintained aggregate, pushed with `session.updated`. Falls back to the app's message-window sum when the host omits it (`AppState.sessionTotalTokens`). |
| Session cost | `Session.cost` | Server-maintained aggregate, USD. Summed over the conversation tree by the adapter. |
| Context/output limits | `ProviderModel.limit` (`context`, `output`) | **Not** a balance: static per-model capabilities that do not shrink while a session runs. They can never stand in for a remaining quota. |

`AppState.composerQuota` (in `Models/ComposerQuota.swift`) is the single
adapter that assembles this. It covers the whole conversation tree — the
session plus its subagent sessions — so the token count and the cost in the
caption always describe the same scope.

## What the server would need to expose for a true "remaining" meter

**Missing field: `quota.remaining` on the session payload** — a number of
allowance units still available for the session's provider, together with
`quota.unit` (the string that says what one unit is) and, for a graphical
meter, `quota.total` and `quota.resets_at`.

Today the V2 session payload (`GET /api/session/:id`, unwrap `data`) carries
`tokens` and `cost` and nothing else:

```jsonc
{
  "data": {
    "id": "ses_1",
    "tokens": { "total": 12300, "input": 10000, "output": 2000, "reasoning": 300 },
    "cost": 0.42
    // ← no quota / allowance / remaining / limit-to-spend field
  }
}
```

The allowance the server would have to add, in the same envelope:

```jsonc
{
  "data": {
    "id": "ses_1",
    "tokens": { "total": 12300 },
    "cost": 0.42,
    "quota": {
      "provider": "codex",
      "unit": "credit",          // what one unit is — without it the client
                                 // would have to guess whether 74 means
                                 // credits, requests or minutes
      "remaining": 74,           // ← the missing field
      "total": 100,              // needed for a meter's fill fraction
      "resets_at": 1760000000000 // when the window resets (ms since epoch)
    }
  }
}
```

Why each part matters:

- `remaining` without `unit` cannot be printed honestly. "74 credits" vs
  "74 requests" vs "74 minutes" are different facts, and the client must not
  pick one.
- `total` is what turns the caption into a meter (a bar needs a fraction).
  `ComposerQuota.Allowance.total` already carries it, so the view can grow a
  meter without a second data path.
- `resets_at` is what makes a remaining number meaningful over time ("74
  credits left, resets in 3h"). The allowance type already has a `window`
  slot for the window's label ("5h", "Weekly").

### The quota data that already exists in the app (and why the caption does not use it)

The app has an unrelated quota source: the **AI Usage Dashboard** configured
in Settings (`aiUsageDashboardURL` → `GET /api/v1/quotas`). It returns
`remaining_percentage`, `remaining`, `usage` and `next_reset_*` per
provider + window label, and it feeds the toolbar badge
(`AIUsageQuotaButton`). The caption does not use it, for four reasons:

1. It is **not the OpenCode server** — it is a separate, user-configured URL
   unrelated to the OpenCode API (see `docs/v2_server_compatibility.md`:
   "quota reads a dedicated dashboard URL unrelated to the OpenCode API").
2. It is **opt-in**: with no dashboard URL set, `isAIUsageQuotaConfigured` is
   `false` and there is nothing to show.
3. It reports a **percentage and an opaque count** without declaring a unit,
   so the client cannot honestly label 74 as "credits".
4. It is **per provider window**, not per session, and it is not tied to the
   conversation in the composer.

When the OpenCode server grows a real allowance, the server's field wins and
the dashboard stays where it is (the toolbar badge).

## Integration into `composerContextRow`

`ChatTabView.swift` is owned by another session, so the patch is specified
here instead of applied. The current row (ChatTabView.swift, `composerContextRow`):

```swift
    private var composerContextRow: some View {
        HStack(spacing: DesignSpacing.sm) {
            ChatModelChip(state: state)
                .glassSurface(cornerRadius: 15)
            ChatTodoChip(state: state)
                .glassSurface(cornerRadius: 15)
            Spacer(minLength: 0)
            if shouldShowComposerStatus {
                quietComposerStatus
                    .layoutPriority(1)
                    .lineLimit(1)
            }
        }
    }
```

The patch — one view added to the trailing group, before the live status:

```swift
    private var composerContextRow: some View {
        HStack(spacing: DesignSpacing.sm) {
            ChatModelChip(state: state)
                .glassSurface(cornerRadius: 15)
            ChatTodoChip(state: state)
                .glassSurface(cornerRadius: 15)
            Spacer(minLength: 0)
            ComposerQuotaCaption(quota: state.composerQuota)
                .lineLimit(1)
            if shouldShowComposerStatus {
                quietComposerStatus
                    .layoutPriority(1)
                    .lineLimit(1)
            }
        }
    }
```

Notes on the placement:

- The caption sits in the trailing group, next to the live status, so the
  two read as one band of "what is happening / what it cost".
- The status keeps `layoutPriority(1)`; the caption has the default priority
  and is the first thing to give up room, so it truncates (tail) instead of
  squeezing the model chip.
- `ComposerQuotaCaption` renders **nothing** when there is nothing to report,
  so the row's layout is unchanged for a fresh session or a host that reports
  no usage.
- No call site changes when a provider allowance arrives: `state.composerQuota`
  is the only place that learns about it.

## Files

| File | Role |
|---|---|
| `OpenCodeClient/OpenCodeClient/Models/ComposerQuota.swift` | The value type (`ComposerQuota`, `ComposerQuota.Allowance`), the caption formatting, and the `AppState.composerQuota` adapter — the single plug-in point for a future provider allowance. |
| `OpenCodeClient/OpenCodeClient/Views/Chat/ComposerQuotaCaption.swift` | The SwiftUI caption: one line, truncating, Dynamic Type aware, design tokens only. |
| `OpenCodeClient/OpenCodeClientTests/ComposerQuotaTests.swift` | Formatting, degradation and boundary tests (Swift Testing). |
| `docs/features/composer_quota/design.md` | This note. |

## Visual / accessibility decisions

- Design tokens only: `DesignTypography.micro`, `DesignColors.Neutral.textSecondary`
  (the text) and `DesignColors.Neutral.textTertiary` (the glyph),
  `DesignSpacing.xs` (the gap). No raw colors, no semantic system font
  literal, no numeric padding, no ad-hoc opacity.
- Light and dark: the caption uses `Color.secondary` / `tertiaryLabel`
  through the tokens, so it reads as secondary text in both schemes and never
  introduces a new hue.
- The text is `DesignTypography.micro` (`.caption`), so it scales with the
  reader's text size. It is capped at `.xxxLarge`: the caption shares one row
  with the model chip, the todo chip and the live status, and past the
  accessibility sizes the composer block itself would break. The row is a
  caption, not body copy — the same numbers are available in full in the
  session list and the context sheet.
- One line, truncated at the tail.
- VoiceOver reads a spoken form (`"74 credits remaining, 5h window"` /
  `"Session usage: 12.3K tokens, $0.42"`), not the raw glyph.
- Accessibility identifier: `composer-quota-caption`.

## Known limitations

- **Not localized yet.** The caption's copy is built in `ComposerQuota`
  because `L10n.swift` is owned by another session in this change. Proper
  localization needs new keys (`composerQuotaTokensUsed`,
  `composerQuotaCostUsed`, `composerQuotaRemaining`, …) and a follow-up that
  edits `L10n.swift`.
- **English-only pluralisation.** The unit is pluralised with a `+ "s"` rule
  (`credit` → `credits`). A localized unit would need its plural form from
  the provider.
- **The cost is USD.** The server reports a bare number; the caption renders
  it as dollars.

## Acceptance criteria

1. With a session that reported tokens and cost, the composer caption reads
   `12.3K tokens · $0.42 used` and stays on one line.
2. With a session that reported tokens only, it reads `12.3K tokens used`.
3. With a session that reported cost only, it reads `$0.42 used`.
4. With no reported usage at all, the caption renders no view — the row is
   unchanged.
5. A provider allowance, when present, renders `74 credits left` (plus the
   window when the provider names one) and takes precedence over the
   consumption figures.
6. No caption ever shows a remaining number the host did not report.
7. Malformed input (negative or non-finite numbers) is ignored, not printed.
8. A cost below one cent reads `<$0.01`, never `$0.00`.
9. The caption uses design tokens only and reads as secondary text in both
   light and dark mode.
10. The caption scales with Dynamic Type up to the accessibility sizes and
    truncates at the tail rather than wrapping.
11. VoiceOver announces the numbers ("74 credits remaining", "Session usage:
    12.3K tokens, $0.42").
12. The integration into `composerContextRow` is a single added view; no
    other call site changes when a provider allowance is added later.
