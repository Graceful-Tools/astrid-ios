<!-- Point-in-time analysis, 2026-11-06. Written from Code-OSS 1.146.0 (58f5c3a6), astrid-web 4facd3a5, astrid-core 2e0ebed. History only: the live plan, when the spike starts, is the astrid-vscode repository. -->

# Astrid mode for VS Code — analysis and spike plan

## Context

Jon wants to explore merging Astrid's layout into VS Code: **one tap shifts VS Code into
"Astrid mode"** — lists on the left, the task list / board in the middle, chat on the right,
code chrome out of the way — and a second tap brings the coding layout back. Focus is the
Mac. Decisions taken in this session: the mode is a **full takeover** (not a companion
panel); the analysis weighs **an extension against a Mac fork of Code-OSS** and recommends
one; the output is **this analysis plus a plan for a first spike**, built in a follow-up.

What was examined (all read-only):

- **Code-OSS** `microsoft/vscode` at `58f5c3a6`, version **1.146.0**, shallow-cloned to the
  scratchpad (`vscode-src/vscode`). Electron 43.8.6, Node 24.22.1, pnpm 12.16.0.
- **Astrid Mac** (`Astrid Mac/App/MacLayout.swift`, `MacRootView.swift`, `MacDeepLink.swift`,
  `MacAppModel.swift`, `Commands/`, `Support/GlobalHotKey.swift`) — the layout being merged.
- **astrid-web** (`lib/auth/desktop-handoff.ts`, `mcp/`, `.well-known/oauth-*`, `lib/csp.ts`,
  `app/[locale]/docs/mcp/page.tsx`, `lib/layout-detection.ts`, `lib/core-rules/`).
- **astrid-core** (`crates/astrid-rules-wasm`, README).

---

## Findings

### A. What "Astrid mode" has to reproduce — the Astrid Mac layout contract

`Astrid Mac/App/MacRootView.swift:1087` is a `NavigationSplitView` with three regions:

| Region | Content | Rule (`MacLayout.swift`) |
|---|---|---|
| Sidebar (~240pt, floor/ideal/max) | My Tasks · Search · Favorites · Lists (+ Add list) · Public lists (collaborative, browsable) · account bar at the bottom | `sidebarMinWidth/IdealWidth/MaxWidth` |
| Middle | the list rows **or** the board for the selected list; content modes `list / board / chat` | board columns ≥250pt each |
| Right column | the list's chat, **always visible when the window ≥1100pt** (web's `lib/layout-detection.ts` 3-column rule) | `chatColumnWindowThreshold = 1100`, `chatColumnWidth` derived from the 380pt detail pop-out |
| Detail | floats over the chat column (never shrinks the rows); full-screen on a board | `detailPanelWidth = 380` |

Also part of the contract: the bare-key keyboard scheme shared with web
(`Astrid Mac/Keyboard/KeyboardShortcuts.swift` ⇄ `astrid-web/hooks/useKeyboardShortcuts.ts`),
⌘K command palette (`Commands/CommandRegistry.swift`), a system-wide ⌥Space hotkey
(`Support/GlobalHotKey.swift`, Carbon, sandbox-safe), and deep links
`astrid://tasks/<id>`, `astrid://lists/<id>`, `astrid://settings/<page>` (`MacDeepLink.swift`).

Mac adds no business logic; everything decides through astrid-core. A VS Code client must
hold the same line (ASTRID.md §0): permissions and strings are a cross-platform contract,
completion goes through the completion rule, never `completed: true`.

### B. How VS Code's workbench layout works — and what a mode toggle can touch

- **Parts and grid.** `src/vs/workbench/services/layout/browser/layoutService.ts:21-32` —
  TITLEBAR, BANNER, ACTIVITYBAR, SIDEBAR, EDITOR, PANEL, AUXILIARYBAR, STATUSBAR. One
  `SerializableGrid` built in `src/vs/workbench/browser/layout.ts:1644-1676`
  (`createGridDescriptor` :2670, `arrangeMiddleSectionNodes` :2595). Part visibility, sizes
  and positions persist as `LayoutStateKeys` (`layout.ts:2860-2911`, storage prefix
  `workbench.`): `sideBar.hidden`, `auxiliaryBar.hidden`, `panel.hidden`, `editor.hidden`,
  `activityBar.hidden`, `statusBar.hidden`, `*.size`, `*.position`, `zenMode.*`.
