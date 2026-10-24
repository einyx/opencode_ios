# OpenCode iOS Client Test Strategy

Date: 2026-06-03

This document systematically explains the test architecture design of the OpenCode iOS client. For day-to-day change records, see `docs/WORKING.md`; this document mainly answers the core questions at the system level: what each test tier verifies, why it exists, how to run it, and which preconditions it depends on.

This design aligns with the four-tier testing model already implemented on the Android client, and adapts and re-sorts it against the existing iOS architecture. The project's existing Swift Testing, `AppState` mock flow, and fixture-driven XCUITest are all preserved and assigned to their corresponding tiers; at the same time, a minimal closed loop of real server integration and LLM-driven UI is added.

## Why Four Tiers

These four tiers are not divided by the testing tool, but by the core questions they answer, their execution cost, and how often they are triggered.

First, unit/contract focuses on protecting pure business logic and data contracts. This tier requires neither launching the app nor connecting to a server, runs the fastest, and has the highest stability, so it should be run on every commit.

Second, state/component is responsible for verifying the client's internal state machine and fixture UI. This is also a major advantage of the iOS architecture: `AppState` supports injecting `MockAPIClient` and `MockSSEClient`, so a large number of state flows that closely mirror real user operations can be reproduced precisely without depending on a real server. fixture-driven XCUITest also belongs to this tier: although it launches the real app, the state is entirely injected by the test case, and fixed assertions ensure that the view wiring is correct.

Third, integration-UI removes the mock dependency and connects directly to a real OpenCode server and real sessions. The core question it answers is: when the server produces real endpoint responses, payload data, and SSE/tool part shapes, can the client still decode, load, and complete the rendering correctly? Tier 2 cannot capture the protocol drift that happens on the server side, and Tier 3 exists precisely to guard that boundary.

Finally, LLM-driven-UI is driven by an agent operating the real app, reading the accessibility tree and screenshots, and making a comprehensive judgement against the goals of a specific scenario. The first three tiers are all process-determinism tests: the assertion rules are hard-coded up front and can only cover known and anticipated scenarios. Tier 4 instead focuses on outcome determinism: given a goal and acceptance criteria, the agent autonomously performs the operation, observes, waits, and evaluates, and it is specifically used to catch UI/UX regressions that were not hardened into assertions in advance. Tier 4 can equally use curated deterministic fixtures; the criterion for dividing the tiers is not whether the data was pre-constructed (curated), but whether observable runtime evidence has been produced on the real app/simulator and handed to the agent for a full-screen-level UX evaluation.

Overall, the earlier the tier (Tier 1/2), the faster the run and the higher the determinism, which makes it more suitable for the daily commit pipeline; the later the tier (Tier 3/4), the more realistic the runtime environment and the higher the cost, and the more it can uncover potential unknown defects. For the problems uncovered in Tier 4, any verification logic that can be hardened should gradually be pushed down and settled into Tier 3 or Tier 2; the stable harness and CLI tools written during the Tier 4 exploration should also be checked in promptly, while the artifacts produced by the runs — screenshots, `.xcresult`, and temporary configs — must be strictly kept under gitignored paths.

## Current Test Targets

The project currently exposes two test targets:

| Target | Framework | Tier | Current Status |
| --- | --- | --- | --- |
| `OpenCodeClientTests` | Swift Testing (`import Testing`) | Tier 1 + Tier 2 | Main test tier |
| `OpenCodeClientUITests` | XCTest UI Testing | Tier 2 | fixture UI / smoke guard |

Main files:

- `OpenCodeClient/OpenCodeClientTests/OpenCodeClientTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ModelsTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ConnectionTests.swift`
- `OpenCodeClient/OpenCodeClientTests/SessionFlowTests.swift`
- `OpenCodeClient/OpenCodeClientTests/CarModeTests.swift`
- `OpenCodeClient/OpenCodeClientTests/AIBuilderVoiceTests.swift`
- `OpenCodeClient/OpenCodeClientTests/RenderingTests.swift`
- `OpenCodeClient/OpenCodeClientTests/TestDoubles.swift`
- `OpenCodeClient/OpenCodeClientTests/ModelShortlistTests.swift`
- `OpenCodeClient/OpenCodeClientTests/SessionScopedStateTests.swift`
- `OpenCodeClient/OpenCodeClientTests/UserDefaultsIsolationTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ReadToolCardIntegrationTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ToolCardClassifierTests.swift`
- `OpenCodeClient/OpenCodeClientTests/ClientCapabilityTests.swift`
- `OpenCodeClient/OpenCodeClientTests/OpenCodeDeepLinkTests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/ToolCardsUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/ModelShortlistUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/CarModeUITests.swift`
- `OpenCodeClient/OpenCodeClientUITests/OpenCodeClientUITestsLaunchTests.swift`
- `ui_driver/`
- `skills/operate_ios_simulator.md`
- `skills/ui_test_tasks.md`
- `skills/ui_test_prompts/01_read_card_visible.md`

