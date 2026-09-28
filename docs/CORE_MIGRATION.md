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
| Repeating rollover + completion outcome | `Utilities/RepeatingTaskHandler.swift` math, `TaskService.calculateNextOccurrence` | **in progress** — delegating to `rules` (`completion`, `nextOccurrence`) |
| Markdown | `Core/Filters/MarkdownBlocks.swift`, `Extensions/String+Markdown.swift` | next |
| Permissions | `TaskList.role(for:)`, `Core/Lists/ListPermissions.swift` (D6) | planned |
| Filters, sort, subtasks, recently completed, My Tasks | `Core/Filters/*`, `TaskListView` inline pipeline, `MacRowPipeline`, `MacMyTasks` | planned |
| Board columns and moves | `Core/Board/ProjectStatus.swift` (rules only; geometry stays) | planned |
| Smart parse, search grammar, mentions | `Utilities/SmartTaskParser.swift`, `AutocompleteSupport`, `MacAutocomplete` | planned |
| Keyboard table, palette scoring, editing session | `Astrid Mac/Keyboard`, `FuzzyMatch`, `Core/Layout/EditingSession.swift` | planned |
| Row projections (due labels, leading control, assignee, pickers) | `Core/Layout/*` | planned |
| Data layer: API client, Outbox, cache, sync, realtime, services | `Core/Networking`, `Core/Outbox`, `Core/Persistence`, `Core/Sync`, `Core/RealTime`, `Core/Services` | planned — last, see below |

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

## Data-layer gaps in the core

What the core must grow before the Swift data layer can go (from the 2026-09-28 mapping):
session renewal (`/api/v1/auth/mobile-session`), a configurable `x-platform` header (hard-coded
`windows-app`), task blockers, project create/delete and "create board for list", shortcode
resolve, chat paging / delete / virtual channels / agent responses / AI assistant settings,
attachment delete and replace, invitation cancel and role change, `updateCustomAgent`, the Copilot
cloud-agent token, contacts upload / search / recommended, app-version check, local (no account)
mode, a client-side GitHub sync pass, offline-queued member operations, and a read that returns
every cached task in the wire shape (the Swift views filter `[Task]` themselves today).
