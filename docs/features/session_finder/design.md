# Session Finder Design Draft

## Conclusion

Position it as a "smart find" mode inside the existing Sessions entry point, rather than as a new standalone Tab, and rather than as a simple title fuzzy filter applied to the already fetched partial list.

The user types a vague recollection of a past session, and the system returns 3–8 matching candidates carrying evidence from the original text. After the user confirms the target in a preview, one tap returns to the original Session to continue typing. In terms of architectural trade-offs, a slightly slower search response is acceptable, but the result must clearly tell the user the search scope, the basis of the recall, and whether that Session is currently in a state where interaction can continue.

During the prototype phase, prioritize orchestrating the existing Markdown archive and semantic search (semantic-search) through a temporary OpenCode Utility Session; the client is only responsible for consuming stable, structured results. Once the interactive experience (UX) validation loop has closed, replace the Utility Session seamlessly with a dedicated Search Bridge service, keeping the UI presentation and the result data contract completely unchanged.

## Success Criteria

Without precisely remembering the session title, creation date, or owning Project, the user can describe a vague memory fragment and complete three core goals within a single retrieval flow:

1. Get a small list of high-confidence candidates, without the pain of digging through dozens of historical titles.
2. Quickly verify and lock onto the real target Session with the help of quoted excerpts from the original text.
3. Clearly know whether that Session supports direct and seamless follow-up questions, or whether only a read-only historical backup is retained.

For the first release, the core quality metric is that the Top 5 candidate list contains the target Session. Search duration is a secondary consideration, but the entire retrieval process must provide credible staged progress feedback; showing nothing but a blank Spinner for a long time is strictly forbidden.

## Entry Point and Main Flow

### iPhone

Fully preserve the existing Sessions toggle button in the Chat toolbar and the swipe-from-the-left-edge gesture. Add a system search field at the top of the expanded Sessions drawer (Sheet), with its placeholder text set to `Describe what you remember`.

When the search field is empty, the interface continues to show the original Active / Archived session list. When the user taps Search on the keyboard to trigger retrieval, the system smoothly switches into smart find mode:

```text
Sessions
┌──────────────────────────────────────┐
│ Discussed iPad Chinese IME           │
└──────────────────────────────────────┘

Searching conversations...
Checking indexed history and live sessions

Possible matches
┌──────────────────────────────────────┐
│ iOS composer input fix               │
│ opencode_ios_client · Jun 18         │
│ You: "Chinese IME still picking..."  │
│                              Preview │
└──────────────────────────────────────┘
```

Clicking any candidate card enters a detail preview page and never crudely replaces the currently ongoing Chat. The preview page presents in one place:

- One round of conversation before and after the matched message context.
- The last round of interaction where that Session paused.
- The owning Project, the date it happened, and the current continuation state.
- A permanently pinned primary action button `Continue in This Session` at the bottom.

If the session belongs to an OpenCode soft-archived Session, the primary button label is adjusted accordingly to `Restore and Continue`. After the user clicks to confirm, the existing `selectSession` logic is invoked, the drawer is closed, and the Chat main interface is returned to with the input field focused; it does not automatically start voice recording and does not automatically submit a message.

The regular Sessions list still keeps the direct "click to switch" interaction. The extra second-confirmation mechanism only applies to semantic search results, which have probabilistic properties, and does not add friction to daily session switching.

### iPad

The search field is permanently located at the top of the left column of the Sessions sidebar. The left column only shows a compact candidate list; when the user picks a candidate, the middle column view temporarily switches from Files to the Session Preview, while the right column always retains the Chat interface the user is currently interacting with. Only when the user explicitly clicks `Continue in This Session` in the preview does the active session in the right column actually switch.

In Compact width mode, an iPad automatically reuses the iPhone drawer interaction logic instead of rigidly forcing a split view based on the device model.

## Search Scope

The default retrieval scope is strictly defined as: the currently connected Host, covering all associated Projects, and including Sessions that are in OpenCode's soft-archived state.

Cross-Host retrieval is not supported by default. Different Hosts correspond to independent connection channels, authentication credentials, and Session namespaces; mixing results from different Hosts would easily create the false-success trap of "a match was found but it cannot be opened in the current environment". A single low-visibility Scope description line is displayed right below the search field, for example:

```text
Home Mac · All Projects · Includes Archived
```

When a matched Session belongs to another Project, after the user confirms continuing, the client automatically switches the current Project to the `directory` corresponding to that Session, ensuring that the Sessions, Files, and Chat views always stay in a unified Workspace context.

The design must clearly distinguish two Archives with different properties:

- OpenCode soft archive: the data is still fully retained in the server's Main DB, and supports instant restore and continued interaction.
- Offline history archive: the data has been migrated to a separate Archive DB or is only retained as Markdown text, and the currently running server cannot perform append operations on it.

The user interface must never conflate the two by generically calling both of them Archived. For offline history, uniformly mark them as `Read-only copy` to avoid mental confusion with the system's existing Archive/Restore states.

## Candidate Cards

Candidate cards only show the key information that helps the user identify and decide:

