# Moving the Apple apps onto astrid-core

*The ledger for replacing the Swift copies of Astrid's rules and data layer with the shared Rust
core, [astrid-core](https://github.com/Graceful-Tools/astrid-core). Architecture rules stay in
[ASTRID.md](../ASTRID.md); this file is the migration's plan, state and findings.*

## Why

Every rule the apps enforce exists three times: on the web (canonical), in astrid-core (which the
Windows app runs on), and in Swift here. The copies drift — astrid-core's `docs/CONTRACTS.md`
records its divergences (D1–D32), several of them bugs that cost real users something (D6 locks
people out of private lists on Apple). The goal is one implementation: the core decides, the
Swift apps render and dispatch.

## How the apps reach the core

```
Astrid App / Astrid Mac (Swift)
        │  import AstridCore                         Packages/AstridCore (SwiftPM)
        ├── CoreRules.ask(...)      sync, stateless ─┐   Sources/AstridCore        hand-written facade
        └── CoreSession.run(...)    async, stateful ─┤   Sources/AstridCoreBindings  generated (UniFFI)
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
| Search | `Core/Filters/TaskSearch.swift` | **done** (AITD-459) — the core's `searchTasks` answers as iOS's search did; both apps ask it through `TaskSearchModel`, asynchronously, and the old Swift tests run against the core |
| List rows: filters, sort, subtasks, recently completed, My Tasks, saved-filter counts | `ListTaskFiltering`, `SubtaskSplicing`, `MyTasksScope`, `applyCompletionFilterWithWindow`, `MacMyTasks`, the iOS and Mac row pipelines | **done** (AITD-460) — the core's `rowsForList` (ids only) answers as iOS's list did; both apps ask it through `ListRowsModel`, asynchronously, with the inputs they hold ahead of the cache; the sidebar's saved-filter badges come from `listCounts`; iOS's search splices through `searchTasks` |
| Board and pickers | `ProjectStatus` (columns, cards, moves, drops), `ProjectStatePicker`, `ProjectStateMove`, `MacBoardMove`, `ListFilingTargets`, `DueDateQuickPicks`, `AssigneeOptions` | **done** (AITD-461) — the core's `board`, `dropBoardCard`, `moveTaskToColumn` / `setTaskStatus` and `taskStatusOptions` answer as iOS's board did; `listPicks` (`asToggles`), `assigneeOptions` and `dueDateOptions` as its pickers did (D43–D50). Both apps ask through `BoardModel` / `TaskStatusOptions` and `PickerAnswers` (`ListPicks`, `DuePicks`, `AssigneePicks`), asynchronously, with each answer kept and shown until the next lands |
| Stays Swift from that group | `EditingSession`, `CustomRepeatSummary`, `AssigneeResolver`, the repeat presets (`Task.Repeating`) | `EditingSession` is the "resigning saves" focus policy: an `ObservableObject` the views bind to synchronously; the core's `editing` module states the same rule, but routing focus changes through an async door buys nothing. `CustomRepeatSummary` words a custom repeat in English, and the core answers parts with keys iOS has no strings for (D49) — moving it means twelve languages of new copy. `AssigneeResolver` names the face on every row while it draws. The repeat picker lists its own enum, now under the same `repeating.*` keys the core uses (D49) |
| Palette | `FuzzyMatch` (Mac) | not started — the core has `palette` |
| Mentions, keyboard table, row projections | `AutocompleteSupport`, `MacAutocomplete`, `Astrid Mac/Keyboard`, `Core/Layout/*` | planned |
| Data layer — tasks, lists, sync | `TaskService`/`ListService`/`SyncManager` internals, the Outbox's task and list kinds | **done** — the services are faces over `CoreSession`; `CoreUpgrade` carries Core Data and queued writes over once |
| Data layer — comments, chat, the live stream, the Outbox | `CommentService`/`ChatService` internals, the whole Swift Outbox runner, `SSEClient`, the Core Data comment and chat caches | **done** — every write goes through the core's journal; one live stream (the core's) for tasks, lists, comments, chat, typing and settings; `CoreUpgrade` moves any queued Swift write, pictures included |
| Data layer — members, boards | `ListMemberService` (and its Core Data queue), `ProjectService` (and its Core Data cache) | **done** — membership changes sent at once, queued only offline (D31); boards made, deleted and refreshed by the core |
| Settings writes | `ReminderSettings`' own pending flag, `MyTasksPreferencesService`'s API calls | **done** — reminder settings journaled; My Tasks filters sent through the core, not queued |
| Data layer — attachments (download/replace/delete), account/settings/agents/connections, Core Data | `AttachmentService` network, the settings services, Core Data | next |
| Data layer — external sync, API client | `Core/Sync/*` (Google, GitHub), `AstridAPIClient` | Google **done** (AITD-463, the core's `syncExternal`); GitHub and the API client after that; Apple Reminders stays native |

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
- Found by the mapping pass (2026-09-28), since recorded as CONTRACTS D22–D28: the
  completion-filter values mean different things (Swift `completed`/`incomplete` vs core `hide`);
  Mac mentions insert a plain `@label` instead of `@[Name](id)`; snooze moves `dueDateTime` on
  Apple but `reminderTime` in the core; iOS My Tasks is "assigned to me" where the Mac and core
  include unassigned; due-date quick picks have no "No due date" on Apple; priority labels are
  off by one between Apple and the core; each Apple list picker applies half of `is_destination`.
  (D8 is resolved — the Mac uses the shared assignee builder, AITD-401.)
- **On disagreement the Mac follows iOS** (Jon, 2026-10-03). Where the two Apple apps disagreed
  with each other, the Mac now does what iOS does, through one shared Swift helper both call:
  D23 — a Mac mention inserts the `@[Name](id)` reference (`ReferenceMarkup`); D25 — My Tasks is
  "assigned to me" on both (`MyTasksScope`); D28 — both list pickers leave out virtual lists and
  only those (`ListFilingTargets`); search is iOS's on both (`TaskSearch`); and iOS's private
  subtask splice gave way to the shared `spliceSubtasks` (the same rule — the "8 vs 10" was the
  depth walk's cap against the splice's, not a disagreement). D26 and D27 were already alike on
  the two apps. Apple-vs-core differences (D22, D24, the unassigned half of D25, the status half
  of D28, D26, D27) stand until settled against the web.
- **"Recently completed" sort never reached a list.** Task c6e87fb8 added `completedAt` to a copy
  of the sort nothing called (`Core/Board/TaskSort.swift`), so its tests passed while both apps
  sorted such a list as auto. The case is now in `sortTasksByListSetting`, and the copy is gone.

- **The core's search is not yet iOS's** (found 2026-10-03, AITD-456). `services/search.rs` needs
  two characters (iOS one), includes completed tasks (iOS uses the default completion window) and
  subtasks (iOS top-level only), and sorts by title match then recency (iOS by priority). Those
  move toward iOS in the core before `TaskSearch` can delegate. Expect the same of the other
  projections: run the Swift tests against the core before deleting a copy, not after.
  **Resolved (AITD-459):** the core moved to iOS on all four (and takes a plain query as typed —
  untrimmed, unsplit); `TaskSearch.swift` is gone. Left as a superset: the web's search grammar
  and identifier hits. One deliberate difference: an assignee with neither name nor email no
  longer matches "Unknown User".
- **The core's list rows were not iOS's either** (found 2026-10-03, AITD-460, by comparing iOS's
  pipeline with `rowsForList`; afterwards a differential test over 1,200 random lists — real,
  saved-filter, My Tasks and the everything view — agreed row for row). Four ways, all moved toward
  iOS in the core (CONTRACTS D40–D42): a list with no `sortBy` is manual on iOS (auto in the
  core, the Mac and web); a spliced subtask obeys only the view's completion filter, and comes
  from every task, not just the list's members; and ties in every sort fall in iOS's store order
  (`TaskOrdering`) rather than the cache's. The Mac, which drew through the same Swift copies with
  its own sort default and subtask rule, follows iOS on all four now.

- **The board and the pickers were not iOS's either** (found 2026-10-03, AITD-461, by running the
  Swift board and picker tests against the core — then a differential test over 1,200 random boards,
  every column and a drop per board, agreed card for card). All moved toward iOS in the core
  (CONTRACTS D43–D50): the board drew subtasks as cards, in cache order, every finished task forever
  and at most 50 a column; never named a default column from a cached status row; wrote an edit of
  nothing when a card was moved to its own column, un-completed last, and offered Done in the state
  menu; had no drop that rearranges a column. Not in the earlier scope check: the board's Done reads
  the list's filter its own way (`hide` hides, absent is the window) and times a card by `updatedAt`,
  never `completedAt`; a time pick on an all-day task landed on the day before west of UTC; and iOS's
  own drop placed the card against a column computed without the board's custom states and with
  subtasks counted — the core places it against the column the board drew. The pickers: the
  assignee rule differed five ways (D47), a quick date pick on a timed task keeps no time on iOS
  (D48), the repeat presets used keys iOS lacks (D49), and the list picker hid the task's own lists,
  sorted by name and capped at ten (D50). The Mac, which had its own board grouping (no Done window,
  no manual order, subtasks as cards), its own assignee builder (unhydrated members and the holder
  offered) and kept a timed task's time on a quick date, follows iOS on all of it now; its assignee
  trigger still names a holder from outside the list.

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

- **Chat, whole**: a channel resolved for a list or a virtual list (My Tasks) from the cache first;
  history paged backwards with the window pruning rule (AITD-354: inside a page's time window the
  server is right, outside it nothing is known, and an unsent message is never taken); a message
  that carries a type, a picture from this device and the row id a view drew; the local-only
  delete, withdrawing an unsent send; agent responses and asking the server for Astrid's.
- **The server's copy replaces the optimistic chat message it echoes**, by `clientRequestId`, from
  whichever path brings it first — stream, page or delivery — and a reply to the optimistic id
  still lands.
- **A photo comment waited for nothing.** Its upload and the comment were two journal entries in
  different lanes with no dependency, so the comment could go out naming the file by its temporary
  id, be refused, and be dead-lettered — the photo gone. The same for a comment on a task created
  offline. The scheduler now holds a write while an older, unfinished entry has still to produce a
  temporary id it names. (Windows had this too.)
- **Signing out left the live stream connected** on the departing account's cookie, delivering its
  events into the cache the next person sees. Sign-out now drops it. (Windows had this too.)
- **The stream says when it is up** (`stream` change, `streamState`), **can be told to start over
  now** (`reconnectStream` — on wake and when the network returns, instead of waiting out a
  backoff), and typing events carry the agent's name and may name a task.
- **Refused writes can be retried** (`retryDeadLetters`), and `outboxStats` names the newest few and
  why.

- **The roster the web sends was unreadable.** `GET /lists/{id}/members` flattens the person into
  each row and lists pending invitations beside the members; decoded as `ListMember`s every row
  was dropped, and a roster refresh wiped the cached members (Windows too).
- **Membership changes work offline** (D31): sent at once and a refusal fails the command, as
  before; only a failed network queues one, and a queued invitation is an invitation, never a
  member a permission check could read.
- **A comment thread refresh forgets deletions and keeps edits on their way**; a comment deleted
  here no longer came back on refresh. The server's copy of a comment replaces the optimistic one
  it echoes, as chat's does.
- **Boards can be made (from a list, in one request) and deleted**, with the cascade in the cache;
  a board deleted elsewhere goes on the next refresh.
- **No live comment or chat event ever reached the cache.** The web wraps the row beside its ids
  (`data.comment`, `data.message`) and names deletions `commentId` / `messageId`; read as the row
  itself, every one was dropped (Windows too). A comment edit from the stream now changes the
  text and keeps the author and files the event leaves out (AITD-331).
- **Waiting on a task** (D32): an add or a removal is sent at once and a refused cycle is shown,
  not dead-lettered unseen; queued only offline. The picker asks the server's permission-filtered
  search first, and ranks the task's own lists first, as web does (the core ranked the whole
  board's).

Found on the Swift side while doing it: the Google Tasks and GitHub mirrors were nudged to push a
local edit by the Swift Outbox's enqueue notice. When task writes moved into the core that notice
went silent, so an edit reached Google only on the next foreground. `TaskService` and `ListService`
now post `LocalMutation` on every write, with its sync source (regression test in
`CoreTaskServiceTests`). And nothing refreshed `ProjectService` any more — it read the Core Data
copy it last wrote — so board columns changed elsewhere never arrived; it reads the core's
projects now, which every sync pass refreshes. The Swift live-stream client also posted
`externalSyncRefresh` (a GitHub webhook) and `featureFlagsUpdated`; `AppCore` forwards the core's
`needsSync` and `settings` changes to the same places. And a smart-task setting changed offline
was pushed once, failed, and was then overwritten by the next fetch; it is journalled now.

## After the cut-over: the first assessment (2026-09-28)

A review of the moved data layer, against the web as canonical, found the cut-over had carried
some bugs over and made a few new ones. All fixed with tests — in astrid-core unless marked Swift.
Most of them hit Windows too.

**Offline and sessions**
- **A write made offline was dead-lettered four minutes in.** A transport error used an attempt
  like a 500 did. No network is now `Offline`: parked, attempts untouched, woken by
  `networkRestored` (Swift calls it on network return, sign-in and wake).
- **A lapsed session dead-lettered every queued write** (a 401 is a 4xx). It waits for a session.
- **The scheduler could spin, and reorder a lane**: `runnable` and `next_wakeup` disagreed about
  what could run. One rule now — the oldest entry of each lane, never a write naming a temp id
  still to be produced — and one drain at a time.
- **Refused writes can come back**: `retryDeadLetters` revives the last seven days, not deletes.
- Swift: **signing in from offline-only mode made everything twice** — the local tasks and lists
  were re-created through the API client while the same creates sat in the journal. The journal
  sends them; the placeholder `local_` assignee is left off the create and the task assigned to
  the account with an edit queued behind it.
- Swift: **`CoreUpgrade` marked itself done after a partial import**; an entry it could not carry
  was lost. It is done only when every entry went, re-imports are deduplicated by
  `clientRequestId`, and an upload whose comment is gone is dropped.

**Sign-out**
- **A pass in flight at sign-out wrote the departing account's rows into the cleared cache.** A
  session gate: sign-out stops new passes, waits (bounded) for running ones, moves the stream's
  epoch on, then wipes — the attachment cache included — and reopens.
- The credential is deleted before the cache, so nothing in between can sign a request with it.

**The live stream**
- **Task and list events are references**, a lean projection beside the id. Applied as the row it
  wiped the assignee, repeat and lists; the core fetches the row. A refused fetch is a deletion —
  how removal from a list arrives now. `task_deleted` / `list_deleted` are read by the web's field
  names, `list_member_*` events are handled, and an agent's reply preview fetches the thread.
- **Frames are cut as bytes** (the Swift `SSEFrameBuffer`, ported with its tests): a character
  split across two reads was garbled.
- Swift: the stream coming back runs one `sync`; the stream going down clears "agent is typing".

**Sync**
- **A pass pruned tasks it merely failed to read.** A task missing from a pass is fetched before it
  is dropped (≤ 50 a pass); a pass that skipped an unreadable row prunes nothing. Lists honour the
  server's `deletedIds`; a list's `defaultDueTime` survives; a queued edit is applied over the
  server's copy of its list.

**Wire shapes that did not match the web**
- A manual reorder sent the whole task; it patches the order. A reminder snoozed here is not undone
  by the PUT's answer. An invitation already sent is done, not dead. Uploads carry their
  `clientRequestId`. Comments carry `createdAt`. Agent saves are `PUT`, deletes carry a body. The
  GitHub repo list is `repos`. User search carries the task and lists it is for.
- Member changes and blockers on a list or task made offline resolve the temp id, or queue.
- Chat: forgetting an unsent message withdraws only what is still pending; a channel the account
  cannot open (403–405) is no channel, not an error.

**Apple bindings (`core/astrid-apple`)**
- `runBlocking` answers only commands that read or write the cache — a network command there froze
  the main thread — and a panic in the core answers as a failure instead of taking the app down.
- The core's reminder loop is not started: UserNotifications schedules Apple's reminders.

**Swift, besides**
- Reminder settings had a second queue of their own that retried only on a network notification,
  and could not turn quiet hours off (a `nil` was left out of the body). They are journaled, with
  `null` for off. My Tasks filters go through the core.
- A comment the core refused left a row on screen that existed nowhere; it is taken back and the
  text returned.
- A data-isolation failure cleared the arrays but not the core's cache, so the next read brought
  the rows back.
- Dead Swift paths removed: 16 `AstridAPIClient` methods (two extension files among them), the Swift
  temp-id map, the no-op auto-sync timer, and service methods nothing called.

## Data-layer gaps in the core

What the core must grow before the rest of the Swift data layer can go. Done since the mapping:
the platform header, change events, chat, members and invitations (queued offline), boards,
blockers, the upgrade seed, completion and creation carrying what the Swift calls sent, reminder
settings. A first launch after the upgrade that is offline has no chat channels or messages until
it is online once: the upgrade seeds tasks, lists and comments, not chat.
Still to do:
shortcode resolve, AI assistant settings and available agents (the core has them; the Swift chat
service still asks the API client), attachment delete and replace, `updateCustomAgent`, the
Copilot cloud-agent token, contacts upload / search / recommended, app-version check, local (no
account) mode as a core concept, a client-side GitHub sync pass, and a read that returns every
cached task in the wire shape (the Swift views filter `[Task]` themselves today).

## Google Tasks sync: on the core

Since AITD-463 the Google pass is the core's `syncExternal`, the same pass Windows runs. It covers
auto-link, every linked list, and My Tasks against Google's default list. astrid-core 126596f
(AWTD2-56) brought it to parity with the Swift pass: dual watermarks, same-title adoption that
skips deleted and tombstoned items (D39), absence deletion, drift repair and completed backfill.
The cases the retired Swift D39 guard (`GooglePushTwin.find`, AITD-462) was tested for are core
tests now (astrid-core 0be2e3a, `aitd463_*`): a tombstoned item, deleted and linked items passed
over for the live unlinked one, and the My Tasks push.
`GoogleTasksSyncService` keeps what is about the account: connect, links, mode (`setGoogleSyncMode`)
and when a pass runs (debounce, floor, the `LocalMutation` nudge). The Swift engine is deleted.

The deletion ledger is the core's as well. Its `deleteTask` records a mirrored task's twin itself.
`GoogleLedgerUpgrade` runs once on the first launch after the switch. It moves the Swift
`SyncDeletionLedger("google")` (pending deletions, local and server tombstones) and the
`googleTaskLinkCache` into the core's ledger through `importExternalLedger`, so a deletion queued
before the update still reaches Google. Every Google pass waits for it. The import is local, so it
works offline. It is marked done only when the core accepts it; a failure leaves the Swift keys for
the next launch. On success the Swift keys are removed, because the core merges an import and a
stale copy imported again would put back links the core has moved past. Sign-out clears the done
flag with the other per-user sync keys (`SyncStateReset`). Excluded tasklists need no import: the
core reads them from the integration's metadata on the server. The first pass re-sent each linked task once, because the
old links carry no agreement timestamps.

The Apple bindings still do not start the core's `external_loop`: the Swift service decides when a
pass runs, so there is never a second one.

GitHub is different. The server runs a cron every 15 minutes; the Swift client pass pushes 2s after
an edit. Dropping the client pass would delay edits reaching GitHub by up to 15 minutes, so it
stays until that is decided.
