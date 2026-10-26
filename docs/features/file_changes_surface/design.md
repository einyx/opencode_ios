# Session changes & diff surface — design

> Status: **implemented** (2026-10-26). Plan: `plan.md`.
> Related: `docs/design.md` §QT-PALETTE, `docs/v2_server_compatibility.md` (diff / file status shapes — re-add if the
> docs restructure restores it).
>
> Note: the first copy of this document, the implementation plan and the review preview
> (`docs/design/drafts/2026-10-26-changes-diff-surface.html`) were lost in the 2026-10-26 docs restructure before
> they were committed; they are recreated here from the session record.

## Intent

A turn that writes files should be legible at a glance: the chat says **what changed**, one tap shows the diff,
and the Files tab never goes stale mid-turn.

Before this shipped, the client fetched the session diff and dropped it (`selectedDiffFile` had no consumer),
`PatchPartView` was dead code, a multi-file patch collapsed into a single file card, the V2 changed-file signal was
never decoded, and the file tree only refreshed on appear / pull-to-refresh / session switch.

## Goals

- **G1** A turn that changed files ends with a tappable "N files changed" card.
- **G2** One tap → per-file list with counts, and the diff of the selected file.
- **G3** The Files tab shows a Changes section, and tree + status refresh automatically when the agent writes.
- **G4** V1 and V2 both work. V2 uses the turn-scoped diff endpoint; V1 uses the session diff and the part's own counts.
- **G5** Every count is readable as text (VoiceOver, greyscale, colour-blind) — colour is decoration only.

## Non-goals

- **NG1** No side-by-side diff. On V2 the server sends `before: ""`, so there is no before content to align.
- **NG2** No file browser inside the diff sheet (HIG *Modality*: one path, no app-within-an-app).
- **NG3** No new server capability. Everything comes from endpoints that already exist.
- **NG4** Revert/undo is a later stage. The server owns it (`/api/session/:id/revert/stage`).
- **NG5** No live-updating counts while a turn is running. The wire does not push them.

## Wire facts the design is built on

| Fact | Consequence |
|---|---|
| V2 `Session.Message.Assistant.content` = `text \| reasoning \| tool` — no patch part | V1 and V2 need different sources for "which files changed" |
| V2 assistant message carries `snapshot.files` (relative paths, **no counts**) | V2 file list comes from the message; counts come from the diff endpoint |
| `GET /api/session/{id}/diff?from=&to=&context=` → `{file, patch, additions, deletions, status}` | V2 diff is turn-scoped; `from` = the user message that started the turn |
| V2 `before` is `""`, `after` is the patch text | The patch string is the only diff body V2 can show |
| V1 patch part → `files[{path, additions, deletions, status}]`; V1 diff has real `before`/`after` | V1 can show counts without a fetch; the renderer derives the diff |
| `GET /api/vcs/status`, `GET /api/vcs/diff?mode=working` | Working-copy changes made outside the session are a separate signal |

## The design, as shipped

### 1. Model

- **One part type, two sources.** The chat's "files changed" surface is always a `Part` with `type == "patch"`.
  - V1: the server already sends patch parts — used as-is.
  - V2: `V2Mapper` synthesizes one patch part per assistant message from `snapshot.files`
    (`Part.FileChange` with path only; counts stay `nil` until the diff loads).
- **Counts live in the diff payload, not in the part.** `FileChangeTotals.resolve(turnDiff:part:)` prefers the
  turn diff, falls back to the part's own per-file counts (V1), and returns `nil` when neither is known — the card
  then shows the file count alone rather than a misleading zero.
- **Diff body is explicit, never inferred.** `FileDiff.patchText` is set by V2 (the server's `patch`); V1 leaves it
  `nil` and `DiffLineParser.lines(before:after:)` derives the diff. The renderer never guesses whether `after`
  holds a patch or file content.

### 2. Wire

- `APIClient.sessionDiff(sessionID:from:to:context:)` — V2 sends `from`/`to`/`context`; V1 ignores them. The
  protocol requirement carries a default implementation, so none of the 13 existing `APIClientProtocol`
  conformers changed.

### 3. Surfaces (one renderer, three hosts)

- **Chat:** the changes card (`PatchPartView`) replaces the patch part in the file-card grid —
  `ToolCardClassifier.split` has a third bucket for change parts, and patch parts are no longer file operations.
- **iPhone:** a sheet — file list on top, the selected file's diff below. One level, no nested browser.
- **iPad:** the files column shows the surface (no sheet on a large screen).
- **Files tab:** a "Changes" section above the tree (`safeAreaInset`), reusing the tree's
  added / modified / deleted vocabulary.

### 4. Freshness

- `FileChangeSignalScanner` finds the signals in a transcript: a change part, or a completed write/edit tool part.
- Signals are **noted once** (`fileStore.notedChangePartIDs`), so reloading an old transcript does not re-refresh.
- One signal schedules one debounced refresh (400 ms) of the session diff, the status map, and the tree (the tree
  only when it is already loaded). Hooked into both the REST message load and the SSE part handler.

### 5. Accessibility

- Counts are text ("3 files changed, 48 lines added, 12 removed" as one VoiceOver label).
- Diff lines read as "removed, line 19: …" / "added, line 19: …".
- Colour is decoration: additions use the accent, removals use secondary text; markers, line numbers and labels
  carry the meaning (QT-PALETTE one-colour rule).

## Test coverage

`OpenCodeClientTests/FileChangesSurfaceTests.swift` (24 tests): V2 snapshot → patch part (and its absence
without a snapshot); V2 diff keeps `patchText` / V1 leaves it nil; classifier buckets (patch = change, write tools
= write signals); patch parsing (hunks, line numbers, file headers, removed `---` content); derived before/after
diff; card tile routing; totals resolution; changed-file list order and dedupe; write-signal scanning.

Deferred: Tier 4 UI tests (card → sheet → diff flow), revert-this-turn, live counts mid-turn.
