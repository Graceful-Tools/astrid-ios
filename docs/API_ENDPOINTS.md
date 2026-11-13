# API endpoints this app calls

Every `/api/v1` path in the iOS/Mac app, grouped by resource.

**Why this file exists.** `AstridAPIClient` is the one HTTP client (ASTRID.md §2a, task
`b1a05e99`), and it spends its paths as inline string literals — so without this list,
"which endpoints does the app use" is a question you answer by reading 1,500 lines. The
`APIEndpoint` enum it replaced (deleted in AITD-504) gave that readability for free; this file buys it back, and
unlike a Swift enum, `astrid-web` can read it.

**It cannot silently rot.** `APIEndpointInventoryTests` fails when the source and this file
disagree, which is the only reason to trust a generated list at all.

Regenerate: see the test — it prints the expected list on failure.

**Most of the app's traffic is not here.** Tasks, lists, comments, chat, members, blockers,
settings, the live stream, Connections, webhooks, account delete/export, Custom Agents, public-list browse/copy, share links, list insights, the deployment's capabilities, Copilot connect/disconnect/status, agent modes, AI keys, available agents, contact sync, people search, contact autocomplete and recommended collaborators (AITD-620) go through astrid-core, whose paths are in
`astrid-core/crates/astrid-core/src/api/endpoints.rs` (see `docs/CORE_MIGRATION.md`). This list
is what the Swift client still calls itself.

**One path outside `/api/v1`.** `/api/mcp/user-tokens` mints the Copilot cloud agent's MCP token
(`AstridAPIClient.createCopilotCloudAgentToken`, Agent hub); web serves it only there. It is
named in `APIEndpointInventoryTests.nonV1Exceptions` so a second one cannot appear unseen. (The
passkey routes under `/api/auth/webauthn/*` are built by `PasskeyManager` through `AstridHTTP`,
not by this client.)

**The UI suite reads the server too.** `UITestAPI` (`UITestSupport/UITestAPI.swift`) asks
`/api/v1/tasks`, `/api/v1/tasks/{id}`, `/api/v1/tasks/{id}/comments` and `/api/v1/lists` with the
run's own session, to check what a journey persisted (AITD-527, AITD-528). That is test support,
not the app, so those paths are named here rather than listed below.


## `AstridAPIClient` — the only client (16 paths)


### `/api/v1/app-version`

- `/api/v1/app-version`

### `/api/v1/auth`

- `/api/v1/auth/apple`
- `/api/v1/auth/desktop/exchange`
- `/api/v1/auth/google`
- `/api/v1/auth/mobile-session`
- `/api/v1/auth/mobile-signup`
- `/api/v1/auth/signout`

### `/api/v1/github`

- `/api/v1/github/repositories`
- `/api/v1/github/status`

### `/api/v1/integrations`


### `/api/v1/lists`

- `/api/v1/lists/{id}/transfer-ownership`

### `/api/v1/public`


### `/api/v1/tasks`

- `/api/v1/tasks`

The client reads `/api/v1/tasks` only for a public list's tasks (`getAllTasks`, AITD-634).

### `/api/v1/upload`

- `/api/v1/upload`

### `/api/v1/users`

- `/api/v1/users/me`
- `/api/v1/users/me/ai-preferences`
- `/api/v1/users/me/settings`
- `/api/v1/users/{id}/profile`