## Daily Runner: Logs, Result Evidence, and Exit Codes

Unit tests use `./scripts/test_unit.sh`, UI tests use `./scripts/test_ui.sh`. Both keep the existing simulator pin, the 15-second screenshot preflight, the dedicated DerivedData, the incremental `build-for-testing` → `test-without-building` order, and the ONLY / REBUILD / UI launch-perf skip rules. An explicit destination does not mean the device is exclusively owned; before running, confirm that the device and the build directory have been released.

```bash
OPENCODE_TEST_DESTINATION="platform=iOS Simulator,id=$SIM_UUID" \
OPENCODE_TEST_ONLY='OpenCodeClientTests/SessionIndicatorTests' \
OPENCODE_TEST_PHASE_TIMEOUT_SECONDS=180 ./scripts/test_unit.sh
```

New parameters: `OPENCODE_TEST_OUTPUT_ROOT` defaults to `.occlient/test-runs/` inside the repo; a custom root must also be normalized into this repo's `.occlient/`, be protected by Git ignore, and there must be no tracked files under `.occlient/`. External roots, symlink/`..` escapes, non-ignored directories, and nested repos are rejected with a return code of 73 before the full log is written. Each run uses an independent random directory and never overwrites old evidence. `OPENCODE_TEST_PHASE_TIMEOUT_SECONDS` defaults to 0 (no limit); a positive integer constrains preflight/build/test respectively, and each phase timeout can have an additional 5-second termination grace period; do not set the 90-second budget for a targeted test as the default for the ~5.5-minute full UI suite. The xcresulttool query on the result bundle has its own 15-second limit; the subsequent small local JSON parsing is not inside that timer.

Each run has a fully live-merged `preflight.log`, `build.log`, and `test.log`, an explicit `test.xcresult`, plus `events.tsv`, the per-phase `*.status.tsv` files, and a final `state.tsv`. The state saves the original command_exit, tee_exit, phase wrapper_exit, and the final acceptance_exit separately; an ordinary non-zero test code is preserved as-is, and a tee failure alone returns 74. When the raw test code is 0 but the bundle is missing, unparsable, of an unrecognized schema, or the result is not Passed, the final runner returns 65, so that callers who only check the exit code cannot pass falsely. Returning 0 requires the test phase to succeed and this run's result bundle to be parsable as Passed; the selected test cases and their count still need to be reviewed. The passed text on stdout and the screenshots do not replace this acceptance.

TSV is data, not source/eval. For `%`, tab, CR, and LF the value is encoded as `%25`, `%09`, `%0D`, `%0A`, and `%25` is processed last when decoding. When a timeout or an interruption leaves no time to obtain the raw code, write unknown; never fabricate an xcodebuild exit code. The cleanup targets only this run's process group.

The full stdout/stderr may contain private paths or app output. ignored only prevents Git from tracking it; it does not protect the console. This runner's full output is used for local development; public CI must use private logs/artifacts together with a redacted external summary, and must not expose the live tee directly. The raw run directory and result bundle are not committed.

The offline regression entry point is `bash scripts/tests/test_runner_observability.sh`: it copies the real runner into a new temporary directory, covers the error paths with fake Xcode/device commands, and then checks the real ignore, tracked, nested repo, and symlink boundaries in a temporary Git repo. It does not start a real device, install dependencies, or modify the current repo's index; the evidence paths are printed at the end. The script keeps the temporary evidence for inspection.

