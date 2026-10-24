# qwen38 rendering issue investigation and fix work record

Records the investigation, root cause and fix for the OpenCode iOS client, where outputs under qwen-3.8-27b (the qwen38 preset) show large numbers of superfluous carriage returns and, occasionally, leaked `<think> / </think>` thinking tags in the body text.

## Conclusion First

**The main bug is in the iOS client rendering layer, not in the OpenCode server.**

For the same data returned by the server, both the Web and the Android client render it correctly (no superfluous carriage returns, no think tag leaks); only iOS displays the leading / trailing newlines in a text part, newline-only parts, and the think tags that leaked into the text part verbatim. The fix direction is to make the iOS client normalize text parts the same way Web / Android do: trim, skip whitespace-only parts, and remove the thinking content that leaked into text parts.

Two boundary clarifications (corrected after an independent review):

- The newlines themselves are part of the output shape of qwen38 / SGLang; the server stores them verbatim and returns them verbatim —— this is not a server "bug", it is that iOS lacks the normalization that Web / Android already have.
- think tag leakage is **not** a systemic problem of qwen38: in a clean qwen38 session (`ses_fcfbff756ffe`, 219 text parts) there are 0 think tags. Most of the think tags in the current session come from this investigation itself "discussing" those tags, plus a few `<think> / </think>` split tails.

## Symptoms

- When the user talks to qwen38 in the iOS app (`RadixArk/Qwen3.8-27B-NVFP4`, SGLang endpoint `http://none.tail63c3c5.ts.net:8002/v1`), the replies contain large numbers of blank lines / superfluous carriage returns, with occasional literal `<think> / </think>` tags.
- Other models, and qwen38 on the Web / Android clients, do not show this phenomenon.
- The user initially suspected an iOS client bug and asked for investigation first, without touching code.

## Investigation Process

### 1. Data layer: confirm that the text parts returned by the server do carry these artifacts

Ran cross-model statistics over the `message` / `part` tables of `~/.local/share/opencode/opencode.db` (excluding the session under investigation itself, to avoid self-contamination):

| Metric | qwen38 | Other models |
|---|---|---|
| text parts starting with `\n` | 99% | 0% |
| text parts ending with `\n` | 92% | ~0% |
| text parts that are pure newlines (no actual content) | 65% | ~0% |
| text parts containing `\n\n\n` | 24% | very few |
| Average newline count per text part | 12.15 | 2.5–3.2 |

Then re-verified with the live API (`GET /session/:id/message`, Basic auth `opencode:<OPENCODE_PASSWORD>`; the credential is `OPENCODE_PASSWORD` in the workspace `.env`): the current session (`ses_fcfbd043bffe417xHHYrV0gw37`, active, counts are a moving target) had 58 text parts containing think tags at the moment of review; but compared against the clean qwen38 session (`ses_fcfbff756ffe`: 219 text, 161 whitespace-only, **0 think**), we can see that most of the think tags in the current session come from this investigation discussing the tags themselves, plus a few `<think> / </think>` split tails (SGLang streaming cuts at the wrong position at the reasoning / content boundary). So think tag leakage is **session-specific + a few split tails**, not a systemic output problem of qwen38.

The server only stores the model output verbatim and returns it verbatim; it performs no normalization —— normalization is the client's responsibility.

### 2. Comparison: how Web / Android render the same data correctly

- **Web** (`opencode-official/packages/session-ui`):
  - `message-part-text.ts:2` applies `.trim()` to the part text;
  - `message-part.tsx:717`, `session-turn.tsx:108,311` use `part.text?.trim()` as the test, and whitespace-only text parts are not rendered at all;
  - the DOMPurify in `markdown-cache.tsx` does not list `think` among the allowed tags, so unknown tags get stripped.
  - In other words, Web explicitly does trim + skipping empty text parts + stripping unknown tags.
