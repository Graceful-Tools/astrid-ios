# Moving the Apple apps onto astrid-core

*The ledger for replacing the Swift copies of Astrid's rules and data layer with the shared Rust
core, [astrid-core](https://github.com/Graceful-Tools/astrid-core). Architecture rules stay in
[ASTRID.md](../ASTRID.md); this file is the migration's plan, state and findings.*

## Why

Every rule the apps enforce exists three times: on the web (canonical), in astrid-core (which the
Windows app runs on), and in Swift here. The copies drift — astrid-core's `docs/CONTRACTS.md`
records seventeen divergences, several of them bugs that cost real users something (D6 locks
people out of private lists on Apple). The goal is one implementation: the core decides, the
Swift apps render and dispatch.

## How the apps reach the core

```
Astrid App / Astrid Mac (Swift)
        │  import AstridCore                         Packages/AstridCore (SwiftPM)
        ├── CoreRules.ask(...)      sync, stateless ─┐   Sources/AstridCore        hand-written facade
        └── CoreClient.run(...)     async, stateful ─┤   Sources/AstridCoreBindings  generated (UniFFI)
                                                     │   AstridCoreFFI.xcframework   the Rust static lib
                                     core/astrid-apple (Rust, UniFFI)
                                                     │
                     astrid_core::rules::run_json ───┤   the pure contracts (repeating, markdown, …)
                     astrid_core::app::App::run_json ┘   the client: cache, Outbox, sync, network
```

- **Two doors, one envelope.** `rules::run_json` answers pure rules synchronously (safe in a view
  body — a round trip is ~15 µs); `App::run_json` runs commands against the cache and network.
  Both take and return JSON in the `/api/v1` wire shape the Swift models already encode, inside
  `{"ok":…,"value":…,"error":…}`. A new capability is a new `kind`, not a new symbol.
- **The bindings live here**, not in astrid-core (its rule 8: each platform keeps its own binding
  layer, as astrid-windows keeps `astrid-ffi`).
- **The core is pinned by revision** in `core/Cargo.toml` and bumped deliberately.
- **Xcode Cloud never builds Rust.** `Packages/AstridCore/Package.swift` links a local
  `AstridCoreFFI.xcframework` when one is present (built by `scripts/core/build-xcframework.sh`,
  gitignored) and otherwise a released zip pinned by URL and checksum.

### Commands

```bash
scripts/core/build-xcframework.sh --core ../astrid-core   # build against a local astrid-core
scripts/core/build-xcframework.sh                         # build the pinned revision
(cd Packages/AstridCore && swift test)                    # the bridge's own tests, on the Mac host
```

## Method, per domain

1. The Swift tests are the specification. Point the Swift API at the core (keep its signature),
   run its tests unchanged.
2. A test that fails is a **divergence**: decide which side is right against the web (canonical),
   record it below and in astrid-core `docs/CONTRACTS.md`, and change the test only when the
   core's answer is the web's. Never "fix" the core to match a Swift bug.
3. Delete the Swift implementation. What remains is a signature that delegates.
4. Gates: `npm run predeploy` and the Mac suite.

## State

| Domain | Swift that goes | Status |
|---|---|---|
| Repeating rollover + completion outcome | `RepeatingTaskHandler.swift` math, `TaskService.calculateNextOccurrence` | **done** — `rules` `completion` / `nextOccurrence`; 78 Swift tests pass against the core |
| Markdown | `MarkdownBlocks.swift`, `String+Markdown.swift`, two platform renderers | **done** — `rules` `renderMarkdown`; one shared `MarkdownView` |
| Permissions | `TaskList.role(for:)`, `ListPermissions` (D6, D29) | **done** — `rules` `listAccess` |
| Smart parse | `SmartTaskParser.swift` (D12, D30) | **done** — `rules` `smartParse`, 12 languages |
| Filters, sort, subtasks, recently completed, My Tasks, board, search, palette | `Core/Filters/*`, view pipelines, `ProjectStatus`, `MacTaskSearch`, `FuzzyMatch` | with the data layer — they run over the whole task set, which the core already holds |
| Mentions, keyboard table, editing session, row projections | `AutocompleteSupport`, `MacAutocomplete`, `Astrid Mac/Keyboard`, `EditingSession`, `Core/Layout/*` | planned |
| Data layer — tasks, lists, sync | `TaskService`/`ListService`/`SyncManager` internals, the Outbox's task and list kinds | **done** — the services are faces over `CoreSession`; `CoreUpgrade` carries Core Data and queued writes over once |
| Data layer — comments, attachments, chat, members, projects | `CommentService`, `AttachmentService`, `ChatService`, `ListMemberService`, `ProjectService`, the rest of the Outbox, Core Data, `SSEClient` | next |
| Data layer — external sync, API client | `Core/Sync/*` (Google, GitHub), `AstridAPIClient` | after that; Apple Reminders stays native |

**Stays native regardless:** Apple Reminders (EventKit), Foundation Models, Sign in with Apple /
passkeys / Google sign-in UI, UserNotifications scheduling, badge, BGTask, StoreKit review, address
book import, NWPathMonitor (behind the core's `Reachability`), the share extension's intake.

## Findings

Divergences and gaps found while migrating. Each is either resolved toward the web in the core,
or filed.

- **Repeat counting never reached the server from any client.** iOS, Mac and the core all roll a
  repeating task forward on the device and send the new due date with `completed: false`; the
  server rolls (and counts) only when it receives `completed: true`, and the v1 update route
  ignores an `occurrenceCount` in the body. So "end after N times" only works for completions
  made on the web. The core's `completion` rule now counts locally; the server-side fix is filed.
- **Swift never cleared a "won't do" reason on reopen** — moot on Apple today (Swift has no
  `closedReason`), and the core's rule does.
- Found by the mapping pass (2026-09-28), not yet in `CONTRACTS.md`: the completion-filter values
  mean different things (Swift `completed`/`incomplete` vs core `hide`); Mac mentions insert a
  plain `@label` instead of `@[Name](id)`; snooze moves `dueDateTime` on Apple but `reminderTime`
  in the core, with different choices; iOS My Tasks is "assigned to me" where the Mac and core
  include unassigned; due-date quick picks have no "No due date" on Apple; priority labels are
  off by one between Apple and the core; each Apple list picker applies half of
  `is_destination`; CONTRACTS D8 is stale (the Mac already uses the shared assignee builder).

## The data layer: design

The Swift data layer — `AstridAPIClient`, the Outbox, Core Data, sync, SSE, the services' write
paths — duplicates the core's `App` end to end. It moves as follows.

1. **One cache.** The core's SQLite store replaces Core Data and `outbox.json`. No entity is ever
   synced by both engines: two caches that each think they are the truth is the regression to
   avoid above all others.
2. **Adapter services.** `TaskService`, `ListService`, `CommentService`, … keep their public API and
   their `@Published` state, because ~40k lines of views bind to them. Their bodies become core
   commands; their state is refreshed from core reads when the core reports a change
   (`CoreSession.subscribe` → `{"change":"task","id":…}` and friends).
3. **Cut over by coupled group, atomically.** Tasks, lists, comments, attachments, projects and
   members share temp ids and one journal, so they move together. Chat, account/settings, agents
   and connections can move separately.
4. **Upgrade without losing anything.** On the first launch of a core build: seed the core's cache
   from Core Data (so an offline launch still shows everything), and replay any pending Swift
   Outbox entries as core commands (so an offline edit made before the update still reaches the
   server). Then Core Data and `outbox.json` are deleted.
5. **Auth stays Swift, the credential is shared.** Sign in with Apple, passkeys, Google and
   session renewal remain native; they write the session cookie to the Keychain item the core
   reads on every request (`CoreCredentials`). Sign-out calls the core's `signOut`, which wipes its
   cache and journal, as the Swift sign-out does.
6. **The platform is stated** — `ios-app` / `mac-app` in `x-platform`, as the Swift client did.

## What the core had to learn from the Apple apps

Moving the data layer surfaced behaviour the Swift layer had and the core — so Windows — did not.
Each is fixed in astrid-core with a test, not papered over in Swift:

- **Calendar steps in the person's zone** for timed tasks (D1, D3): "monthly at 2pm" across a
  daylight-saving change, the third Tuesday on the person's calendar.
- **A pull never resurrects a deletion made here** whose delete is still on its way, or just landed
  under a fetch already in flight (Swift's `recentlyDeletedIds`).
- **A pull never shows a new task twice**: the server's copy of a task made here replaces its
  temporary row by the create's idempotency key.
- **A full pass forgets what the server no longer has** — a list deleted on the web while the
  device was away (Swift task 53071260) — except unsent rows and rows that moved after the pass
  began (f07dff56).
- **The live stream cannot undo a newer local edit** or bring back a task deleted here (Swift's
  `LiveUpdatePolicy`).
- **Settings a shell writes are all kept**: `updateList` silently dropped `defaultIsPrivate`,
  `publicListType`, `projectId`, `aiAgentConfig` and more.
- **Completion carries the task as the person sees it, the timer, and an inbound provider's source
  and time**; creation carries repeat and privacy, and can skip list defaults a shell applied.

## Data-layer gaps in the core

What the core must grow before the Swift data layer can go (from the 2026-09-28 mapping). Done:
a configurable platform header (`Config.platform`), change events as JSON (`Change::to_json`).
Still to do:
`completeTask` carrying the on-screen task, the timer, an inbound source and `completedAt`;
`createTask` carrying repeat, privacy and reminder; a bulk wire-shape read of cached tasks; a cache
seed for the upgrade; project create/delete and "create board for list", shortcode
resolve, chat paging / delete / virtual channels / agent responses / AI assistant settings,
attachment delete and replace, invitation cancel and role change, `updateCustomAgent`, the Copilot
cloud-agent token, contacts upload / search / recommended, app-version check, local (no account)
mode, a client-side GitHub sync pass, offline-queued member operations, and a read that returns
every cached task in the wire shape (the Swift views filter `[Task]` themselves today).