2026-10-14 verification: 9 shell files passed the syntax check, 43/43 regression scenarios passed (35 mock + 8 real Git boundary scenarios). One real `SessionIndicatorTests` run passed 36/36, with preflight/build/test/query at 1/19/9/0 seconds and all raw codes at 0, 29 seconds in total. The initial parser returned acceptance 65 because of a wrong field name; the summary of the real Xcode 27.0 / 27A266a uses a top-level `result: Passed`, and a minimal fix has been made. After keeping this run's JSON offline replay, parse=parsed and acceptance=0; Xcode was not run a second time, and the first failure status was not rewritten. The redacted summary subset is stored in `scripts/tests/fixtures/xcresult-summary-passed.json`, and the unknown-schema branch keeps rejecting.

## Tier 1: unit / contract

Tier 1 focuses on pure logic and data contract tests; it needs neither a real server nor any UI operation. The tests live in `OpenCodeClientTests` and use the Swift Testing framework.

This tier is relatively mature and mainly covers:

- `Session` / `SessionStatus` / `Message` / `Part` decoding.
- `SSEEvent` payload shape.
- API models such as `TodoItem`, `Project`, `QuestionRequest`.
- URL correction, scheme completion, path normalization, and file path extraction.
- Client capability action/callback decoding, Pending/Outbox expiration and idempotency, and permission plus original session continuation.
- `ToolCardClassifier`: which parts enter the file-card grid and which are folded into the merged tool calls row; directory read detection and entries parsing.
- `SSHKeyManager` key lifecycle: separating read from create (`getKeyPair()` is read-only and never generates), guiding generation only when the entry is missing (`errSecItemNotFound`), failing closed by throwing `keyUnavailable` when the Keychain is temporarily unreadable instead of regenerating, and a consistency check plus repair for a cached public key derived from the private key.

This tier mainly verifies whether the client correctly handles known input formats and pure rules. But it cannot prove that the real server is still sending data that conforms to the contract; that question is left to Tier 3.

Run:

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

When adding pure logic, model decoding, path/URL handling, or tool classification logic, you should preferentially add Tier 1 tests.

## Tier 2: state flow / fixture UI

Tier 2 drives the real client state machine and the real UI based on fake data or mock dependencies. Because it needs no real server connection, this tier is cheap, highly deterministic, and highly controllable, which makes it very suitable for covering all kinds of edge states and abnormal branches.

In the iOS project, this tier has two forms:

The first is `AppState` state-flow testing. Because `AppState` supports injecting `MockAPIClient` and `MockSSEClient`, test cases can precisely control API responses, error injection, and SSE event dispatch, driving the real `AppState` through deterministic state transitions. The current coverage includes:

- `loadSessions()` / `loadMoreSessions()`.
- `createSession()` / `deleteSession()` / fallback selection.
- `message.updated` / `message.part.updated` / `session.updated`.
- optimistic user row dedupe and failure rollback.
- session tree, sidebar root-only helper, archived filtering.

The second is fixture-driven XCUITest. The app injects deterministic state at launch through launch arguments, and then the UI test drives the real app to verify operations:

- `UITEST_SESSION_TREE_FIXTURE`: verifies that child/subagent sessions are visible in the session list; the current fixture also contains an active/archived session tree to cover the archive section wiring.
- `UITEST_TOOL_CARDS_FIXTURE`: verifies the half-width process tile grid (file cards and the merged tool calls tile share a 2-up grid and are always half-width), and the expanded content (the expanded content stays inside the half-width tile).
- `UITEST_F3_TRANSCRIBING_FIXTURE`: verifies that the voice rail still keeps text review/send when the agent is running and transcribing in parallel, and that the agent interrupt is demoted to the `⋯` menu.
- `UITEST_F3_RETRY_FIXTURE`: verifies that the preserved-audio retry state clearly expresses "retrying the same audio clip", and that the recovery action is separated from the agent abort semantics.
- `UITEST_CLIENT_CAPABILITY_FIXTURE`: verifies the Health export local authorization reason, the "just this once" and "always allow in the future" options, and the cancel entry point.
- launch/input smoke: verifies app launch, chat input reachability, and that long input stays scrollable.

Tier 2 effectively protects the client's internal state-flow orchestration and view wiring, but in essence it still runs in an assumed environment constructed by the test. Once the server changes the protocol while the mock still uses old payloads, Tier 2 tests may still pass falsely, so it cannot replace Tier 3.

