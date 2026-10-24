# Visual Writing Weapon System: Discussion Draft v2

> This document is not a conclusion, it is an anchor for discussion; it is also dogfood —— it is itself written according to the low-cognitive-burden principle, to test whether that principle can bear the weight.
>
> v2 changes: absorbed the criticism of three sub-agents, cutting the "four axes" down to "1 tension axis + adaptive path + 1 pre-gate + 1 uncertainty axis"; anti-patterns were split by severity; self-eval changed from questions into scan actions; the original debate was collected into `<details>` at the end of the document.
>
> v2.1 changes (reader feedback): moved "attention budget" from a tension axis to an input of the adaptive path —— it should not be preset to 30 seconds or 30 minutes; the document should carry both trajectories at once. Only this reframe can catch counterexamples like "first draft vs heavily revised draft of the same RFC".
>
> **2026-06-14 status update**: the methodology itself has sunk into the "Visual Cognitive Load Reduction" section of `rules/skills/workflow_internal_writing.md` (outside this repo path, under `knowledge_working/rules/skills/`). It covers the three axioms, the weapon library overview, the adaptive path mechanism, the delta versus the old markdown-first practice, and the things not yet decided. **This document is kept as a dogfood case analysis, recording the complete path of "one PRD/RFC dogfood + three sub-agent debates"**. For the live methodology, read the skill; this is the historical entry point.

## The Real Question

Not "should we use visual or not", and not "should we use it more or less". Both of those are fake questions. The real question is:

> **When an AI writes an internal document, when does visual genuinely reduce the load, and when does visual add false signals?**

If this question can be carved into the AI writing loop, then how many weapons to use, how long they should be, and whether to use a chip are all natural corollaries.

## Evidence First: 8 anti-patterns, dug out of real dogfood material

These 8 are not imagined: they are the ground truth that the anti-pattern hunter found in the real document I had just written. Sorted by "severity × fix cost", the first 3 **must be tackled first over the weekend**.

