# yage fix work record

Records the local fixes we made to opencode-official + oh-my-openagent (OMO) on our own fork, and the process of locating them. `adhoc_jobs/opencode_ios_client/opencode-official` is a local checkout of the official opencode repository, tracking origin/dev; `/private/tmp/oh-my-openagent/` is a source checkout of OMO 3.17.13.

## 2026-05-04 Concurrent race of multiple generation fibers under the same sessionID

### Symptoms

After upgrading to OMO 3.17.x, when the user talks to the main session in the web UI, the phenomenon "two or three thinking runs proceed at the same time, with similar but inconsistent content, the context window being consumed faster, and compaction often running concurrently" appears frequently.

The hard evidence at the database level comes from a certain user message in the prod db (`~/.local/share/opencode/opencode.db`), session `ses_20ac172c1ffe4DAFzQzpgSw0mx`: a single user message has 22 assistant messages hanging under it, all sharing the same parentID; in the time series at least 6 sibling assistants with `finish=stop` appear, and their input token usage does not accumulate; the first two, 270ms apart, each independently called exactly the same `background_output(task_id=bg_xxx)`. Normally the intermediate steps of a multi-step generation loop are `tool-calls`, the last step is `stop`, and then it breaks out; this "multiple stops under the same parent" shape can only be explained by multiple independent generation fibers writing in parallel under the same sessionID.

### Root Cause

The sessionID-level mutex provided by the opencode server's `SessionRunState.defaultLayer` is not globally unique within the process.

`SessionRunState.defaultLayer` is re-provided via `Layer.provide` in four places:

1. `packages/opencode/src/effect/app-runtime.ts`
2. `packages/opencode/src/server/routes/instance/httpapi/server.ts`
3. `packages/opencode/src/session/prompt.ts` (provided by `SessionPrompt.defaultLayer`)
4. `packages/opencode/src/session/revert.ts` (provided by `SessionRevert.defaultLayer`)

Every `Layer.provide(SessionRunState.defaultLayer)` rebuilds that layer, triggering its internal `InstanceState.make(...)` to run one pass of `Effect.gen`, thereby creating an independent `runners: Map<SessionID, Runner>`. Under the same process and the same directory there are multiple `runners` Maps at the same time, each starting from empty on its own.

In the concurrent scenario:
- Request A goes through the `SessionRunState` of layer instance 1, `runners_v1.get(sessionID)` finds nothing → `Runner.make` → starts fiber_A running `runLoop`.
- Request B goes through the `SessionRunState` of layer instance 2, `runners_v2.get(sessionID)` also finds nothing → another `Runner.make` → starts fiber_B.
- Both fibers run `runLoop` on the same `sessionID`, each re-reading the messages from the db, each doing step++, each writing tool calls into the `parts` table, each running the LLM. The `SynchronizedRef` is a sham, because it protects the state of a single `Runner` instance, and there are two `Runner` instances themselves.

The reason ordinary user conversations rarely hit this race is that normal conversation is naturally serial (the user sends one → waits for the reply → sends the next); by the time the second prompt comes in, the first has long been idle. Seven hooks in OMO 3.17.x — the background-task notification, `unstable-agent-babysitter`, `todo-continuation-enforcer`, `compaction-context-injector/recovery`, etc. — actively call `client.session.promptAsync(...)` while an existing fiber has not yet exited, which exposes this already-broken lock most often.

### Key milestones of the investigation