- Session title, rendered at most two lines.
- Short Project name, omitting long absolute paths.
- Absolute date when it happened; for distant historical sessions, showing only relative time is not enough to establish a clear temporal anchor.
- 2–3 lines of the key matched excerpt from the original text, explicitly labeled with the role as `You` or `Assistant`.
- Special status tags: `Archived`, `Read-only copy`, `Child session`; the regular Idle state is not redundantly displayed.
- An optional one-line status hint `Last stopped at`, helping the user distinguish between "it merely matched an early related discussion" and "it is suitable to continue the context directly from the end".

The interface firmly refuses to display abstract similarity numbers such as 0.83. Such scores lack clear operational guidance for the user and tend instead to create misleading false precision. AI-generated distilled summaries can only serve as auxiliary reference and must never replace real evidence quoted from the original text.

Retrieval results are uniformly aggregated and presented at the Session level, not scattered as a list of slices (Chunks). When multiple Chunks match the same Session, the excerpt with the highest distinctiveness is kept, and multi-point matches are used as an internal confidence signal for ranking. When a child session (Child Session) is matched, the default is to aggregate up to the parent Session level for display and to label the match source as Child, so that the fragments of a single complex workflow do not monopolize the candidate list.

## Search and Ranking

What the V0 stage needs at its core is semantic retrieval capability, not the introduction of a high-overhead generative LLM rerank.

Recommended lightweight ranking pipeline design:

1. Recall the Top 20–30 candidate Chunks from the existing Markdown semantic index.
2. Supplement with exact-match session titles retrieved from the Live DB, plus the most recently active Sessions.
3. Deduplicate and aggregate at the Session level by the `(host namespace, session_id)` tuple.
4. Rank primarily by a blend of the highest semantic similarity score, the number of repeated multi-slice matches, and exact keyword hits, with time decay (recency) used only as a weak correction factor.
5. Verify whether the candidate Session currently belongs to the Main DB, the Archive DB, or exists only as a Markdown file.
6. Output the final Top 5 candidates, dynamically relaxed to at most 8 when the overall confidence is low.

Only if subsequent offline evaluation data clearly proves that the Top-3/Top-5 accuracy of hybrid retrieval (Hybrid Retrieval) is insufficient should a dedicated Reranker model be introduced for the top 20 candidates. And the Reranker must support an automatic timeout-based degradation mechanism; it must never become a hard dependency that blocks first-screen rendering, and it is strictly forbidden to tamper with the recalled original text excerpts.

## V0 Execution Architecture

### Why Start with a Utility Session

The existing `search` interface of the OpenCode server can only do literal filtering by Session Title; while the iOS client only maintains a partial window in memory that loads progressively forward. Neither current state can truly support deep search across the full history content. In contrast, the Workspace environment already has the daily exported Markdown archives, a command-line semantic search tool (semantic-search CLI), and an OpenCode Agent with tool-calling capabilities.

Therefore, during the prototype phase the following lightweight execution chain can be designed:

```text
iOS query
  -> create ephemeral utility session
  -> structured prompt calls semantic-search and checks DB availability
  -> JSON result
  -> delete utility session after successful parsing
  -> render candidates
```

The Utility Session is forced to use a JSON Schema to constrain its output format. The client is strictly forbidden from guessing and extracting the Session ID by parsing free-form model text. When the flow fails abnormally, the Utility Session is retained for troubleshooting and diagnostics; the next retrieval always creates a clean new session, avoiding historical multi-turn context interfering with ranking precision.

The core advantage of this approach is that the client-side change is extremely small, and the real frequency and value of users retrieving old sessions with natural language can be validated quickly at the lowest cost. Its cost is a slightly higher end-to-end latency, one Agent interaction round per search, and a dependency on the Workspace where the server lives having permission to access the Session archive and the semantic search tool.

### Stable Result Contract

```json
{
  "query": "Discussed iPad Chinese IME sending before commit",
  "scope": {
    "host_namespace": "current-host",
    "projects": "all",
    "indexed_through": "2026-07-15T04:00:00-07:00"
  },
  "results": [
    {
      "source": "opencode",
      "host_namespace": "current-host",
      "session_id": "ses_example",
      "title": "iOS composer input fix",
      "project_directory": "/workspace/project",
      "updated_at": 1784102400000,
      "matched_message_id": "msg_example",
      "matched_role": "user",
      "excerpt": "The Chinese IME was still selecting characters...",
      "availability": "live",
      "is_soft_archived": false,
      "parent_session_id": null
    }
  ]
}
```

The `availability` field must support at least the following enum states:

- `live`: the current server can load it directly and supports appending messages.
- `offline_db`: it exists in the offline Archive DB, and in the V0 stage it supports read-only viewing only.
- `markdown_only`: only the exported Markdown text is retained, and in the V0 stage it supports read-only viewing only.
- `missing`: the index matched it but the underlying original data can no longer be resolved or located, so it is not rendered as a normal candidate card.

In the data model design, the unique primary key must never rely on `session_id` alone; it must be composed as the composite triple `(source, host_namespace, session_id)`. Otherwise, when multi-Host or heterogeneous Session sources are added later, the ability to locate things globally and uniquely will be lost outright.