<style>
.ap-grid{display:grid;grid-template-columns:1fr;gap:8px;margin:12px 0}
.ap-crit{padding:10px 12px;border-left:4px solid var(--bad-border,#ef4444);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-form{padding:10px 12px;border-left:4px solid var(--warn-border,#f59e0b);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-style{padding:10px 12px;border-left:4px solid var(--block-border,#6b7280);background:var(--card-bg,#fafbfc);color:var(--fg,#243244);border-radius:0 8px 8px 0}
.ap-grid h4{margin:0 0 4px;font-size:.95rem;color:var(--fg,#243244)}
.ap-evi{display:block;margin:3px 0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85rem;color:var(--link,#2e5c8a)}
.ap-grid p{margin:3px 0;font-size:.9rem;color:var(--fg,#243244)}
</style>

<div class="ap-grid">

<div class="ap-crit">
<h4>① Cross-document contradictions (must be fixed immediately)</h4>
<span class="ap-evi">Evidence · child PRD §5.1 keeps the strikethrough "~~Native by default~~ Updated: Web by default"; child RFC §12 still says "Decision: do not default for now"</span>
<p>The same decision circulates in 5 versions (child PRD / child RFC / main PRD / main RFC / WORKING), but only 2 made it into git. Readers have no idea which one is the source of truth.</p>
</div>

<div class="ap-crit">
<h4>② Table + card mirrored as "fallback", double maintenance (must be fixed immediately)</h4>
<span class="ap-evi">Evidence · visual_explainer_html_md.md "first-screen status card" + "pure Markdown fallback" correspond item by item</span>
<p>The reason is renderer compatibility; the cost is maintaining the same information twice. Missing one edit makes them inconsistent; the fallback should be a rendering degradation, not a hand-copied duplicate.</p>
</div>

<div class="ap-crit">
<h4>③ <code>&lt;details&gt;</code> holding core conclusions instead of optional material (must be fixed immediately)</h4>
<span class="ap-evi">Evidence · the details in main RFC §7.5 stuff in rendering paths / JS dependencies / the security model —— these are exactly the target content for engineering readers of the RFC</span>
<p>"Expand on demand" implies optional reading, but the content is mandatory. Readers either click it open — in which case the folding is pointless — or don't, which degrades the RFC into a marketing page.</p>
</div>

<div class="ap-form">
<h4>④ Decision reversals stacked with strikethroughs + update stamps instead of rewriting the body</h4>
<span class="ap-evi">Evidence · child PRD §5.1 "~~First version keeps Native~~ **Updated (2026-06-14): ...**"</span>
<p>This dumps git history back into the body. This is exactly how document rot accumulates over six months.</p>
</div>

<div class="ap-form">
<h4>⑤ Status classification is too fine-grained and drifts within the document</h4>
<span class="ap-evi">Evidence · visual_explainer_html_md.md switches the chip axis 3 times across different sections</span>
<p>"holds but weak / rejected / candidate / blocked" vs "done / next round" vs "not prioritized / prioritized / parallel" —— readers have to maintain several sets of color-code semantic mappings.</p>
</div>

<div class="ap-form">
<h4>⑥ Chips used as end-of-row status stamps, a single color carrying no information</h4>
<span class="ap-evi">Evidence · OpenCode_iOS_Client_PRD.md §4.3.5 status table: 7 of 8 rows are "shipped"</span>
<p>A chip here has no filtering value and no comparison value; it just puts a capsule around the two characters "shipped". Readers instead have to scan line by line for "what is not finished".<br><em>Note: the existence of this anti-pattern was itself proven by this document's v1, which fumbled it (8 all-red cards) —— v2 only fixed it by splitting the cards into 3 severity tiers.</em></p>
</div>

<div class="ap-style">
<h4>⑦ Status table row keys use Phase/Sprint instead of user experience</h4>
<span class="ap-evi">Evidence · 2026-06_markdown_web_preview_prd.md (archive/) §"Implementation Progress" vs main PRD §4.3.5 — same information, different layout</span>
<p>The same team writing two versions in the same week shows that AI defaults back to engineering sequence. If the order changes after replacing the row key with "what the user sees in the App", then the current ordering is an anti-pattern.</p>
</div>

<div class="ap-style">
<h4>⑧ Titles name categories instead of verdicts</h4>
<span class="ap-evi">Evidence · child RFC §5 "Solution Overview", §6 "Component Design", §7 "Security Model", §8 "UI Design"</span>
<p>The skill already warns against writing "Flowchart" or "Matrix", but "Security Model" is the same problem one level deeper. "Security Model" → "The WebView only runs bundle JS; the sanitizer strips scripts after rendering" — that is a verdict.</p>
</div>

</div>

<p><em>Red border = content/factual error, will mislead readers; orange border = maintenance problem, will rot over the long run; gray border = form problem, tiring to read but not bleeding.</em></p>

## Framing Grown Out of the Evidence

Looking at the 8 anti-patterns above in reverse, what is really in conflict is not "more visual or less visual", but these two tension axes plus two judgment gates, one before and one after.

### One tension axis + adaptive path (block level)

**Axis A · What the reader has to do in this block** — commit-to-action (glance and decide) or explore-to-understand (read through and think it through)?
For the former, visual is a sharp tool; for the latter, visual manufactures the illusion of "I understood it". **Decision signal**: does this block directly follow an action item list / does its title contain a verb? commit. Is this block arguing "why X does not hold" / is it followed by a tradeoff paragraph? explore.

**"Attention budget" is not a tension axis; it is an input signal of the adaptive reading path**. For the same RFC, an intuitive small change only needs the reader to scan it in 30 seconds; a heavily revised draft has readers auditing it paragraph by paragraph. **Presetting the budget to a single static value is wrong, whether it is 30 seconds or 30 minutes** —— the document should carry both trajectories at once. Concrete approach: the first screen provides a skim layer (visual + a one-line takeaway); the body provides deep-reading hooks through anchors / links / `<details>` —— points that look dubious on a skim can zoom in to the evidence, the tradeoff, and the reasoning. This is why we need an HTML extension layer rather than markdown alone: the adaptive path relies on anchors / folding / hover, and markdown by itself is not enough.

The unit of judgment is the **block**, not the **whole document**. A weekly report may be commit on the first screen (status cards on top) and explore below (argument sections must be prose). Locking an entire document to one end of the axis is overfitting.

### Two gates, one before and one after (pass the gates before talking about tension axes)

**Pre-gate · Thickness of shared context** — can the reader decode the semantics of the visual you intend to use?
Reader set ≤ 3 people and within this week = thick; cross-team / cross-quarter / new hires = thin. **If thin, visual is rejected outright, no matter how the tension axis votes**. This gate is not a tension; it is a precondition.

**Post-gate · Factual credibility** — are the underlying conclusions solid?
Visual makes things "look very certain". When the facts are in flux (decision reversals, unsettled data, PRs not yet merged), the certainty of visual appearance becomes a liability —— readers will over-trust it. The root cause of anti-patterns ①②④ is the same: visual packages unsettled facts as certain. **When facts are unsettled, visual is downgraded to a table + timestamp, or plain text.**

## Self-evaluation: three things to scan after writing

Not questions to ask before writing (the AI has no answers), but **scan + threshold + fix path** after writing.

<style>
.se-tbl{margin:8px 0}
.se-tbl table{width:100%;border-collapse:collapse}
.se-tbl th,.se-tbl td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--border,#e6e8eb);color:var(--fg,#243244);font-size:.9rem;vertical-align:top}
.se-tbl th{font-weight:600;background:var(--card-bg,#fafbfc)}
.se-tbl code{font-size:.85rem;background:var(--code-bg,#f0f0f0);padding:1px 5px;border-radius:3px}
</style>

<div class="se-tbl">

| Scan | Threshold = trigger | Fix |
|---|---|---|
| Number of occurrences of the color enum values in the chip column | dominant color ≥ 80% | delete the chip column; exception rows become an end-of-row `⚠ blocked` annotation |
| `grep -r` this paragraph's core conclusion in the current repo | ≥ 2 hits | change the paragraph to `see [path]`, do not copy the text |
| Every `##` / `###` heading: after deleting it, can the first sentence of the body stand alone as a subheading | yes = the heading is a category name | rewrite the heading as that verdict sentence in the body |
| Whether the body contains a strikethrough + a "(date)" stamp | yes = history is back-filled into the body | rewrite the body as the latest decision; move the old version to a changelog at the end |
| After deleting the content inside `<details>`, can the reader still make the primary judgment | no = the details hold the core | move the core out of the details; leave only audit material in the folded section |
| Whether the enum values for chip / status classification are the same set in the earlier and later sections of this document | different = semantic drift | unify the whole document on one set (recommended cap: ok/warn/bad/block) |

</div>

## Weapon Lineage vs Decision Mechanism: not symmetric; the latter is the foundation

The joint optimization the User proposed is a trade-off, but **the two legs are not equally weighted**.

**Foundation: the decision mechanism**. If the AI has internalized "pass the two gates first, then judge the two axes", then even with only 4 weapons (short paragraphs / short tables / details / chips when the distribution is uniform) it will hit the vast majority of scenarios.

**Upper layer: the weapon lineage**. More weapons → the form factor hits precisely and reduces the load deeply in a single pass; but more weapons → higher AI decision cost and error rate. Therefore "adding weapons" must be backed by dogfood evidence (add only after repeated gaps appear); nothing is added just to "enrich the weapon library".

Skill upgrade priority: ① internalize the two gates + two axes (the foundation) → ② write the self-eval scan table as executable guardrails → ③ add the 8 anti-patterns to the failure-mode table → ④ cautiously add weapons (right now there is nothing that must be added).

## A few things not yet decided

1. **Should chips be downgraded altogether?** Anti-pattern ⑥ exposes that in a same-column, same-color scenario the chip is pure decoration. Should chips become "only for anomaly/exception annotations", not appearing by default?
2. **How to fix cross-document copying**: (a) a single source + links from the other documents / (b) accept copying + a last-synced stamp —— (a) is clean but readers have to jump; (b) is realistic but will inevitably rot after 6 months.
3. **Standard operating procedure for decision reversals**: directly rewrite the body + move history into a changelog, vs strikethrough + update stamps to preserve the audit trail —— the latter destroys traceability.
4. **The boundary between the "reader intent" and "attention budget" axes**: Framing Skeptic suggested merging them, but I keep two axes —— a boss reading a 6-screen quarterly doc is commit + high budget; once merged, this counterexample gets lost. Is this judgment right?

---

## Appendix: the raw debate of three sub-agents (audit material, optional reading)

<details>
<summary>Framing Skeptic: can the four-axis framing hold up to scrutiny?</summary>

Having read the whole text, I go straight to the attack. I answer in five points and finish with my proposed topology.

**1. Independence of the four axes: one pair is a tautology, one pair is nested**

**Axis 2 (lifecycle) and axis 4 (reader intent) are highly correlated**. A document you read once and discard, its reader is almost certainly commit-to-action; a long-maintained PRD/RFC, its reader is most likely explore-to-understand. The two axes almost co-vary (~70%). But **a retrospective you read yourself six months later** is long-lifecycle + explore; **an onboarding doc for a stranger** is long-lifecycle + commit-to-action. So the two axes cannot be merged, but acknowledge that they co-vary.

**Axis 3 (thickness of shared context) is not a tension axis at all, but a meta-gate**. This is the point of the framework that most deserves to be attacked. Axes 1/2/4 all describe "what the reader has to do, how long the document has to live", at the same level of abstraction; axis 3 describes "whether the reader can decode the semantics of visual". Its mechanism is not "visual is better on this end, worse on the other", but "thin context → any visual must first pay an explanation tax, which may outright reject visual". It is not a parallel dimension of judgment with the first three axes, but a precondition.

**2. Deeper dimensions that were overlooked**

Two candidates genuinely independent of the existing four axes were filtered out:

- **Author proficiency** —— in AI writing scenarios proficiency is a constant (low) and does not constitute a judgment variable
- **Number of readers (1 vs 100)** —— in practice absorbable by axis 3
- **Reader attention budget (30 seconds vs 30 minutes)** —— **this is a genuinely independent new axis, and it is highly explanatory**. Under a 30-second budget, even with an open judgment, the reader can only rely on visual to frame things first; under a 30-minute budget, even with a structured document, the reader is willing to read the explanation behind the tables. The "weekly report vs PRD" comparison in the MD actually mixes two things: judgment structure + attention budget. **Counterexample: writing a 6-screen quarterly doc for the boss** is structured + long budget; the four-axis framework says "use visual", but the boss will read for 30 minutes, and visual becomes noise. **The attention budget axis should be added.**
- **Trust level** —— absorbable by axis 3

**3. Extreme tests**

- Writing a quarterly doc for the boss → the four axes unanimously vote "heavy visual", but the intuition is wrong: the boss reads it paragraph by paragraph. The framework fails, it lacks **attention budget**
- Team comparison of "should we adopt X" options → axis 1 looks structural, but is actually explore-to-understand; axis 4 is commit-to-action. **Axes 1 and 4 conflict directly**, and the framework does not tell you which one to listen to
- A retrospective you read yourself six months later → the four axes unanimously vote "little visual", the framework holds
- A cross-department status update → axes 1/2/4 all vote visual; axis 3 is thin, directly vetoing the first three votes. **Proves axis 3 is a gate, not an axis**

**4. The mixed state of axis 1**

MD's own example already exposes the problem: in the weekly report, "which path holds" is structured visual, "why confidence cannot be used" is open-ended prose. **The two coexisting in the same weekly report** is the norm. The unit of judgment should not be "the whole document" but "the paragraph/block".

**5. Proposed topology**

- Keep two core tension axes: **Axis A the judgment the reader has to make** (original axis 1, block level), **Axis B attention budget × lifecycle** (merged)
- Demote original axis 4 to a sub-case of axis A
- Promote axis 3 to a pre-gate, no longer listed as a tension axis
- Add a third axis: **the author's factual credibility** —— the root cause of anti-patterns ①②④ is that visual makes "looks very certain" exceed the certainty of the underlying facts

Final: **2 tension axes + 1 pre-gate + 1 uncertainty axis**.

</details>

<details>
<summary>Implementation Surgeon: grinding abstract principles into actionable instructions</summary>

**1. Rules that are too abstract**

"Judging which end the reader is at" is intuition for a human, but an empty concept for an AI. Observable signals are needed:

- Signals that the reader has to make a commit decision: the document ends with an action item list / a "Recommended Action" section / the document title contains "weekly report", "status" or "decision"; the author themself will use this document for scheduling within 24 hours
- Signals that the reader has to explore: the document must answer "why X does not hold", contains a "reasoning"/"analysis"/"tradeoff" section, is longer than 2000 characters, and has no actionable checklist at the end
- Signals that the document's lifecycle is short: the filename carries a date / the path is under `weekly_reports/` `status/` `worklog/`
- Signals that shared context is thick: the reader set is ≤ 3 people and they are on the same project in the same week

**2. Reconciling the conflict**

MD anti-pattern 4 vs the skill's "every HTML visual must have a Markdown fallback" —— a surface conflict, not a real one. The fallback carries equivalent information when rendering fails; it is not "presenting two copies side by side for all readers". Reconciliation: the fallback should live inside `<details>`; the visibility of the two copies must be mutually exclusive, and they must not sit side by side on the first screen.

**3. Self-check signals for the 8 anti-patterns**

Usable as is: #2 (details holding the core —— "after deleting the content in the details, can the reader still make the primary judgment?"), #4 (mirroring —— "does every row of the card correspond one-to-one with the table?"), #7 → now #6 (single-color chips —— "is ≥80% of this column the same color?").

These need sharper discriminating signals:

- #1 (Phase/Sprint ordering): "after replacing the row key with 'what the user sees in the App', does the order change? A change = anti-pattern"
- #3 (chip semantic drift): "are the chip color semantics of the earlier sections of this document the same set as the current ones?"
- #5 (cross-document copying): "does grepping the whole repo find this conclusion's text string in ≥2 places?"
- #6 → now #8 (category-name headings): "after deleting this heading, can the first sentence of the body stand alone as a subheading? Yes = category name"
- #8 → now #4 (strikethrough stamps): "does this passage contain a strikethrough or an 'Updated (date)' stamp?"

**4. Self-eval changed into "scan after writing"**

MD's current checklist is all questions, and the AI does not know the answers before writing. Change it into "scans executed after one writing pass":

- Color distribution → "after writing the whole table, count the occurrences of the color enum values in the chip column; if the dominant color is ≥ 80%, delete this column"
- Cross-document copying → "turn this paragraph's core conclusion into a one-line grep; if it hits ≥2 places, change it to a link"
- Heading verdicts → "sweep all H2/H3 and ask each one: 'if the heading is deleted, can the first sentence of the body serve directly as a subheading?'"

The key change: **questions become "action + threshold + fix path" triples**.

**5. The four axes become "four yes/no per paragraph"**

Before writing a visual, all of these must be answered:

1. After reading this paragraph, will the reader take some action within 24 hours?
2. Will this document be edited next week / referenced six months from now? (yes = long lifecycle, visual is a tax)
3. Is the document's target reader set ≤ 3 people and all on this project this week? (no = thin context)
4. After the skim does the reader "make a decision" or "think it through"? (the latter = no visual)

If ≥1 of the four is a "no / think it through", the current paragraph gets no visual. **A hard gate, not a suggestion**.

**6. Classification: skill body vs self-eval**

- Into the skill body (before / during writing): the four-axis yes/no gate, mutual exclusion of HTML fallback visibility, anti-patterns 1/2/6 (they affect the skeleton, so changing them afterwards is expensive)
- Into self-eval (scan after writing): anti-patterns 3/4/7 (a local scan catches them), anti-patterns 5/8 (grep + regex can check them)

</details>

<details>
<summary>Visual Form Critic: does MD's own form hold up?</summary>

**1. The 4-row "real tension axes" table**

Is it lower-burden than a markdown table? **Not obviously**. The table has 2 fixed-width columns and its content is mostly prose; in essence it is "bold label + paragraph". Converting it to pure markdown `**X**:Y<br><sub>example: ...</sub>` loses nothing. The CSS block is an "axis card" form appearing for the first time; readers have to spend a beat learning it, but after learning it they find it is just a table —— negative ROI.

Is the hierarchy jump appropriate? The main heading at 600 weight + the gray secondary em at 0.92x has too weak a contrast. Axis names are recommended at 1rem/700 + circled numbers ① ② ③ ④.

**Change to**: a markdown table with 2 columns, `| Tension axis | visual reduces load / adds burden |`.

**2. The anti-pattern library's 8 red-bordered cards**

**All-red conflicts with #7 itself** —— yes, and awkwardly. 8 all-red cards = an implicit signal of "8 identical danger levels", which is exactly the "single color, no information" that #7 describes. The semantics of chips/red borders were supposed to carry severity; they have now degraded into decorative frames.

**Change to**: introduce two severity tiers. "Must be fixed immediately" (#5/#2/#4) get red borders; "form problems that do not bleed" (#6/#7/#1) get orange or gray borders. With this change, #7 is immediately corroborated by dogfood.

The small gray `.ap-evi` evidence gets skipped. Cards are scanned, and small gray 0.85rem text at the bottom of a card is "decorative metadata". But the evidence is precisely this document's key difference from other empty talk (the ground truth it claims) —— it should be floated up.

**Change to**: move the evidence line from the card bottom to just below the h4, in monochrome monospace.

**Ordering?** Right now 1-8 shows no logic. Sort by "severity + fix cost": #5 → #4 → #2 → #8 → #3 → #7 → #1 → #6.

**3. The two-column "weapon lineage vs decision mechanism" layout**

Are the two columns two sides of the same tradeoff? **Partly**. Both sides are "precision vs internalize cost". Placing them side by side implies "independent dimensions", but the author says in the very next sentence "the two legs are not equally weighted, the decision mechanism is the foundation" —— since they are not symmetric, the two columns mislead.

After collapsing to a single column on mobile, does it still mean anything? No.

**Change to**: remove the two columns, make them two ordinary paragraphs, and make the hierarchy explicit in the labels.

**4. The overall narrative**

The current 6 ## : the real question → four axes → anti-pattern → two legs → checklist → discussion items.

**Problem**: the anti-patterns are this draft's unique evidence; burying them on the third screen is a waste. The frame should grow out of the evidence, rather than establishing the frame first and then hunting for evidence.

**Change to**: move the anti-patterns up to the second section (right after "the real question"), opening with real evidence; the frame becomes "looking at these 8, the real opposition is these two axes + two gates".

**5. `<details>` absent**

It should be dogfooded, and the fact that it is unused right now is a real flaw —— the document explicitly lists details as a key tool while not using a single one. Legitimate things to fold: the raw outputs of the three sub-agent debates (audit trail, not required reading). These are textbook "audit material" use cases, and they demonstrate the positive side of #2 perfectly.

**Change to**: add a `## Appendix` at the end with three details folding in the sub-agent outputs.

---

**One-sentence summary**: the draft is real substance at the level of its argument, but at the level of form there are 3 places where it defeats itself —— the all-red anti-pattern cards collide with #7, the two-column two-legs layout collides with its own statement of "not symmetric", and the document-wide absence of details collides with its own toolkit claims. Fixing these 3 places + floating the anti-patterns up as the opening would let the document actually bear the weight of the principles it advocates.

</details>
