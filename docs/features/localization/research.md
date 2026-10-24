# Localization Research and Planning (iOS Client)

Last updated: 2026-02-15

## Background

The current iOS client mixes Chinese and English: the core navigation bar (Chat/Files/Settings) is mostly English, but many buttons, hints, and error messages are still hardcoded in Chinese. For example, the "Close" button in the Settings panel is a typical case of this localized mixing problem.

The goal of this document is not to launch a full one-shot refactor, but to define an actionable, low-risk localization implementation path that supports progressive iteration.

## Current State Conclusions

- UI interaction copy is currently hardcoded directly through SwiftUI's `Text("...")` and `Button("...")`.
- The project has not yet established a standard `Localizable.strings` or String Catalog (`.xcstrings`) resource management system.
- There is no unified internationalization (i18n) abstraction layer (such as an `L10n.xxx` helper), which makes it hard to automatically verify copy consistency across the UI.
- The resulting user-facing disconnect: Chinese buttons pop up abruptly under an English system language, while English hints frequently appear mixed in under a Chinese system environment.

## Complexity Assessment

If the goal is set as "show English under an English system, show Chinese under a Chinese system", there is no architectural difficulty from a technical implementation standpoint; it is essentially a medium-sized code governance task. Most of the workload lies in cleaning up scattered copy and performing bulk replacements, without touching the underlying core architecture.

- **Quick-and-usable version (estimated 1–2 days)**: prioritize covering the high-frequency main-flow entry points (Settings, core Chat interactions, error dialogs), which immediately removes the most obvious sense of mixed languages.
- **Complete and stable version (estimated 3–6 days)**: fully cover all UI views and error message copy, and add unit tests plus UI automation regression cases, forming a durable, maintainable localization engineering standard.

## Recommended Implementation Plan

1. Build the localization infrastructure
   - Prefer Xcode String Catalog (recommended) or standard `Localizable.strings` file management.
   - Initialize at least two language resource bundles: `en` (English) and `zh-Hans` (Simplified Chinese).
   - Establish a unified, standard Key naming hierarchy, for example `settings.close`, `ssh.status.connected`.

2. Wrap a lightweight access helper layer
   - Add an `L10n` helper type (wrapped as an Enum or Struct) to avoid hardcoding bare string Keys directly in the View layer.
   - Standardize the parameterized interpolation template conventions to avoid scattered dynamic string concatenation.

3. Advance the migration in phases
   - P1: cover the Settings screen and the entire network connection chain (the configuration path with the highest user sensitivity).
   - P2: cover the Chat session flow, Session list management, and Files browsing.
   - P3: cover all kinds of error hints, debug messages, and edge/niche screens.

4. Establish validation and regression-prevention mechanisms
   - Switch between English and Chinese runtime environments in the Xcode Scheme for bilingual validation.
   - Introduce UI snapshot tests or minimal smoke regression cases for the core main screens, to prevent mixed-language issues from resurfacing in later iterations.

## Recommendation for This Round (Fast Path)

We recommend completing a light-weight UX fix first: replace the "Close" copy in the top-left of the Settings panel with `Close` in the top-right, so that the current English-dominant interface is not broken by an isolated Chinese label. Then proceed steadily with the full localization overhaul following the phased plan above.

## Risks and Caveats

- Do not focus only on translating static UI copy: business error messages contain a large amount of text dynamically returned by the server, so the governance boundary between "passing the server text through as-is" and "mapping through local templates" must be defined in advance.
- The copy Key naming conventions must be frozen and locked down early, to prevent naming confusion and redundant definitions when multiple people develop in parallel.
- While rolling out the localization replacements, also clean up the legacy hardcoded bare strings scattered in each location, and establish a mechanism to prevent them from coming back.

## RFC (Addendum): Phased Implementation Plan for a Single V1 Covering P1/P2/P3

> Background feedback: V1 can finish P1/P2/P3, but it must be phased; the "error message pass-through strategy" is low priority and is not a delivery goal for this round.