- **Android** (`opencode_android_client/.../ChatMessageContent.kt`): the text part is handed to the CommonMark-family `Markdown` renderer (`com.mikepenz.markdown`, dispatch at `:436`, render at `:776`), whitespace is collapsed and empty paragraphs produce no visible blank lines, so there is no "pile of carriage returns".

Both sides prove the same thing: this data itself can be rendered correctly; the problem is in iOS's rendering layer.

### 3. Locating the iOS rendering defect (`MessageRowView.swift`)

- `buildAssistantBlocks(parts:)`: `isReasoning` parts are skipped (they go through the thinking block renderer), `isText` parts go through `markdownText`.
- `markdownText` → `shouldRenderMarkdown` / `hasMarkdownSyntax`: for whitespace-only text (empty after trimming) it returns false, so it falls through to the native `Text(text)`.
- The native `Text` renders every `\n` as a visible blank line → the user sees "a pile of carriage returns".
- The `<think> / </think>` tags that leaked into a text part are rendered as literal text.

### 4. Cross-validation against the SGLang reasoning parser (2026-08-23, SGLang source `none:~/co/llm_serving`)

The launch parameters of the running SGLang endpoint `none.tail63c3c5.ts.net:8002` (`serve_llm.sh`, confirmed against the live process): `--reasoning-parser qwen3 --tool-call-parser qwen3_coder --speculative-algorithm DFLASH --speculative-num-draft-tokens 8`.

In `vendor/sglang/python/sglang/srt/parser/reasoning_parser.py`, `Qwen3Detector` (:355) inherits `BaseReasoningFormatDetector` (:62), and the streaming state machine is **one-shot**:

- :206-211: `stripped_think_start` is a one-shot marker, it strips only the first `<think>`;
- :214-225: the **first** `</think>` encountered permanently turns reasoning off (:220 `_in_reasoning = False`, it never goes back to True afterwards);
- :260-263: after leaving reasoning, all content is passed through verbatim as `normal_text` —— including literal `<think>` / `</think>`.

The OpenAI-compatible endpoint (`serving_chat.py` constructs `ReasoningParser` at :222-238, outputs `reasoning_content` at :738 / :1923) maps `reasoning_text` to `reasoning_content` (stored by OpenCode as a reasoning part), and `normal_text` to `content` (stored by OpenCode as a text part).

Data cross-validation (189 assistant messages in the current session):

- The part sequence of all 189 messages is uniformly `step-start / reasoning / text / step-finish / tool...` —— each message has exactly 1 reasoning part + 1 text part;
- Of the 189 reasoning parts, 0 contain literal think tags; 62 text parts (33%) contain tags, of which 61 contain at least one **standalone-on-its-own-line** (outside code fences) `</think>`;
- **Decisive evidence**: in the messages whose text part contains a leak, the reasoning part is truncated mid-sentence, and the text part continues exactly from the second half of that same sentence. Example: one reasoning part ends with “...thought output uses `” (truncated mid-sentence, backtick not closed), while the text part of the same message starts with “` tags. In OpenCode, reasoning parts are separated...” —— the same sentence was cut in the middle by SGLang.

The mechanism closes the loop: the model emits a literal `</think>` inside its own thinking (this session was investigating the think tag bug, so the model repeatedly discusses / restates those labels while thinking), the SGLang state machine takes the literal `</think>` in the thinking as the real terminator → reasoning ends early → the remaining thinking + the real `</think>` all leak into the content stream → OpenCode stores it verbatim as a text part → iOS renders it verbatim. A clean session (no literal `</think>` while thinking) has 0 leaks; this session leaks 33%, directly correlated with "the probability of the model writing a literal `</think>` while thinking". SGLang's tokenizer layer cannot distinguish "the model output the tag as text" from "the model ended its thinking", so the ambiguity can only be absorbed in the client's normalization layer —— fixing the iOS rendering layer is the right place.