- **There are no named or saved layouts.** `workbench.action.customizeLayout`
  (`browser/actions/layoutActions.ts:1434`) is a quick-pick of individual toggles.
- **Zen Mode is the existing "mode toggle"** (`layout.ts:1455-1620`): on entry it records
  `wasVisible{sideBar,panel,auxiliaryBar}` plus fullscreen/centered transitions in
  `zenMode.exitInfo`, hides parts, and restores from that record on exit. A maximized
  secondary sidebar does the same dance (`setAuxiliaryBarMaximized` :2179). **This is the
  pattern Astrid mode copies** — product code can read the state; an extension cannot (see C).
- **Idempotent setters exist** for everything a mode needs:
  `workbench.action.closeSidebar` / `closePanel` / `closeAuxiliaryBar` (hide),
  `focusSideBar` / `focusPanel` / `focusAuxiliaryBar` (show),
  `workbench.action.activityBarLocation.{default,top,bottom,hide}`,
  `workbench.action.editorLayoutSingle`, `joinAllGroups`, `lockEditorGroup`,
  `toggleMaximizeEditorGroup`; internally all go through
  `IWorkbenchLayoutService.setPartHidden(hidden, part)` (`layoutService.ts:613`).
  Toggles (`toggleSidebarVisibility`, `togglePanel`, `toggleAuxiliaryBar`,
  `toggleActivityBarVisibility`, `toggleStatusbarVisibility`) must be avoided — they
  cannot be made idempotent without reading state.
- **The chat column already has a home.** The built-in Chat view container
  `workbench.panel.chat` is registered in the **auxiliary bar** by default
  (`contrib/chat/browser/chatParticipant.contribution.ts:42-50`), which is exactly where
  Astrid's right column goes.
- **Adding a new Part to the grid is deep**: the `Parts` enum, `workbench.ts:326-334`,
  `createWorkbenchLayout`, `createGridDescriptor`, `setPartHidden`, new state keys, context
  keys, splash and test services — the auxiliary bar's introduction touches ~20 files in
  `src/vs/workbench` alone. Not a spike-sized change, and never needed: the three Astrid
  columns map 1:1 onto sidebar / editor / auxiliary bar.
- **The strongest precedent is the Agents Window** (`src/vs/sessions/`, 720 TS files): a
  *second workbench* layered above `vs/workbench` with its own fixed topology
  (`LAYOUT.md`: Sidebar | Sessions Part / Editor / Aux / Custom View Grid + Panel; no activity
  bar, no status bar), its own HTML entry (`electron-browser/sessions.html`,
  `sessions.desktop.main.ts`), a **title-bar button** that switches into it
  (`OpenWorkspaceInAgentsWindowTitleBarAction`, `MenuId.TitleBarAdjacentCenter`,
  `contrib/chat/electron-browser/agentSessions/agentSessionsActions.ts:210-225`), and a
  **system-wide keybinding** to open it from anywhere (`SYSTEM_WIDE_KEYBINDING.md`, macOS tip
  promotes ⌃⌘A). Microsoft built "one tap → a different window shape" as a separate window,
  not by re-gridding the editor window. A fork-level Astrid mode would follow the same shape.

### C. The extension path — what is reachable without a fork (stable API, 1.146)

Reachable:

- **Three columns.** `contributes.viewsContainers` accepts `activitybar`, `panel` **and
  `secondarySidebar`** (`src/vs/workbench/api/browser/viewsExtensionPoint.ts:63-80`, :323) —
  so a lists container on the left and a chat container on the right are declarative.
  `createTreeView`, `registerWebviewViewProvider` (`retainContextWhenHidden`),
  `createWebviewPanel(…, ViewColumn.One)`, `registerCustomEditorProvider` are all stable.
