# Local-First Architecture

*Owns the Outbox mechanism and the cache-invalidation rules. Rules and control points are in `ASTRID.md`; external sync is in `SYNC_ARCHITECTURE.md`.*

## The model in one paragraph

Every user action is applied to astrid-core's SQLite cache and journaled as a write; the core's Outbox replays it against the server with backoff, idempotency, lanes and
dependency ordering. Reads come from the cache; a sync pass and the live stream merge the server's
rows on top, guarded so neither undoes a newer local edit or brings back a local deletion. The
Swift services are faces over `CoreSession` (`AppCore.shared.session`): they send commands and
redraw their `@Published` state when the core reports a change. It is the same engine the Windows
app runs — see `docs/CORE_MIGRATION.md` for the move and astrid-core's own `docs/` for the
journal's internals.

## The Outbox (astrid-core `outbox/`)

The journal is the **only** client write path for tasks, lists, comments, chat, attachments,
members, blockers and settings. A Swift service never calls `AstridAPIClient` for any of those.

| Piece | Role |
|---|---|
| `journal` | Durable entries in the cache: kind, payload, `clientRequestId` (the server's idempotency key), attempts, next attempt, the temp id an entry produces |
| `scheduler` | What may run now: the oldest entry of each lane (`serialization_key` — one lane per task, list, comment…), and never a write that names a temp id an older entry has yet to produce |
| `runner` | Drains what the scheduler allows, one drain at a time, inside the session (below) |
| `handlers` | One per kind: the request, then the cache reconciled (temp → real id, mapping kept for queued edits) |

What each outcome means:

- **Done** — the entry goes; anything it produced (a real id) is recorded for the entries after it.
- **Offline** — no network, or no session (a 401). The entry is parked for 30 s *without* using an
  attempt, and is woken at once by `networkRestored`. Before 2026-09-28 both burned attempts, so a
  write made on a plane was dead-lettered four minutes in, and a lapsed session dead-lettered
  every queued write.
- **Retry** — the server failed (5xx, an unreadable answer): exponential backoff, then dead.
- **Dead** — refused for good (4xx). Dead letters are kept; `retryDeadLetters` revives the last
  seven days' worth, except deletes, and nudges delivery. `outboxStats` names the newest few and
  why.

When the Swift side calls in:

- `AppCore.networkRestored()` — on `.networkDidBecomeAvailable`, on sign-in and session start, and
  on wake (Mac). Wakes parked writes, drains, and restarts the live stream.
- The stream coming back up runs one `sync`: whatever happened while it was down reached nobody.
- `drain` — pull-to-refresh / "Sync now" (`SyncManager.performQuickSync`).

**Sign-out** closes the core's session gate first: nothing new starts, a sync pass, drain or
stream frame already in flight is waited for (bounded), and only then are the cache, the journal,
the attachment cache and the credential wiped. Without it a pass that was mid-flight wrote the
departing account's rows into the cache the next person saw.

### Adding a new write operation

1. Add the kind, its handler and its lane in astrid-core, with a test there. Mirror the web's
   wire shape — the web is canonical.
2. Add a `Command` for it and dispatch it; answer with the optimistic row.
3. In Swift, add a method on the service that runs the command (`core.run(CoreCommand(...))`).
   Views call the service; nothing calls `AstridAPIClient` for it.
4. Rebuild the framework (`scripts/core/build-xcframework.sh --core ../astrid-core`), and pin the
   core revision when it ships.
5. Any new per-user key Swift persists goes into `SyncStateReset.userDefaultsKeys` in the same
   change (`SyncStateResetTests`).

### What is deliberately not queued

- **My Tasks filters** (`setMyTasksFilters`): a filter replayed a week later would move a screen
  under whoever is looking at it. It is remembered locally and sent once.
- **Membership changes and blockers** are sent at once so a refusal ("no such person", "that would
  be a cycle") is shown; only a failed network queues them (CONTRACTS D31, D32).

### Upgrading from the Swift layer (`CoreUpgrade`)

On the first launch of a core build, Core Data seeds the core's cache and every entry left in the
Swift `outbox.json` (and Core Data's pending member rows) is imported into the core's journal,
deduplicated by `clientRequestId`. The upgrade is marked done only when every entry was carried
over; one that could not be is kept for the next launch, and an upload whose comment is gone is
dropped rather than sent.

## Reads and merges

- The cache is the read. A full pass replaces what moved and forgets what the server no longer
  has — except unsent rows, rows that moved after the pass began, and (for tasks) anything it
  cannot confirm gone: a task missing from a pass is fetched on its own before it is dropped, up to
  50 a pass, and nothing is pruned from a pass that skipped a row it could not read.
- **Deletions made here stay deleted**: neither a pass nor the stream brings back a row whose
  delete is queued or just landed.
- **The live stream carries references, not rows.** A task or list event is the id beside a lean
  projection; the core fetches the row and applies that (403/404/410 → it is gone — how this
  account learns it was removed from a list). An agent's reply arrives as a preview; the thread is
  fetched. Frames are cut as bytes, so a character split across reads is not garbled.
- **Pending edits win.** A server row that arrives while an edit to it is still queued has the
  edit applied over it.
- **Dedup**: the server's copy of a row made here replaces the temporary one by `clientRequestId`.

## External sync providers (`Astrid App/Core/Sync/`)

Apple Reminders, Google Tasks and GitHub Issues mirror content through the same canonical
service layer. Every write goes in via `TaskService` (`completeTask` for completions, with
`completedAt` / `completedSource` so imported history is backdated rather than flashing as
open). Provider workers wake on `.externalSyncRefresh` (the core's `needsSync` change, from a
server webhook) and `LocalMutation.didHappen` (every service write), plus foreground, pull-to-refresh and
"Sync now". Planners, ledgers, cursors and the sign-out reset contract are in
[SYNC_ARCHITECTURE.md](./SYNC_ARCHITECTURE.md).

## Caching: what fills each cache, and what clears it

Written for task 266f816e. The caches are deliberate — the brief asks for caching
on the clients and explicitly does not want performance compromised. What was
missing is the *invalidation* rules, which are the part that rots silently: a
wrong one is invisible until a user sees stale data.

### `TaskService.cachedTasks` / `.tasks`, `ListService.lists`

| | |
|---|---|
| what it is | the core's cache, read into `[String: Task]` / `[TaskList]` for the views to bind to |
| filled by | `reload` after every core change (`CoreChange.task` / `.list` / `.synced` / `.delivered`) and every write the service makes. `AppCore.audiences(for:)` decides which services hear a change: a delivered write names the rows it touched, so only those rows are read again (AITD-454). Only a change the core cannot describe reaches every service |
| cleared by | sign-out (the core wipes its cache; the services clear theirs), and a failed data-isolation check in `SyncManager`, which also runs the core's `clearCache` so the next read cannot bring the rows straight back |
| NOT cleared by | switching lists, backgrounding, or a sync pass |

What a pass forgets, and what it keeps, is decided in the core — see "Reads and merges" above.
The Swift arrays never prune on their own; a row leaves them when it leaves the core's cache.

### `ImageCache` (memory + disk)

| | |
|---|---|
| memory | `NSCache`, 100 images / 50 MB, keyed by absolute URL |
| disk | `~/Library/Caches/ListImageCache`, filename = the URL with `/` and `:` replaced |
| cleared by | `clearCache()` on sign-out; `clearSecureFilesCache()` after a list-image change in `ListAdminTab` |

Two things to know:

- The cache is keyed by URL, so a *new* image at a *new* URL is never stale. The
  failure mode is the opposite one: the same URL with different bytes, which is
  why `clearSecureFilesCache()` exists for uploads.
- `clearMemoryCache()` runs when the app becomes active (`AstridApp`), so a
  foreground re-reads images from disk or the server rather than serving a stale
  in-memory copy for the whole session.

### `ProfileCache`, `UserImageCache`

Sign-out only. Both are read-through with no invalidation of individual entries,
so a user who changes their avatar is reflected only after the URL changes or the
app is reinstalled — acceptable because the avatar URL is content-addressed, but
worth knowing before assuming a stale avatar is a rendering bug.