One point that must be distinguished carefully: fixture-driven XCUITest can serve both Tier 2 and Tier 4. When it only executes fixed code assertions, it belongs to Tier 2; when it reuses the same fixture to launch the real app, expands the target UI, and exports screenshots, and then hands them to the agent to read and evaluate the screen layout, hierarchy structure, visual density, and privacy compliance, it becomes Tier 4's deterministic visual QA mode. Although this mode does not use real server data, it trades that for highly reproducible, secret-free, fast-iterating visual feedback evidence, which is very suitable for design polish and UI regression assessment.

## Tier 3: integration

Tier 3 connects directly to a real OpenCode server, creates real sessions, and receives the message and tool parts actually produced by the server, verifying the correctness of the client's contract through fixed assertions. Its core goal is to catch the protocol drift at the client/server interface boundary as early as possible.

The current minimal implementation of this tier is `ReadToolCardIntegrationTests.swift`. The test skips the live path by default and only really connects to the test server when the environment variable `OPENCODE_INTEGRATION_TESTS=1` is explicitly set. The test process reads `ProcessInfo.processInfo.environment` first; if the corresponding configuration is missing, it fills in the missing keys on demand from the git-ignored `.env` at the repo root, while making sure not to overwrite existing environment variables.

Its full execution flow includes:

1. Connect to the local test server, usually 4097, to avoid touching the 4096 the user is using.
2. Run a health check with the real `APIClient`.
3. Create a real session.
4. Send a read-only prompt: read `AGENTS.md`, with creating, editing, and writing files explicitly forbidden.
5. Poll the real messages until a read tool part appears.
6. Use the real decode result and `ToolCardClassifier` to verify that the read tool part is recognized as a read/file operation.
7. Delete the created session on a best-effort basis.

The current version of Tier 3 focuses on guarding the real server -> client decode and classification contract, and does not yet include the complete app-side end-to-end UI navigation chain. A complete UI version can be added later: launch the app, configure the server connection, dispatch the prompt, and verify the full-screen UI behavior end to end.

The related credentials and model/agent configuration must be provided through the gitignored `.env` or through test run parameters, and must never be hardcoded into the source code, the documentation examples, or the Xcode project. When merging the `.env` configuration from the Android client, only the missing keys should be added, without overwriting the existing iOS configuration; in addition, `OPENCODE_SERVER_URL` must use a host address that the iOS Simulator can reach (such as `127.0.0.1`), and must not directly reuse the `10.0.2.2` dedicated to the Android emulator. When no configuration is detected or the server is unreachable, the test should explicitly perform a skip/block and print the specific reason, so that a missing environment is not misreported as a functional failure of the app itself.

Tier 3 by default only allows read-only safe scenarios. Real write/edit operations would directly modify the current workspace, so write operations are strictly forbidden in Tier 3 unless the server cwd explicitly points to a dedicated isolated sandbox.