- **The shift itself** is a sequence of the idempotent commands in B plus
  `workbench.action.editorLayoutSingle` → `joinAllGroups` → open the board webview →
  `lockEditorGroup`; `window.tabGroups` (stable) records which editors were open so they can
  be reopened on exit.
- **The tap**: a status-bar item, an activity-bar icon, an `editor/title` button, a keybinding,
  the **Touch Bar** (`touchBar` menu is contributable, `menusExtensionPoint.ts:45-47`), or the
  Astrid Mac app firing `vscode://graceful-tools.astrid/mode` through
  `window.registerUriHandler` (`vscode.d.ts:11727`). A system-wide shortcut works too — but
  only as a user `keybindings.json` entry with `"systemWide": true`
  (`systemWideKeybindings.specification.md`); extensions cannot ship one.
- **Auth & secrets**: `SecretStorage`, `authentication.registerAuthenticationProvider`.
- **Astrid tools in VS Code's own chat**: `lm.registerMcpServerDefinitionProvider` +
  `contributes.mcpServerDefinitionProviders` (stable, `vscode.d.ts:21109`;
  `McpHttpServerDefinition(label, uri, headers)` :20741).

Not reachable (the real gaps):

1. **No API reads layout state** — not stable, not proposed. `sideBarVisible`,
   `auxiliaryBarVisible`, `panelVisible` exist only as `when`-clause context keys
   (`src/vs/workbench/common/contextkeys.ts:138,180,193`). So "restore exactly what you left"
   is best-effort from an extension; Zen Mode's exact restore is product-only.
2. **No title bar / Command Center / layout-control menu** for extensions —
   `MenuId.TitleBar*`, `CommandCenter`, `LayoutControlMenu` are absent from
   `services/actions/common/menusExtensionPoint.ts`.
3. **No profile API**; switching profiles restarts the extension host
   (`services/userDataProfile/browser/userDataProfileManagement.ts:177-210`) — profiles are
   not a viable mode mechanism.
4. **Embedding astrid.cc in a webview is out**: the web sends `frame-ancestors 'self'`
   (`astrid-web/lib/csp.ts:75`) and `X-Frame-Options` (`next.config.mjs:138`), and even if
   relaxed, its session cookie would be third-party under the `vscode-webview://` top origin.
   The extension renders its own UI and talks to `/api/v1` itself.
5. The `agentSessions` view location is proposal-gated (`chatSessionsProvider`) — a fork or
   `--enable-proposed-api` only.

### D. The Mac fork path — what it costs

- **Build**: `pnpm install` (Node 24.22.1 enforced by `build/npm/preinstall.ts`), `pnpm run
  compile`, `./scripts/code.sh` (downloads Electron, `build/lib/preLaunch.ts`); packaging is
  `gulp vscode-darwin-arm64-min` (`build/gulpfile.vscode.ts:584-640`, output beside the repo).
  README says ≥4 cores / 6–8 GB; a first compile is tens of minutes on this class of Mac.
- **Branding/identity**: `product.json` (`nameShort/Long`, `applicationName`,
  `dataFolderName`, `darwinBundleIdentifier`, `urlProtocol` — the Info.plist is *generated*
  from these in `build/lib/electron.ts:157-262`, which also hardcodes company name, icon
  `resources/darwin/code.icns`, document types). The OSS `product.json` has **no
  `extensionsGallery`, `updateUrl`, `quality`**; a fork must add a gallery (Open VSX by
  convention — not documented in-repo) or ship everything built-in.
- **Signing/notarization**: `build/darwin/sign.ts` uses `@electron/osx-sign` with env-driven
  identity; notarization is Microsoft's internal ESRP (`build/azure-pipelines/darwin/codesign.ts`)
  — a fork writes its own `notarytool` step. Distribution is outside the App Store
  (Electron + extension host ≠ sandbox); Astrid Mac's `docs/MAC_DISTRIBUTION.md` direct
  channel is the model.