1. **Inconsistent phenomenon**: the session `ses_20b312218ffevzQP9joW0u5mYD` first seen in the prod db also has 9 independent assistants under a single user message, the first two 270ms apart each calling background_output(`bg_66da62a9`), with input tokens not accumulating —— confirmed to be real concurrency, not a step chain.
2. **First misjudgment**: attributing the race to commit `5ba68a28 refactor(httpapi): scope async prompt fiber (#25213)` —— that commit replaced `Effect.runFork` with `Effect.forkIn(scope, ...)` and removed the explicit `provideService(InstanceRef, ...)`, so it was suspected that the forked-out fiber lost its per-request InstanceRef binding and thus got a different InstanceState. A round of "explicitly provide InstanceRef + WorkspaceRef to the forked fiber" fix was made; after deploying, the race had not disappeared, and the db showed 22 stop siblings again under the same user message.
3. **Adding trace evidence**: added `Effect.logInfo` to the reuse/create branches of `SessionRunState.runner`, and tagged every InstanceState instance with a random `mapId`. After restarting the server we saw 0 reuse / 9 create —— the second prompt on the same sessionID still creates instead of reusing, proving that the race is not in the fiber binding layer but in the multi-instance `runners` Map layer.
4. **Adding more trace to look at the cache**: added `cacheSize / cacheHit / cacheKeys` logging to `InstanceStore.load` and saw the same directory `/Users/grapeot/co/knowledge_working` booted twice under different InstanceStore instances (once by AppRuntime at startup, once by the HTTP server at startup), and that two different `mapId`s appeared in `SessionRunState` across multiple prompts.
5. **Pinpointing the multiple Layer builds**: grepping `SessionRunState.defaultLayer` showed four `Layer.provide` sites, confirming that the root cause is the layer reference being built into multiple service instances at different sites.

### Fix

`packages/opencode/src/session/run-state.ts`: moved the `runners` Map up to the module top level as `sharedRunners`, so that all `SessionRunState` layer instances share one Map. The Scope is still one per InstanceState, used to fork the run fiber, but the sessionID lock is decoupled from the number of layer instances.

```ts
// module top-level
const sharedRunners = new Map<SessionID, Runner.Runner<MessageV2.WithParts>>()

// in layer init
return { runners: sharedRunners, scope, __id }
```

The finalizer no longer calls `runners.clear()` —— because this Map is now process-wide and other layer instances may still be using it. The active runner is cancelled when its own fiber scope closes; the normal lifecycle does not rely on this finalizer for cleanup.

Verification after deploying: consecutive prompts on the same main session each run in a single fiber, with 1 user → ≤4 sequential assistants under a single user message (tool-calls in between, stop at the end); the race is gone.

### The diagnostic trace has been removed

The `mapId` + `sharedRunners.size` logging added to `packages/opencode/src/session/run-state.ts` during the investigation, and the `InstanceStore.load called` logging in `packages/opencode/src/project/instance-store.ts`, were both removed after the fix was verified (commit `ae98a8c7 chore(server): remove sessionID race diagnostics now that fix is verified`), and `bun run build` repackaged `packages/opencode/dist/opencode-darwin-arm64/bin/opencode`. The structural fix of hoisting `sharedRunners` to module scope stays.

The next time the opencode web server is started it will by default use this new binary. No server is currently running; start one manually when needed. When starting it, cd into the target working directory (e.g. `/Users/grapeot/co/knowledge_working`); the server inherits this cwd as the directory of the initial InstanceState.

### Another fix that came along for the ride (kept)

`packages/opencode/src/server/routes/instance/httpapi/handlers/session.ts`: explicitly `provideService(InstanceRef, instance)` + `provideService(WorkspaceRef, workspace)` for the forked fiber before `forkIn`. This is the fix made on the misjudgment path above; on its own it is also reasonable (restoring the semantics before commit `5ba68a28`, avoiding the forked async prompt fiber resolving to the wrong instance under some timing), it does not conflict with the real fix, and it is kept rather than reverted.

## 2026-05-04 OMO 3.17.13 background_output "Task not found" race (fixed)

### Symptoms

After OMO issues the `[ALL BACKGROUND TASKS COMPLETE]` system notification to the parent session, the model immediately calls `background_output(task_id="bg_xxxxxx")`, and **the first call returns `Task not found`; immediately retrying once with the same id gets the result**. In daily use this race appears fairly often; the phenomenon persisted after the race fix was deployed, so it is unrelated to the server lock we just fixed and is an internal OMO timing problem.