### 1) First Correct the Assessment of the Current State (based on a full read of the repo)

After a comprehensive read of the current codebase, the project is not "missing i18n infrastructure" but rather "**the infrastructure is already in prototype form, but global adoption has not yet closed the loop**":

- The code already ships `OpenCodeClient/OpenCodeClient/Support/L10n.swift`, containing `en/zh` bilingual dictionaries and a Key enum.
- However, hardcoded strings are still widespread inside view components (causing mixed Chinese/English), mainly concentrated in the following files:
  - `OpenCodeClient/OpenCodeClient/ContentView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
  - `OpenCodeClient/OpenCodeClient/ContentView.swift` (sidebar section; the logic formerly in `SplitSidebarView.swift` has been merged in)
  - `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
  - `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- The error-message handling chain is currently in a state where multiple modes coexist:
  - There is a templated localization implementation (based on `AppError` + `L10n.errorMessage(...)`)
  - There is also logic that reads `error.localizedDescription` directly (scattered across `AppState`)
  - The `error.data.message` inside Assistant messages is displayed as a direct pass-through (via `Message.errorMessageForDisplay`)

Technology selection conclusion: the optimal evolution path in the V1 phase is to **keep using and refine the existing `L10n.swift` architecture, and complete the wiring replacement across all views**; this round does not take on the migration cost of switching to `.xcstrings`.

### 2) V1 Goals and Non-Goals

**V1 goals (must be completed in this round)**

- Fully cover all UI interaction copy involved in P1/P2/P3, ensuring the interface renders strictly consistently after the system language changes.
- Completely eliminate the experience gaps of "Chinese and English mixed within the same screen" and "abrupt language switching in core operation flows".
- Establish a durable engineering standard: new UI copy must go through an `L10n` Key; bare strings are strictly forbidden from flowing directly into the view layer.

**V1 non-goals (explicitly out of scope)**

- This round does not deeply refactor the "server error copy pass-through strategy" or stratify it into layers.
- `L10n.swift` is not migrated to the Xcode String Catalog system yet (deferred to later V1.1+ optimizations).
- The existing error data structures returned by the server are not adjusted or modified.

### 3) Phasing Plan (milestones within the same V1)

#### M1 (P1) — Settings + Connection Chain (high visibility)

Goal: first converge on the configuration and connection modules that users touch most often and that most easily expose mixed languages.

Main list of files to change:

- `OpenCodeClient/OpenCodeClient/Views/SettingsTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift` (entries such as Close in Settings and the file preview panel)
- `OpenCodeClient/OpenCodeClient/AppState.swift` (the static hint copy along the connection chain)

Core changes:

- Route all Section titles, configuration field names, buttons, and Alert prompts uniformly through `L10n.t(...)`.
- Standardize and unify the Key references for "Close / Done / Confirm / Cancel" across panels and dialogs.
- Refactor the two help descriptions in `schemeHelpText(...)` into `L10n.helpForURLScheme(...)`, removing duplicated hardcoding.
- Fill in the missing enum cases in `L10n.Key` (for example Public Key Error, Copy Command, Command Copied, Theme, Untrusted, Rotate, and so on).

Acceptance criteria:

- Under both English and Chinese runtime environments, the Settings screen shows no inverted isolated language islands.
- SSH- and AI Builder-related dialogs and action buttons stay language-consistent.

#### M2 (P2) — Chat + Session + Files Main Flows

Goal: fully cover the mainstream paths with the highest daily interaction frequency, eliminating cognitive interruption during a session.

Main list of files to change:

- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift`
- `OpenCodeClient/OpenCodeClient/Views/SessionListView.swift`
- `OpenCodeClient/OpenCodeClient/Views/FilesTabView.swift`
- `OpenCodeClient/OpenCodeClient/ContentView.swift` (Preview empty-state view)

Core changes:

- Replace all Alert dialogs, navigation titles, input Placeholders, empty-state copy, and voice pre-check prompts in the Chat module with `L10n`.
- Route Session list titles, empty states, and session state descriptions (busy/retry/idle) uniformly through `L10n`.
- Refactor the locale of `RelativeDateTimeFormatter` from the hardcoded `zh_Hans` to follow the system's `Locale.current`.
- Route the hardcoded copy for the Files tree, Workspace hints, search Prompts, and file previews fully through `L10n`.

Acceptance criteria:

- From asking a question in Chat, to switching the Session list, to browsing Files and previewing files, the whole flow has no Chinese/English mixing.
- Relative time descriptions (such as "5 minutes ago") localize dynamically and accurately according to the system language.

#### M3 (P3) — Tool/Patch/Context/Permission + Activity Status Copy Wrap-up

Goal: systematically address the high-exposure but peripheral card components, achieving consistency in global visual style and terminology.

Main list of files to change:

- `OpenCodeClient/OpenCodeClient/Views/Chat/ToolPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PatchPartView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ContextUsageView.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/PermissionCardView.swift`
- `OpenCodeClient/OpenCodeClient/Controllers/ActivityTracker.swift`
- `OpenCodeClient/OpenCodeClient/Views/Chat/ChatTabView.swift` (Completed/Busy/Retrying/Idle status copy)

Core changes:

- Route everything in the Tool and Patch cards, such as "Reason / Command / Input / Output / Open in File Tree / Choose File", through standardized Keys.
- Fully convert the Context detail panel's Section titles, data Labels, Loading state, and Empty state copy to Keys.
- Unify the Permission authorization card's button copy and titles under Keys.
- Introduce `L10n` Keys for ActivityTracker's status mapping copy (Thinking / Planning / Running commands, etc.), removing the hardcoded English copy at runtime.

Acceptance criteria:

- Tool, Patch, Context, and Permission cards keep professional terminology aligned in both language environments.
- The dynamic copy on Activity status rows is neatly laid out with no mixing in the Chinese or English environment.

### 4) Low-Priority Items (explicitly postponed in this round)

- The "server error copy pass-through strategy" is explicitly deferred to later dedicated governance (such as the V1.1 or V2 phase); this round adds no extra strategy conversion layer.
- Keep the current behavior, continuing to allow `error.localizedDescription` and the server-native `error.data.message` to be output as-is; this round focuses on localizing copy in the client's UI framework layer and does not rewrite the semantic source of error information.

### 5) Quality Gate (Definition of Done)

- Code standards:
  - All newly added and modified UI copy must contain no bare strings (except product brand names, model IDs, and protocol-level constants).
  - `L10n.Key` naming strictly follows the `domain.actionOrNoun` convention (for example `settings.copyCommand`).
- Test coverage:
  - Add basic unit tests verifying that the core Keys in `L10n` have corresponding mappings in both the `en` and `zh` dictionaries (guaranteed via two-way set-alignment assertions).
  - Add smoke validation covering the key flows: the Settings screen, Chat Alert dialogs, the Session empty state, Tool/Patch card dialogs, and the Context detail panel.
- Regression criteria:
  - Complete at least two rounds of end-to-end manual walkthroughs (one under the English system language, one under the Chinese system language).
  - A regression of already-fixed mixing issues is strictly forbidden (for example, mixing `Close` with a localized Chinese label).

### 6) Implementation Order and Effort Estimate

- Day 1: advance the M1 milestone (Settings + connection chain) and complete self-testing.
- Day 2: advance the M2 milestone (Chat / Session / Files main flows) and complete self-testing.
- Day 3: advance the M3 milestone (Tool / Patch / Context / Permission / Activity status wrap-up) and run the full regression acceptance.

Summary: **V1 delivers the complete P1/P2/P3 overhaul in a single overall delivery, but the execution pace strictly follows the M1 → M2 → M3 phases, ensuring that each stage has a clearly acceptable milestone**.