- **Where a product-level Astrid mode would live**: a `src/vs/workbench/contrib/astridMode/`
  contribution registered with `registerWorkbenchContribution2` and imported from
  `workbench.desktop.main.ts`, reading/writing layout through `IWorkbenchLayoutService`
  exactly as Zen Mode does (exact restore), a title-bar action on
  `MenuId.TitleBarAdjacentCenter` (the Agents Window precedent), and the Astrid UI itself
  shipped as a **built-in extension** (`extensions/astrid/` is auto-bundled,
  `build/lib/extensions.ts:51`; built-ins keep `enabledApiProposals`,
  `extensionsProposedApi.ts:110-113`). Layer rules: `local/code-layering` (eslint) —
  `common` → `browser` → `electron-browser`; `pnpm run valid-layers-check`.
- **Upstream tracking**: monthly releases, a private `distro` mixin for Microsoft-only parts
  (`package.json:5`), Copilot wired in as `defaultChatAgent`. Every month the fork rebases on
  ~1–2k upstream commits; the Agents Window alone is a moving 720-file subsystem.
- **Licence**: MIT (`LICENSE.txt`); the Microsoft marketplace and Copilot are *not* part of
  what a fork may ship.

### E. Data, auth, shared rules for a VS Code client

- **API**: `/api/v1/...` (astrid-ios `docs/API_ENDPOINTS.md`, `docs/API_CONTRACT.md`); live
  updates on `GET /api/v1/sse`.
- **Sign-in exists for native clients**: the browser hand-off
  (`astrid-web/lib/auth/desktop-handoff.ts`) — `https://astrid.cc/auth/desktop?client=…&state=…&code_challenge=…`,
  PKCE S256, callback `astrid://auth/callback?code=…`, then
  `POST /api/v1/auth/desktop/exchange {client, code, codeVerifier}` → session token in the body.
  `DesktopClientId` is `'windows'|'ios'|'mac'|'android'` with the callback scheme fixed to
  `BRAND.appUrlScheme`; a `vscode` client whose callback is
  `vscode://graceful-tools.astrid/auth/callback` is a ~20-line web change. The alternative,
  an OAuth 2.1 public client against `/oauth/authorize` + `/api/v1/oauth/token`, exists today
  but its scopes are MCP-shaped (`tasks:*`, `lists:read`, `comments:*`) — no chat, members,
  settings, search, SSE — so the hand-off is the right door for the full client.
- **Shared rules without a Swift/Rust bridge**: `astrid-core/crates/astrid-rules-wasm`
  (wasm-bindgen, `runJson(request)` → `renderMarkdown`, `smartParse`, `listAccess`,
  `completion`/`nextOccurrence`, `searchTasks`, `rowsForList`, `board`, pickers…) is the
  same door the Apple apps reach through UniFFI; astrid-web already vendors it for Node
  (`lib/core-rules/wasm.ts`). The extension host is Node → the extension loads it and
  **reimplements no rule** (ASTRID.md rule 4 holds). The stateful core (`App`: cache,
  Outbox, sync, SSE) has no wasm target yet; the spike writes a thin fetch+SSE client in TS
  and a later step adds a `wasm32` `App` build to astrid-core.
- **The 4th client, by the existing rules**: astrid-core README rule 8 — each platform keeps
  its own binding layer in its own repo — so this is `astrid-vscode`, pinning astrid-core by
  revision like `core/Cargo.toml` does.

### F. Already free today: Astrid tools inside VS Code's chat

astrid.cc hosts an MCP server at `https://astrid.cc/mcp` with OAuth discovery
(`/.well-known/oauth-authorization-server` → `registration_endpoint = /api/v1/oauth/register`,
PKCE S256) and 13 tools (`get_tasks`, `get_task`, `create_task`, `update_task`, `get_lists`,
`create_list`, `update_list`, `add_comment`, `get_task_comments`, `get_list_messages`,
`add_blocker`, `remove_blocker`, `get_agent_queue`). VS Code's MCP client does dynamic client
registration itself (`src/vs/base/common/oauth.ts:947 fetchDynamicRegistration`), and
astrid.cc/docs/mcp already emits the one-click `vscode:mcp/install?{"name","type":"http","url"}`
link. **The chat half of "Astrid mode" — talk to your lists from VS Code — needs zero new
code**; the extension's job is to switch the chat view into Astrid context, not to build a
chat.