The practical workaround used earlier in memory (`feedback*` / `reference*`) was "if the first call is not found, immediately retry once", but the root cause had not been figured out.

### The code path already located

`/private/tmp/oh-my-openagent/src/tools/background-task/create-background-output.ts:61` calls `manager.getTask(args.task_id)`, and on `undefined` it returns `Task not found: <id>` directly. On the manager side, `tasks: Map<string, BackgroundTask>` is set in `BackgroundManager.addTask` (`features/background-agent/manager.ts:328-337`), and task.id has the form `bg_<8 hex>` (manager.ts:396).

The only removal path is `removeTask` (339-341), called by `scheduleTaskRemoval` after `setTimeout(..., TASK_CLEANUP_DELAY_MS=10min)`. So "not found right after the notification" is not caused by cleaning up too early.

### Two suspicion directions not yet verified

1. **Multiple BackgroundManager instances**: possibly isomorphic to the multi-instance `runners` on the server side that was just fixed. If the OMO plugin is init'ed in multiple copies across multiple directory / layer paths, each manager has its own `tasks` Map, and the manager that sent the notification is not the same one that receives the tool call.
2. **task.id is inconsistent between the notification and the registration**: in theory the notification was sent before the task reached `addTask` in the manager; or the task was reissued with a new id while the notification carried the old id.

Next step: add trace to the three places `BackgroundManager.addTask` / `getTask` / `notifyParentSession` (logging the manager instance id + tasks Map size + the task id being operated on); restarting and reproducing once is enough to characterize it.

### Empirical evidence

The OMO source was cloned locally into `adhoc_jobs/opencode_ios_client/oh-my-openagent`, checked out at the 3.17.13 tag, `bun install && bun run build`, and the plugin entry in `~/.config/opencode/opencode.json` was changed from `oh-my-openagent@3.17.13` to a local absolute path, so that the opencode plugin loader takes the file path channel directly (`pluginSource(spec)` goes through `isPathPluginSpec`).

Trace was added in the `BackgroundManager` constructor / `addTask` / `getTask` / `removeTask`: each instance logs a random 6-character `__omoMgrId`, and each operation logs `mgrId` + `taskId` + `tasks Map size` + all current keys. OMO's own `log()` writes through `os.tmpdir()` to `/var/folders/.../T/oh-my-opencode.log` (on macOS it is not `/tmp`; the exact directory has to be obtained from `os.tmpdir()` before you can tail it).

First reproduction (the Sisyphus orchestrator has a sub-agent execute a minimal echo):

```
[03:02:13.836] addTask  mgrId=cmat84  taskId=bg_e6a5c0c1  mapSize=1
[03:02:13.837] getTask  mgrId=cmat84  taskId=bg_e6a5c0c1  hit=yes
[03:02:13.938] getTask  mgrId=cmat84  taskId=bg_e6a5c0c1  hit=yes (×2)
[03:03:14.759] getTask  mgrId=yga2vq  taskId=bg_e6a5c0c1  hit=NO   mapSize=0  keys=[]
```

The `tasks` Maps are mutually invisible across different `mgrId`s —— under the same process and the same directory, the opencode plugin loader re-`import()`s a copy of the plugin on every boot along the InstanceState bootstrap path (the log directly shows `service=plugin path=oh-my-openagent@... loading plugin` appearing more than twice), and each copy of the plugin constructs its own BackgroundManager, with its own tasks Map.

The registration notification used the task on mgrId=cmat84, while the later `background_output(task_id=bg_e6a5c0c1)` tool call from the server route landed in the tool closure of another copy of the plugin, so it looked up the tasks Map of mgrId=yga2vq and necessarily got not found. The second retry with the same id happened to grab the tool registration of the original mgr, which is why "retrying once fixes it".

### Fix