Data validation of the observation "the response starts with a code block": of the 189 text parts, only 1 starts with ``` in raw form, and after simulating the second batch of stripping there are 0 —— this shows it is mainly a stylistic preference of qwen38 (it likes starting with code), not a boundary bug; but the leaked thinking tails often contain code fragments, which on iOS really do create the impression of "the reply starts with code".

## Root Cause

The iOS client does not normalize text parts the way Web / Android do. Specifically:

1. **Whitespace-only text parts fall through to the native `Text` (main cause)**: `hasMarkdownSyntax` returns false for text that is empty after trimming, so it falls through to the native `Text`, which renders every `\n` as a visible blank line.
2. **Leaked thinking content is rendered literally (secondary, session-specific)**: the thinking content that leaked into a text part, along with the literal `<think> / </think>`, is not handled and is displayed as-is (for the SGLang-side mechanism see investigation process §4).

(The server returns the model output verbatim, and Web / Android already normalize it separately, so the problem exists only at the iOS layer.)

## Fix (branch `fix/whitespace-text-parts`)

### First batch: blank part filtering + trim (done, verified)

`MessageRowView.swift`:

- Added `isRenderableText(_:)`: returns false for whitespace-only text.
- `buildAssistantBlocks(parts:)` was extracted into a static, testable function; text parts first pass through `isRenderableText`, and whitespace-only parts are skipped outright (no more blank lines, and they no longer break tool card merging).
- `markdownText` trims before rendering, removing leading / trailing newlines.
- `AssistantBlock` changed from private to internal for testing.

Four new tests were added to `OpenCodeClientTests.swift` (`MessageRenderingHeuristicTests`):

- `renderableTextRejectsWhitespaceOnlyParts`
- `renderableTextAcceptsContentWithSurroundingWhitespace`
- `assistantBlocksSkipsWhitespaceOnlyTextParts`
- `assistantBlocksMergesToolRunAcrossWhitespaceTextPart`

Verification: the simulator build passed; all 11 tests in `MessageRenderingHeuristicTests` passed. The full suite has 2 pre-existing UI test failures (`testSettingsShowsThreeSpeechStrategiesAndRealtimePrompt`, `testToolCardsFixtureRendersFileCardsAndMergedToolCalls`), unrelated to this change.

Known gaps (pointed out by the independent review, not fixed):

- `copyableText` only filters `isEmpty`: `"\n\n\n"` survives and is then joined with `"\n\n"`, so copy / text selection is still a pile of blank lines.
- `selectionText` / the text-selection sheet do not apply the same filtering either.
- The user bubble adds padding for every text part: after an empty part becomes an `EmptyView`, up to 20pt of blank space can still remain (the assistant path skips them, the user path does not).
- `StreamingReasoningView` is still plain `Text`: reasoning parts currently contain no think tags, but if a leak happens in the future it would show up on the reasoning bar.

### Second batch: stripping leaked thinking content (completed 2026-08-23, the approach was revised after a Grok review)

How the approach evolved: the original plan was "strip the whole block + keep only the content after the last `</think>`" → the independent review changed it to a DOMPurify-style "strip only the tags, keep the inner text" → after discussing with the user on 2026-08-23 the focus was corrected once more:

**What the user cares about is not "literal tags being visible" but "thinking content appearing in the reply body".** Content that should have been shown in the thinking block, after leaking into a text part and being displayed as body text, is the core problem. The DOMPurify-style "strip tags, keep content" leaves the leaked thinking content in the body and therefore does not solve the core problem; and a normal reply that happens to be "discussing these tags" is not the user's concern. So the approach changed to **deleting the leaked thinking content from assistant text parts** (not just stripping tags):

- Extract `static func normalizedText(_:)` (unit-testable), applying only to **assistant text parts**; user messages are never modified (when the user themself discusses the tags, they must be preserved verbatim —— the literal `</think>` in this session's user messages is a ready-made example):
  1. Recognize code fences line by line (``` or ~~~, at most 3 leading spaces allowed; an opening fence line may carry an info string, a closing fence line must consist only of fence characters and be no shorter than the opening fence); tags inside a fence (including the fence lines themselves) are never touched —— the server-side parser has zero awareness of code fences, so client-side normalization has to understand fences itself;
  2. Remove the thinking tail (the main rule, **executed first**): if there is a standalone-on-its-own-line </think> (outside a fence), cut from the start of the text up to and including the **last** such closing tag —— SGLang only honors the first close during the reasoning period (`.find()`, any position, inline occurrences count), and a literal close in the model's thinking ends reasoning early, after which the remaining thinking + the real close all land in the text part; the real close is always the last standalone-on-its-own-line close in the part, and the real response (if any) comes after it; if the cut leaves nothing, the part is not renderable;
  3. Remove the open tail: if the remaining portion still has a standalone-on-its-own-line <think> (streaming truncation, no close after it), cut from that line to the end of the text; finally trim the leading and trailing whitespace.
  4. **Ordering decision** (key finding of the Grok review): you cannot first delete the "complete open..close blocks" and then cut the tail —— if the thinking tail contains a literal open example block with no literal close after it, "deleting blocks first" deletes the real close together with its own literal open, and the leaked thinking before it remains in the body; cutting to the last close first is correct in both cases, at the cost described under "known trade-offs".