---

## Recommendation

**Build Astrid mode as an extension first; keep the fork as a later, optional shell.**

- Everything the full takeover needs — three columns, locked board editor, the tap, auth,
  live data, shared rules, chat tools — is on the **stable** extension API. The gaps (exact
  layout restore, a title-bar button, a shipped system-wide hotkey) are polish, and two of
  the three have good-enough substitutes (a restore record in `globalState`; a status-bar /
  Touch Bar / `vscode://` tap, with ⌥Space from the Astrid Mac app as the "real" one tap).
- An extension runs in stock VS Code, VS Code Insiders, Cursor and Windsurf — where Jon's
  users already are. A fork asks them to install a second editor and leave Copilot behind.
- A fork's defining advantages (exact restore via `IWorkbenchLayoutService`, a
  `TitleBarAdjacentCenter` button, an Astrid *Window* à la Agents Window) are additive: the
  Astrid UI ships as a built-in extension either way (`extensions/astrid/`), so nothing
  built for the extension is thrown away if "Astrid Code" for Mac is wanted later. Decide
  that after the extension exists and the restore heuristic has been lived with.
- Cost of the fork, if taken: a monthly rebase on a repo that is adding a second workbench,
  our own signing + notarization + update channel, and an Open VSX gallery — real,
  recurring, and unrelated to Astrid.

Staged route: **(1)** spike below → **(2)** real data layer (astrid-core `App` to wasm) +
cross-platform contract tests → **(3)** publish on Marketplace/Open VSX + the `vscode` hand-off
client in astrid-web → **(4)** optional: Code-OSS Mac build with the title-bar switch and
exact restore, Astrid extension built in.

## Spike plan — `astrid-vscode`, an extension that proves the one-tap shift on this Mac

Goal: against **stock VS Code on macOS**, one tap turns a coding window into the Astrid
three-column layout with real data (read + complete + create), and a second tap puts the
coding window back as closely as the platform allows. Not in scope: a chat composer,
offline/Outbox, attachments, Marketplace publishing.

### Auth and data decisions (verified this session, no astrid-web change needed)

- **OAuth 2.1 public client via dynamic registration** — not the desktop hand-off.
  `astrid-web/lib/api-auth-middleware.ts:81` accepts `Authorization: Bearer astrid_…` on
  `/api/v1`; the legacy SSE handler re-exported at `/api/v1/sse` does too
  (`app/api/sse/route.ts:54-60`, needs `sse:connect` or `tasks:read`); chat routes gate on
  `chat:read`/`chat:write` (`app/api/v1/chat/channels/…/route.ts`). Registration with no
  `scope` grants `SCOPE_GROUPS.ai_agent` (`lib/oauth/oauth-client-manager.ts:38`) =
  tasks/lists/comments/chat read+write, `user:read`, `sse:connect` — everything the spike
  reads. **Redirect URIs must be HTTPS or loopback** (`oauth-client-manager.ts:78-80`), so
  the sign-in callback is a one-shot `http://127.0.0.1:<port>/callback` listener in the
  extension host (the standard VS Code pattern), not `vscode://`. Token + refresh + client id
  live in `SecretStorage`. The hand-off path stays the fallback if a route turns out to be
  cookie-only.
- **Rules from astrid-core, not reimplemented**: vendor
  `astrid-web/packages/astrid-rules/node/` (`astrid_rules_wasm.js` + `_bg.wasm`, `REVISION`
  `52a371d…`) and call `runJson` for `listAccess` (what buttons to show), `renderMarkdown`,
  `smartParse` (quick-add), `completion` (**the only way a task gets completed** — it yields
  the PATCH body with repeat rollover), `rowsForList`/`board` (row order, columns).