`src/features/background-agent/manager.ts`: all five task-state Maps of BackgroundManager were hoisted to the module top level as `SHARED_*`:

```ts
const SHARED_TASKS: Map<string, BackgroundTask> = new Map()
const SHARED_TASKS_BY_PARENT_SESSION: Map<string, Set<string>> = new Map()
const SHARED_NOTIFICATIONS: Map<string, BackgroundTask[]> = new Map()
const SHARED_PENDING_NOTIFICATIONS: Map<string, string[]> = new Map()
const SHARED_PENDING_BY_PARENT: Map<string, Set<string>> = new Map()
```

In the constructor, `this.tasks = SHARED_TASKS` etc. replace the original `new Map()`. task.id is `bg_<8 hex>`, unique across the whole process, and sessionID `ses_xxx` is likewise unique across the whole process, so sharing the key space across instances causes no conflict. Structurally this is isomorphic to the earlier fix of the server `runners` Map.

The `tasks.clear() / ...` behavior on the shutdown path is kept —— shutdown is only triggered by the process exit signal handler (`process-cleanup.ts`); since the process is about to exit anyway, clearing everything does not matter, and there is no path where a single manager shuts down alone and wipes out someone else's state.

### Verification

`bun run build` repackaged OMO; `kill -9` the old opencode server, and restart the web from the `cd /Users/grapeot/co/knowledge_working` cwd.

Running the same background-agent task again, the key trace:

```
[03:05:11] BackgroundManager constructor mgrId=30ty70 dir=/Users/grapeot/co/knowledge_working
[03:05:26] BackgroundManager constructor mgrId=0huwx9 dir=/Users/grapeot/co/knowledge_working
[03:05:36] addTask  mgrId=30ty70  taskId=bg_a8321bf7  mapSize=1
[03:05:36] getTask  mgrId=30ty70  taskId=bg_a8321bf7  hit=yes
[03:05:47] [background-agent] notifyParentSession bg_a8321bf7 ; Task completed via session.idle
[03:05:53] getTask  mgrId=0huwx9  taskId=bg_a8321bf7  hit=YES   keys=["bg_a8321bf7"]
```

Two BackgroundManager instances still exist (the multi-instance plugin itself was not touched), but the second mgr can now find the task added by the first mgr —— proving that the `tasks` Map is now shared process-wide. This is exactly the moment of "not found right after the notification" in the user's error path; after the fix, a cross-mgr lookup hits directly.

### Deployment

OMO uses the local file path plugin, with the configuration hardcoded in `~/.config/opencode/opencode.json` as `plugin: ["/Users/grapeot/co/.../oh-my-openagent"]`. When upgrading the OMO upstream version later, a local git fetch + rebase + another `bun run build` is needed, keeping these five SHARED-ized local modifications. It is worth considering filing a PR upstream to OMO later, changing the tasks/notifications maps into module-level singletons, or using an explicit `globalThis.__omoBackgroundManagerState__` as a fallback.

### The diagnostic trace has been removed

The omo-trace of `__omoMgrId` + `addTask/getTask/removeTask` was deleted from the source after the fix was verified (commit `d5357f77 chore(background-agent): remove omo-trace diagnostics now that fix is verified`), and the OMO bundle was rebuilt. The historical log file on this machine `/var/folders/.../T/oh-my-opencode.log` (which had grown to 170 MB) was trashed as well. The structural fix of the five shared SHARED Maps stays.

### The more upstream problem that still exists (not fixed)

The opencode plugin loader inits multiple plugin instances under the same process and the same directory; the SHARED Map fix **works around** this rather than **root-causing** it. The thorough fix is to make the opencode server do plugin init per-process (instead of per-InstanceState), so that there really is only one BackgroundManager. This is equivalent to "direction B" of the earlier server `runners` race —— a large blast radius and high risk, left as a follow-up task. The SHARED Map already makes the race observed on the OMO side disappear, so we use it for now.