Live run example:

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientTests/ReadToolCardIntegrationTests
```

The local `.env` must configure at least `OPENCODE_INTEGRATION_TESTS=1`, `OPENCODE_SERVER_URL`, and `OPENCODE_AGENT`; if the server has authentication enabled, `OPENCODE_USERNAME` / `OPENCODE_PASSWORD` must also be provided. If a model needs to be specified, it can be configured through `OPENCODE_MODEL_PROVIDER` / `OPENCODE_MODEL_ID`.

## Tier 4: LLM-driven UI

Tier 4 is actually driven by an agent operating the real app. By parsing the UI state returned by the tooling or taking screenshots, it autonomously judges against the user's business scenarios and acceptance criteria. This tier does not pursue exhaustive coverage; its core is to find the implicit problems that fixed code assertions cannot anticipate, especially UX regressions involving async timing, full-screen information readability, and interaction experience degradation.

The current minimal closed loop implemented on iOS includes:

- `ui_driver/`: a `simctl` backed Python CLI skeleton.
- `skills/operate_ios_simulator.md`: the operation-layer skill.
- `skills/ui_test_tasks.md`: the Tier 4 test task workflow.
- `skills/ui_test_prompts/01_read_card_visible.md`: the first read-card prompt.
- `OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot`: a deterministic screenshot harness that is skipped by default. After `TIER4_SCREENSHOT_PATH` or the `screenshot_path` in `/tmp/opencode-ios-tier4-config.json` is set, it launches the real app with a synthetic session tree fixture, expands the Archive section, and writes the PNG to the specified path.

`ui_driver` currently supports subcommands such as `devices`, `launch`, `screenshot`, `tree`, `run-xcuitest`, `configure-server`, and `send-prompt`. The `tree` command provides two working modes: when no Xcode arguments are passed, it performs an honest screenshot-only observation and returns `observability: screenshot_only`, empty `nodes` / `compact`, and a warning; while when the `--project`, `--scheme`, and `--destination` arguments are passed, it calls `Tier4DriverUITests/testAccessibilityObservationSnapshot` and returns `observability: xcuitest_accessibility_snapshot` together with the corresponding XCTest summary. Even here, there is still no Android-style faithful simulation of a complete accessibility tree. When a specific UI element needs to be asserted precisely, it is recommended to trigger a focused UI harness through `run-xcuitest` or the XCTest-based `tree` command; this conforms better to iOS platform engineering best practice than hard-coded coordinate tapping or fabricating a fake tree. Tier 4 combines screenshot evidence, the XCTest summary, and the agent's autonomous cognition to reach a final verdict; when the information is insufficient to reach a conclusion, it explicitly reports BLOCKED.

The execution chain of `configure-server` and `send-prompt` on the live 4097 test port has been verified. The driver passes the run configuration to XCTest via a temporary file `/tmp/opencode-ios-tier4-config.json` with permission `0600`, ensuring that no plaintext password leaks into the command line or into `xcodebuild_args`; for password entry it uniformly injects via paste/`Cmd+V`, and the JSON output redacts sensitive passwords in the tail logs of stdout/stderr. In addition, the Xcode UI test always explicitly specifies `-parallel-testing-enabled NO`, preventing test startup failures caused by clone runner conflicts.

### Deterministic screenshot QA

When dealing with pure UI layout or visual design changes, the deterministic screenshot harness should be preferred over dynamic screenshots that depend on a live server. A live screenshot easily mixes the server's running state, account credentials, network fluctuation timing, and dynamic session data into the test evaluation; a fixture screenshot, in contrast, focuses on checking whether the current interface design is rendered precisely on iPhone/iPad. The success acceptance criterion of this flow is not simply "the test case executed successfully", but that the produced screenshots can pass a manual or intelligent review by reading the image.

How to run:

```bash
# Write the gitignored temporary config; you can also use the TIER4_SCREENSHOT_PATH environment variable instead.
printf '{"screenshot_path":"%s"}\n' \
  "$PWD/tmp/visual_qa/session_archive_fixture.png" \
  > /tmp/opencode-ios-tier4-config.json

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testCaptureSessionArchiveFixtureScreenshot \
  -parallel-testing-enabled NO
```

The deterministic fixture for the F3 voice composer can be run separately with the same layer of UI test:

```bash
xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testF3TranscribingComposerFixtureScreenshot \
  -only-testing:OpenCodeClientUITests/OpenCodeClientUITests/testF3RetryComposerFixtureScreenshot
