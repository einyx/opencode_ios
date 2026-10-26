# Session Changes & Diff Surface — Implementation Plan

> Status: **executed to completion** (2026-10-26) — all tasks shipped and verified. Kept as the record of how the
> design in `design.md` was built. Spec: `design.md` (read it first — it carries the wire facts).

**Goal:** Make agent file changes legible — a "N files changed" card in chat, a real diff viewer, a Files-tab Changes section, and a file tree that refreshes when the agent writes.

**Architecture:** One part type (`"patch"`) is the single "files changed" signal for both server generations. V1 sends it; V2 synthesizes it from `assistant.snapshot.files`. Counts come from the diff payload, never from the part, because V2's snapshot carries paths only. One diff renderer (`DiffLineParser` → `DiffLinesView`) is hosted by three surfaces: an iPhone sheet, the iPad files column, and the Files tab.

**Tech Stack:** Swift 5 / SwiftUI / Swift Testing, iOS 17+. OpenCode V1 + V2 HTTP APIs.

## Global Constraints

- Unit tests run through `./scripts/test_unit.sh`; `xcodebuild build`/`test` run sequentially (shared build database).
- Tests that build `AppState` must pass an isolated `userDefaults:` suite.
- New files are auto-included (`PBXFileSystemSynchronizedRootGroup`).
- Every new `L10n.Key` needs **both** English and zh-Hans entries (`LocalizationTests`).
- No magic visual values — `DesignTokens` only; Views never call `.opacity(` (POL-COLOR-09) and never use `Semantic.error/success/warning` (POL-COLOR-11/14/15).
- Protocol changes must not break the 13 existing `APIClientProtocol` conformers: new requirements get **protocol extension defaults**.

## Tasks (as executed)

1. **V2 changed-file signal + diff payload** — decode `snapshot` into a synthesized patch part; `FileDiff.patchText`; scoped `sessionDiff` with protocol default. *Tests: snapshot → part, absence cases, patchText.*
2. **Classification + diff line parsing** — `ToolCardClassifier.isChangePart/isWriteOperation` + three-way `split`; `DiffLineParser.lines(fromPatch:)` / `lines(before:after:)` with hunk numbering, file-header skipping, and a line-count cap. *Tests: bucket routing, parse shapes, edge cases.*
3. **Chat changes card + diff surface** — `.changes` tile, rewritten `PatchPartView` (counts, scope, accessibility), `DiffLinesView`, `SessionChangesView`, iPhone sheet (`presentationDetents([.medium, .large])`), iPad files column, L10n (en + zh). *Tests: tile routing, totals fallback, list order/dedupe.*
4. **Turn-scoped diffs + freshness** — `turnDiffs` keyed by turn user message, `loadTurnDiff` (V2 only), `noteFileChangeSignal(s)` with noted-once semantics, debounced `refreshFileChangeState`. Hooked into `loadMessages` and the SSE part handler. *Tests: signal scanning (read-only, write-only, patch, user messages never signal).*
5. **Files-tab Changes section + full suite** — `FilesChangesSection` above the tree; full unit suite green.
6. **Docs** — this folder, WORKING.md entry, README index row.

## Verification

- `OpenCodeClientTests/FileChangesSurfaceTests` — 24 tests, green.
- Full unit suite — **1173 passed / 0 failed**, exit 0, parsed Passed bundle (2026-10-26).
- `scripts/polish_lint.sh` — clean (no new palette/spacing/opacity violations).

## Deferred

Revert-this-turn (server-owned, needs confirmation), live counts mid-turn, side-by-side diff, Tier 4 UI tests.