### Formal Bridge

After the UX loop validation is complete, the Utility Session can smoothly evolve into a dedicated Companion Search endpoint:

```http
GET /session-search?q=...&host=...&project=all&limit=5
GET /session-search/opencode/{session_id}/preview
```

The Bridge server uniformly takes over index construction, DB availability resolution (availability resolve), and Preview rendering, while the iOS client's data contract stays completely unchanged. It is strictly forbidden to let the mobile client directly reach across levels to access the server's SQLite database files, absolute physical Markdown paths, or the underlying Embedding cache.

## Loading, Weak Matches, and Failures

Search operations must be explicitly triggered and submitted by the user; an expensive semantic query must never be triggered on every keystroke.

- Response completed within 400ms: present the search results directly and smoothly, without a flickering loading animation.
- Takes longer than 400ms: show the `Searching conversations...` state.
- Takes longer than 2s: append the hint text `Checking older indexed sessions...`.
- The user edits the description and resubmits: keep the previous result list but lower its visual opacity, while showing the refreshing state, to avoid the interface frequently flickering into blankness.

When the match confidence is low (weak match), show a friendly hint:

```text
No strong match found. These sessions may be related.
```

For a genuine zero-result scenario, the interface must clearly state the Host scope and the index time watermark of the retrieval, and provide three clear fallback exits: modify the search description, browse all Sessions in reverse chronological order, or switch to another Host. The three scenarios of network error, index not yet ready, and no retrieval results must be strictly distinguished in their state presentation; they must not be lumped together under a single `No results` that hides the problem.

## Direct Continuation and Read-Only History

The core goal of the V0 stage is to help the user quickly find a session and continue the conversation, so results in the `live` state always enjoy the highest display priority. Results in the `offline_db` and `markdown_only` states are instead aggregated into a separate `Older read-only matches` area, where users are only allowed to browse the history; the interface does not provide a Continue entry point that would easily cause misunderstanding.

If offline archived sessions later need to be woken up again, an explicit `Restore to OpenCode` data flow specification must be established: the complete Session Subtree, associated Messages and Parts data must be fully validated from the Archive DB and written back to the Main DB, and only after confirming correctness may continued appending be allowed. At present, the underlying data toolchain only has a safe one-way Main -> Archive migration flow (plan/apply) and provides no ready-made reverse restore command; moreover, overwriting the underlying files while OpenCode is actively running and writing to the DB easily causes data corruption. Therefore this capability is not included in the scope of the first prototype.

## Approaches Not Adopted

- Do not "only filter the session titles already loaded by the client". Since the list initially only fetches a limited local window, such UI easily gives the user the false impression that "the search has been completed across the full history".
- Do not let the AI automatically open a uniquely matched session. Retrieving historical sessions is inherently ambiguous and must be confirmed by the user after reviewing the original evidence.
- Do not silently replace the current Chat immediately after the user clicks a search candidate. The retrieval itself is a probabilistic decision, while the current active session is a valuable persisted work context.
- Do not fully re-export all sessions before every search. Reuse the daily scheduled semantic index first; only provide an explicit manual refresh entry point when the index is clearly lagging.
- Do not let the iOS client read the server's SQLite or Markdown files directly. The mobile client strictly relies on the standardized Search and Preview data contracts for communication.

## Existing Code Touchpoints

- iPhone Sessions sheet and click-to-switch: `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift:25-135`.
- iPad Sessions left column: `OpenCodeClient/OpenCodeClient/ContentView.swift:890-1042`.
- Existing session switching and message loading: `OpenCodeClient/OpenCodeClient/AppState+Sessions.swift:221-257`.
- The current session list only requests by directory + limit: `OpenCodeClient/OpenCodeClient/Services/APIClient.swift:99-112`.
- `Session` currently has no excerpt or availability: `OpenCodeClient/OpenCodeClient/Models/Session.swift:8-40`.
- The existing design has already explicitly rejected drawing a local title filter as a search: `docs/design.md:209-217`, `docs/OpenCode_iOS_Client_RFC.md:526-537`.

## Prototype Scope

The first prototype strictly focuses on the iPhone side and converges on the following functional boundaries:

1. The retrieval scope is limited to the current Host, includes all associated Projects, and covers soft-archived sessions.
2. Only an explicitly submitted natural language Query starts a retrieval.
3. A Top 5 candidate list is returned, with the corresponding original text excerpts shown.
4. The interaction supports Preview then confirmation to continue; soft-archived sessions first perform a Restore wakeup before continuing the conversation.
5. Offline DB and Markdown archive results support plain-text read-only browsing only.
6. It is implemented on the basis of the Utility Session and a structured JSON Schema, without introducing an LLM Rerank for now.

The core of what this prototype validates is not the ultimate form of the Semantic-Search underlying technology selection, but whether the interaction loop of "describe a vague memory -> inspect the original evidence -> resume the original session with one tap" can truly significantly reduce the mental burden of users finding and reusing past sessions.