- **Data layer for the spike is thin TS**: `fetch` with Bearer + one 401→refresh; SSE via
  Node `fetch` + a line parser (no `EventSource` in the extension host), reconnect with
  backoff; events per `docs/API_CONTRACT.md` §SSE into an in-memory store. The real data
  layer (astrid-core `App` → `wasm32`) is stage 2, not the spike.

### Repository and tooling

New repo `Graceful-Tools/astrid-vscode` (astrid-core rule 8: each platform's binding layer
in its own repo; the extension bundle must not depend on astrid-web's Next.js tree).
TypeScript + esbuild (two entries: `src/extension.ts` → `dist/extension.js` cjs;
`media/*.ts` → browser esm for the webviews), `@vscode/test-electron` + mocha,
`vsce package` → `.vsix`. Publisher/ext id placeholder `graceful-tools.astrid`.

```
astrid-vscode/
  package.json  tsconfig.json  esbuild.mjs  .vscode/launch.json
  src/extension.ts              activate(): wire the pieces below, status-bar item
  src/mode/ModeController.ts    enter / exit / departure detection, globalState record
  src/mode/LayoutSnapshot.ts    tabGroups snapshot + reopen
  src/auth/OAuthClient.ts       discovery → DCR → PKCE → loopback → token; SecretStorage
  src/data/AstridClient.ts      fetch + SSE
  src/data/Store.ts             lists / tasks / messages, change events
  src/rules/Rules.ts            loads vendor wasm, typed runJson helpers, REVISION assert
  src/views/ListsTree.ts        TreeDataProvider — My Tasks · Search · Favorites · Lists · Public
  src/views/BoardPanel.ts       WebviewPanel in ViewColumn.One: list/board + inline detail
  src/views/ChatView.ts         WebviewViewProvider in the secondary sidebar (read-only transcript)
  src/mcp/McpProvider.ts        McpServerDefinitionProvider → https://astrid.cc/mcp
  media/board.ts  media/chat.ts  media/*.css   vanilla, no framework
  vendor/astrid-rules/          copied from astrid-web/packages/astrid-rules/node + REVISION
  test/suite/*.test.ts
```

`package.json` contributions: commands `astrid.toggleMode / enterMode / exitMode / signIn /
signOut / openList / completeTask / createTask / refresh`; keybinding `cmd+shift+a` for
`astrid.toggleMode` (⌥Space is the Mac app's — it will fire `vscode://graceful-tools.astrid/mode`
through `registerUriHandler` later); `viewsContainers.activitybar: astrid` with view
`astrid.lists`, `viewsContainers.secondarySidebar: astridChat` with webview view
`astrid.chat`; `menus.view/title` on `astrid.lists` (toggle, refresh, sign-in);
`mcpServerDefinitionProviders: [{ id: "astrid.mcp", label: "Astrid" }]`; webview panel
serializer `astrid.board`. Activation is implicit from the contributions plus
`onStartupFinished` so the status-bar tap exists before the first use.

### The mode state machine (`ModeController`)

`globalState["astrid.mode"] = { active, snapshot }` with
`snapshot = { tabs: [{uri, viewColumn, pinned, preview}], activeTabUri, groupCount,
assumed: { sidebarVisible, panelVisible, auxBarVisible } }`.

**Enter**, in this order (every step idempotent, so a double tap is harmless):
1. no-op if `active`.
2. snapshot `window.tabGroups.all` (text/diff/notebook inputs only — webviews and
   terminals are not reopenable by URI), `groupCount`, and the heuristics:
   `panelVisible = window.terminals.length > 0`, `sidebarVisible = true` (no API can read
   it — see Findings C.1), `auxBarVisible = false`.
3. `workbench.action.closePanel`.
4. `workbench.action.joinAllGroups` → `workbench.action.editorLayoutSingle` →
   `tabGroups.close(nonDirtyTabs)` (dirty tabs stay open and are recorded as left alone).
5. reveal `BoardPanel` in `ViewColumn.One` → `workbench.action.lockEditorGroup`.
6. `astrid.lists.focus` (opens the primary sidebar on our container) →
   `astrid.chat.focus` (opens the secondary sidebar on ours) → `panel.reveal(One, false)`.
7. `setContext astrid.modeActive true`; status-bar item → "Astrid ✓"; save `globalState`.
   Activity bar and status bar are left alone in the spike (snapshot keeps room for a later
   option to hide them).

**Exit**: `workbench.action.unlockEditorGroup` → dispose the board panel →
`workbench.action.closeAuxiliaryBar` → sidebar: `focusSideBar` + `workbench.view.explorer`
if `assumed.sidebarVisible` else `closeSidebar` → `focusPanel` only if
`assumed.panelVisible` → `vscode.setEditorLayout` with `groupCount` columns → reopen tabs
with `window.showTextDocument(uri, { viewColumn, preview, preserveFocus: true })`, active
one last → clear context, state, status bar.

**Honest limits** (the fork line): prior sidebar/secondary-sidebar visibility, which
viewlet was active, column widths and group sizes are not readable from an extension;
restore is "Explorer visible, panel if you had a terminal, same files in the same columns".

**Leaving the mode by hand**: a lock makes Quick Open put a file into a *new* group. While
active, watch `tabGroups.onDidChangeTabGroups`; if a second group appears, show a one-time
status-bar hint ("Restore coding layout") and **do not auto-exit** (it would close their
file). After a window reload with `active: true`, the `astrid.board` serializer re-creates
the panel and the mode stays on.

### Views

- **Lists tree**: the Mac sidebar's sections and order (`MacRootView.swift:1087-1140`);
  selection runs `astrid.openList`; Search is `showInputBox` → `/api/v1/search`.
- **Board panel**: one webview (`retainContextWhenHidden`, nonce CSP, `enableScripts`);
  list/board modes from `rowsForList` / `board`; markdown through `renderMarkdown`; the
  detail is an inline right-hand pane *inside* the webview (a second editor group would
  break the single-group contract); messages `openList / rows / selectTask / complete /
  create`; `complete` goes through `Rules.completion` → PATCH.
- **Chat column**: a read-only transcript of the selected list's channel (proves the
  secondary-sidebar container and the three-column shape); composing is deferred to VS
  Code's own chat with the Astrid MCP tools (`McpProvider`). A native composer with the
  agent-typing stream is a product feature, not a layout spike.