```

The same harness only needs the destination switched to be reused for iPad device verification. Screenshot artifacts are recommended to be output under the `tmp/visual_qa/` directory and must never be committed. After execution, the images must be opened and verified item by item: whether the interface correctly stayed on the target page, whether the target section expanded properly, whether any unexpected system dialogs or stale UI remainders are present, whether real private data leaks, and whether the overall visual hierarchy strictly matches the design expectations.

In the design practice of the session archive feature, this workflow successfully captured two typical problems that fixed code assertions could not find: first, the combination of `DisclosureGroup` and the system list row easily degrades the section header into a visually clumsy default-styled cell; second, trying to offset the sheet/list padding with a negative top padding causes the `Active` header to be occluded by the title bar above in certain viewports. The screenshot review mechanism turns such layout regressions into directly visible, deterministic evidence, which makes it easy to later push the fixed, stable interaction behavior down into the fixture UI test.

This architecture continues the core idea validated on the Android side: the CLI acts as the skeleton, the agent acts as the intelligent decision layer, and the test case is the prompt. The difference is that the iOS platform lacks a low-overhead direct export interface like Android's `uiautomator dump`, so at this stage XCTest is used as the bridge for precisely identifying UI identity. Currently `configure-server` and `send-prompt` have been packaged into `ui_driver` as advanced commands; if a stable and reliable iOS accessibility tree parsing capability can be built later, generic interaction instructions such as `tap-label` will be added further.

Tier 4 tests do not need to be part of the daily trigger chain of every commit; they are usually triggered on demand or run periodically. When Tier 4 exploration has identified an interaction behavior with stable assertion characteristics, the hardenable part should promptly be pushed down to Tier 3 or Tier 2 for maintenance.

The code with long-term maintenance value that emerges during the Tier 4 implementation should be committed to the repository (such as the launch fixture, the XCTest screenshot harness, the `ui_driver` subcommands, and the redaction/helper scripts); while the various one-off artifacts produced by a single run must never be committed, specifically including real screenshots, fixture screenshots, `.xcresult`, DerivedData caches, the Xcode workspace's `xcuserdata`, the temporary config file `/tmp/opencode-ios-tier4-config.json`, and the credential JSON that contains credentials.

## Cross-Cutting Prerequisite: UI Observability

The effective operation of Tier 2, Tier 3, and Tier 4 all depends heavily on a stable, semantic accessibility surface. Any UI element that must be asserted by automated tests or perceived and judged by an agent must explicitly declare a clear `accessibilityIdentifier` and `accessibilityLabel`; relying on fragile absolute coordinates, view colors, typography spacing, and other rendering details is strictly forbidden.

The tool card components on iOS already make a fine-grained distinction between read and write operations at the accessibility layer:

- file read: `toolcard.read.<basename>`, label `Read file <basename>`.
- write/edit/patch: `toolcard.write.<basename>`, label `Write file <basename>`.
- directory read: `toolcard.folder.<basename>`, label `Read directory <basename>`.
- merged non-file tools: `toolcard.toolcalls`. This tile is a custom-drawn button row (not the system DisclosureGroup): `.isButton` trait + expansion value (`已展开`/`已收起`, i.e. expanded/collapsed), with the identifier unchanged.
- thinking tile: `message-thinking-card`. Also a custom-drawn button row: `.isButton` trait + expansion value (`已展开`/`已收起`, i.e. expanded/collapsed), with the identifier unchanged.

`ToolCardsUITests` uses `UITEST_TOOL_CARDS_FIXTURE` to ensure that both read-type and write-type cards can be correctly captured and recognized in XCUITest. Given that performing write/edit/patch operations on a real server carries safety risks, the UI rendering of write cards is mainly verified with Tier 2 fixtures; read cards, on the other hand, get dual coverage from the Tier 2 fixture and the Tier 3 real-server read path.

The **half-width visual QA** of the process tiles (thinking / merged tool calls) is carried by the `oc_toolcards_collapsed` / `oc_toolcards` screenshots produced by `ToolCardsUITests` (deterministic screenshots; read the image to check that the tile width equals the grid column width and that the expanded content stays within the half width). Note that the current `UITEST_TOOL_CARDS_FIXTURE` does not contain a reasoning part, so the thinking tile currently has no UI coverage; optionally adding a reasoning part to that fixture would complete it.

## Boundaries and Safety

The locally running OpenCode server may share the `/Users/grapeot/co/knowledge_working` working directory. Without a dedicated isolated sandbox configured, Tier 3 and Tier 4 are only allowed to trigger read-only tool calls. Any prompt that contains an intent to create, modify, or write files is treated as an out-of-bounds operation and must be strictly forbidden.

The screenshots and UI trees produced by automated tests may carry server URLs, usernames, session details, or other sensitive private information. Therefore all artifacts generated by Tier 4 must be forcibly output to a gitignored directory; before sharing them externally or committing them, they must be strictly verified to ensure that no token, password, or real private data is smuggled along.

The execution rules for test commands must strictly follow the project `AGENTS.md` spec: `xcodebuild build` and `xcodebuild test` must be executed serially in order, and concurrent runs are strictly forbidden, to avoid `build.db: database is locked` caused by a shared DerivedData / build database.

## Recommended Verification Commands

After modifying business code or test cases in daily work, the following build and test commands should at least be executed in order:

```bash
xcodebuild build \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'generic/platform=iOS Simulator'

xcodebuild test \
  -project "OpenCodeClient.xcodeproj" \
  -scheme "OpenCodeClient" \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'
```

To run Tier 3, you additionally need a local test server, authentication credentials, and agent/model configuration; to run Tier 4, you need to ensure that the target simulator is already booted, that the app is preinstalled, and that the iOS `ui_driver` and its accompanying skill/prompt are ready.

Run the unit tests that ship with `ui_driver`:

```bash
cd ui_driver
.venv/bin/python -m pytest -q
```
