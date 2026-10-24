# Agent Catalog Validation and Making Deletion Failures Visible

Date: 2026-09-27

## Background

When connecting to a host that only exposes `build`, the client may still send a prompt with the agent name from the previous server, and the peer replies with 501. The other path is deletion: when the host replies 501 to `DELETE /session/:id`, if the error message does not show the status code and the body, the user will think the session has been deleted.

On iOS the selection state is `selectedAgentIndex`, not a persisted agent name. `Message` does not decode `info.agent` either, and there is no path that infers the agent from history. The cross-host leftovers come from the in-memory agent list and index: when switching hosts, `resetConnectionRuntimeForHostSwitch` previously did not clear the agents. The placeholder list (`OpenCode-Builder` etc.) is also not the result of the current server's `GET /agent`.

The deletion path itself already throws `APIError.httpError` for status >= 400 in `APIClient.makeRequest`, and `AppState.deleteSession` only deletes the local row after the request succeeds; the list UI shows the error with `error.localizedDescription`. The gap is that `APIError` does not conform to `LocalizedError`, so the alert does not show the status code and the body.

## Changes

`AgentInfo.effectiveSelectedAgent(selection:agents:)`: if the catalog is empty, keep the selection; if the catalog contains that name, keep it; otherwise take the first visible agent, and otherwise `"build"`.

Application points:

- After `loadAgents()` succeeds, re-validate `selectedAgentName` against the list returned this time, and sync the picker index.
- `sendMessage()` re-validates through `agentNameForPrompt()`. When there is still no catalog for the current host, no placeholder name is sent; it always uses `"build"`.
- `loadMessages()` also re-validates after success. There is no inference of the agent from messages; when the catalog is empty the selection is not changed.
- When switching hosts, clear the agent list and the catalog marker, and return the selection to `"build"`, to avoid endorsing the new host with the previous server's list.
- The default selection is `"build"`, not index 0 of the placeholder list. When the server catalog contains `build` it will be chosen, even if it is not the first item in the list. Only when there is no `build` does it fall back to the first visible agent.

Deletion: `APIError` is changed to conform to `LocalizedError`. The description for a non-2xx response is `HTTP <status>: <body>`. The failure branches of the UI and the local list do not need to change.

## Tests

`OpenCodeClientTests`:

- Pure function: unknown falls back, known is kept, an empty catalog leaves it unchanged, and it falls back to `"build"` when there is no visible agent.
- The correction of unknown names by `loadAgents` / `sendMessage` / `loadMessages`, and an empty catalog not changing the selection.
- Switching hosts drops the previous server's agent.
- The `APIError` message contains the status code and the body; on a delete 501 the local row is kept.

UI tests were not run. The deletion alert still uses the existing `actionError = error.localizedDescription`.