- **Discrimination basis**: only `<think>` / `</think>` that are **standalone on their own line** (outside code fences) are treated as boundary markers; tags appearing inline (usually with backticks, inside a discussion sentence) are left alone. Data validation: of the 62 text parts containing tags in the current session, 61 contain at least one closing tag that stands on its own line outside a fence; after simulating the processing, 20 pure thinking-tail parts become empty.
- `buildAssistantBlocks`: text parts that are empty after normalization are skipped (extending the existing whitespace-only skip; "pure thinking tail" parts no longer produce blank lines and no longer break tool card merging).
- `markdownText`: assistant parts go through `normalizedText` before rendering (user parts keep the first batch's trim).
- `copyableText`: each part first goes through `normalizedText` (assistant) / trim (user), parts that are empty after normalization are filtered out, and the rest are joined with "\n\n" —— fixing the gap where whitespace-only parts (such as "\n\n\n") survived and were then joined.
- `selectionText` / the selection sheet: the input is `copyableText` itself, so it is fixed along with the copy construction and the function itself needs no change.
- The user bubble padding gap (task item 3): the ForEach in `userMessageView` now iterates only over text parts that pass `isRenderableText`, so empty parts no longer produce a 20pt padding box.
- `StreamingReasoningView` (task item 4, recorded only): reasoning parts currently contain think tags in 0 of 189 cases (verified); if a leak reaches the reasoning channel in the future, it would show on the reasoning bar —— acceptable, since the reasoning bar is where thinking content is displayed anyway; reuse `normalizedText` if it is really needed.

Tests still to be added (following the `MessageRenderingHeuristicTests` style; the tag constants in Swift are constructed with "\u{3C}think\u{3E}" / "\u{3C}/think\u{3E}"):

- deleting a complete thinking block (open line + content + close line + real response → only the response remains)
- a pure thinking-tail part → empty string
- thinking tail + a real response at the end → only the response remains
- inline tags (backticks / mid-sentence) are left alone
- tags inside code fences are left alone
- a tail containing literal open/close example blocks → still only the content after the last close remains (ordering regression)
- `copyableText` normalization (whitespace part + thinking-tail part + real part → no extra blank lines, no thinking content)
- `copyableText` does not modify user messages
- `buildAssistantBlocks` skips "pure thinking tail" parts and tool merging is preserved

Known trade-off (the cost of the ordering decision): if the model quotes an example thinking block in an ordinary reply using a tag that is **standalone on its own line** (and not inside a code fence), everything from the start of the text up to that example's close (including the text preceding the example) gets cut. The user has explicitly said this case is out of the concern scope; examples inside code fences are unaffected.

Another residual case: if the literal close in the thinking is **inline** (not standalone on its own line) and is followed by no standalone-on-its-own-line close at all (only 1 of the current session's 62 tagged text parts is like this), then the text part has no identifiable split boundary and the leaked thinking is preserved verbatim. The Web client has the same lack of recognition ability (behaves identically); there is no reliable signal to cut on, so this is accepted as not fixed.
### Third batch: empirical rendering path on the simulator (paused, for this investigation only)

- Added a `render-part` debug log to `loadMessages` in `AppState+Messages.swift`: for every text / reasoning part of every assistant message it logs `type` (the server's raw type), `isReasoning` / `isText` (the app's classification), and a newline-visualized content preview (first 160 characters).
  - Chosen at loadMessages rather than in the view: the view body is recomputed on every render pass (the log would flood the screen), while loadMessages runs only once per fetch, and it is the first place where raw server data lands.
- Already built + installed onto the booted simulator (iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323`, iOS 26.3).
- **This log does not go into the production PR**: the body preview is `privacy: .public`, and it covers only `loadMessages`, not the SSE streaming path. Keeping it long-term requires redacting the preview and covering SSE as well.
- Not done: seeding the simulator credential (the UserDefaults `serverURL` / `username` are already written; the Keychain password is still pending —— there is no `security` binary inside the simulator, spawning a custom binary also fails, so a different seeding approach is needed), then deep link `opencode://session/ses_fcfbd043bffe417xHHYrV0gw37` and capture os_log.

## Independent review (Grok, 2026-08-23)

- Conclusion: the root cause of the superfluous blank lines holds (iOS lacks normalization, iOS is what should be fixed); but saying "think tags are also a systemic iOS bug" overstates it —— a clean qwen38 session has 0 think tags.
- Verdict on the first batch fix: correct but incomplete (the gaps are listed above). The trim only removes whitespace at both ends of a part and does not touch the paragraphs in between, so the collateral damage is minimal; the behavior matches Web's `.trim()`.
- Think tag handling: recommends "strip only the tags, keep the inner text" (DOMPurify-style), with rendering and copy sharing `normalizedText`; do not do "cut to the last close tag".
- Evidence: 206 messages from the live API (185 assistant text: 99.5% with a leading `\n`, 38.9% whitespace-only, 58 containing think; 185 reasoning with 0 containing think); clean session `ses_fcfbff756ffe` has 0 think tags; Web `message-part-text.ts:2` / `message-part.tsx:717` / `markdown-cache.tsx` DOMPurify; Android `ChatMessageContent.kt:436,776`.

## Why fix it on the client

- The same server data renders correctly on Web / Android, which shows the data itself can be rendered correctly; the problem is in the iOS rendering layer, not in the server / model.
- Client-side normalization is idempotent: it has no side effect on other models (which do not have these newlines / tags to begin with).
- Not touching the server and not touching the model keeps the blast radius minimal and aligns with Web / Android behavior.

## Key Coordinates

- Branch: `fix/whitespace-text-parts` (`7382991` whitespace filtering + trim; `24f5c36` debug log —— not in the PR; `fcef352` this document)
- Target session: `ses_fcfbd043bffe417xHHYrV0gw37` (active, counts are a moving target)
- API: `http://127.0.0.1:4096`, Basic auth `opencode` / `OPENCODE_PASSWORD` (workspace `.env`)
- Simulator: iPhone 17 Pro `8625CF87-A59C-474D-9658-DDFFFA707323` (iOS 26.3, booted)
- bundle id: `com.grapeot.OpenCodeClient`
- Build constraint: `xcodebuild build` and `test` must run sequentially (they share build.db); a full test run takes 10–20 minutes, use `-only-testing:OpenCodeClientTests/MessageRenderingHeuristicTests` for targeted runs