### Verification

Manual, on this Mac in the Extension Development Host (F5; Copilot Chat left enabled for
the MCP check):
1. Start from two editor groups + a terminal + Explorer. Tap → panel closed, one locked
   group showing the board, Astrid lists on the left, chat column on the right, no file tabs.
2. Tap again → terminal back, two groups with the same files, Explorer, board gone.
3. Dirty editor → it survives, mode still enters. 4. ⌘P a file in mode → new group + hint,
   mode stays, exit restores. 5. Reload window in mode → board returns, exit still works.
6. Sign-in round trip (loopback), token survives reload, a 401 refreshes once, an SSE
   `task_updated` from astrid.cc reaches the board within ~2 s.
7. Complete a repeating task → next occurrence matches the web app (same core).
8. `listAccess` hides "create" on a browsable public list.
9. VS Code chat: "list my Astrid tasks" calls the MCP tool after the trust prompt.

Automated (`@vscode/test-electron`): enter→exit leaves `tabGroups.all` equal to the
snapshot (URIs + columns); enter is idempotent; `Rules.completion` passes the fixtures in
`astrid-web/packages/astrid-rules/fixtures` under the vendored wasm; `OAuthClient` PKCE /
state / loopback-callback unit tests against a mocked discovery document.

### Decisions the spike should settle before a product call

- Is heuristic layout restore acceptable, or is exact restore (fork-only) the bar?
- Is status bar + ⌘⇧A + ⌥Space-from-the-Mac-app enough of a "tap" without a title-bar button?
- Does a locked group plus Quick Open spawning a second group feel broken? (The only full
  ownership of the editor area is a fork or a custom editor over a virtual document.)
- Chat: MCP-through-VS-Code-chat needs Copilot Chat present and signed in; does the product
  need an Astrid-native composer?
- Which name/identity (`graceful-tools.astrid`) and whether to list on Open VSX as well as
  the Marketplace.
