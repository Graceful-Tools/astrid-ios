# Local-First Architecture

*Owns the Outbox mechanism and the cache-invalidation rules. Rules and control points are in `ASTRID.md`; external sync is in `SYNC_ARCHITECTURE.md`.*

## The model in one paragraph

Every user action applies **optimistically** to in-memory state and CoreData first, then journals a write through the **unified Outbox**, which replays it against the server with retry/backoff, idempotency, and dependency ordering. Reads are cache-first (CoreData seeds memory; server fetches merge on top with deletion/dedup guards). External providers (Apple Reminders, Google Tasks, GitHub Issues) mirror content through the same canonical service layer.

## The unified Outbox (`Astrid App/Core/Outbox/`)

The Outbox is the **only** client write path for tasks, comments, chat sends, and attachment uploads.

| Piece | Role |
|---|---|
| `OutboxEntry` | One journaled write: kind, JSON payload, `clientRequestId` (server idempotency key), `attempts` + `nextAttemptAt` backoff, `dependsOn` edges, `result` output |
| `OutboxStore` | Durable journal (`Application Support/outbox.json`) — survives relaunch |
| `OutboxRunner` | Drains runnable entries; schedules retries; dead-letters on permanent errors |
| `OutboxManager` | Enqueue API + `drain()` (pull-to-refresh / "sync now" / reconnect entry point) |
| Per-kind handlers | Perform the server call and reconcile local state (temp→real id swaps, mark synced) |

**Kinds (9):** `createTask`, `updateTask`, `deleteTask`, `createComment`, `updateComment`, `deleteComment`, `sendChatMessage`, `uploadAttachment`, `updateList`.

Key behaviors:
- **Idempotency**: every entry carries a `clientRequestId`; the server dedupes, so retries can't double-create.
- **Dependency chains**: a comment/chat message with a staged attachment gets a `dependsOn` edge on its `uploadAttachment` entry and reads the real fileId from the dependency's `result`. A dependency's permanent failure propagates to dependents.
- **`.blocked` vs `.retryable`**: waits on local state (e.g., a temp task id not yet resolved) return `.blocked` and don't burn attempts.
- **Dead letters** are never pruned; Settings → Outbox shows kind + lastError for any dropped write.
- **Mutation nudge**: every enqueue posts `OutboxManager.didEnqueueMutation`, which the external sync providers observe (debounced) so edits push out within seconds.
- **Sign-out wipes the journal** (`clearAllForSignOut`) — queued writes belong to the departing user.

### Adding a new write operation

1. Define a payload struct + kind string; register a handler with `OutboxManager`.
2. In the service: apply optimistically (memory + CoreData `syncStatus: "pending"`), then `enqueue`.
3. Handler: perform the server call with the entry's `clientRequestId`, then call the service's `reconcileOutbox*` helper (temp→real swap, mark `synced`).
4. Never give views direct `AstridAPIClient` access — the service layer is the canonical control point (see CLAUDE.md).
5. If the operation adds any new per-user persisted sync key, add it to `SyncStateReset.userDefaultsKeys` in the same change and cover it in `SyncStateResetTests`.

### Still on the legacy per-service pattern

`ListService.syncPendingLists` (list **creates** only), `ListMemberService.syncPendingOperations`, and chat **deletes** (`ChatService.syncPendingMessages` delete branch) — these have no Outbox kinds yet. `TaskService.syncPendingOperations` and `CommentService.syncPendingComments` still exist but are thin wrappers over `OutboxManager.drain()`.

**Lists are split on purpose (AITD-410).** List *updates* are an Outbox kind (`updateList`); list *creates* are still the legacy sweep. Updates were the silent-data-loss case: `updateListAdvanced` swallowed the failure, logged "will sync when online", and nothing retried it — `CDTaskList.update(from:)` never marks the row pending, so the sweep's `syncStatus` predicate could not see it, and the next `fetchLists()` reverted the change. Creates already replayed (network-restore observer + 60s timer); their bug was that a failed attempt wrote `syncStatus = "failed"` while the predicate selected only `"pending"`, so one lost attempt stranded the list forever. `ListSyncStatus.unsynced` now owns that selection.

Two things to know before extending this:

- The update payload is journaled as **JSON text, not a typed struct**. `updateListAdvanced` takes `[String: Any]` because `NSNull()` ("clear this field") has to stay distinct from an absent key ("leave it alone") — see `ListSettingsPayload`. A `Codable` struct of optionals cannot express that difference.
- `updateList` has its own **serialization lane** (`list:<id>`) in `OutboxScheduler.serializationKey`. Without one the default is `entry:<id>`, and two queued updates to the same list can run concurrently and land out of order — the user's last edit silently replaced by the one before it.

## Reads and merges

- CoreData seeds memory at launch; server fetches merge via `TaskService.mergeAndSortTasksInBackground` (timestamp-based: newer local wins).
- **Deletion guard**: `recentlyDeletedTaskIds` (ordered, capped at 500, oldest-first eviction) filters every merge and is **retained after the server confirms the delete** — a fetch that started before the delete can still deliver the task after it. Cleared only on sign-out.
- Dedup: `clientRequestId` matching prevents a pending create and its server echo from coexisting.

## External sync providers (`Astrid App/Core/Sync/`)

Apple Reminders, Google Tasks and GitHub Issues mirror content through the same canonical
service layer. Every write goes in via `TaskService` (`completeTask` for completions, with
`completedAt` / `completedSource` so imported history is backdated rather than flashing as
open). Provider workers wake on `.externalSyncRefresh` (server SSE nudge) and
`OutboxManager.didEnqueueMutation` (local write nudge), plus foreground, pull-to-refresh and
"Sync now". Planners, ledgers, cursors and the sign-out reset contract are in
[SYNC_ARCHITECTURE.md](./SYNC_ARCHITECTURE.md).

## Caching: what fills each cache, and what clears it

Written for task 266f816e. The caches are deliberate — the brief asks for caching
on the clients and explicitly does not want performance compromised. What was
missing is the *invalidation* rules, which are the part that rots silently: a
wrong one is invisible until a user sees stale data.

### `TaskService.cachedTasks` / `.tasks`

| | |
|---|---|
| what it is | `[String: Task]` by id, plus the published array the UI binds to |
| filled by | the initial Core Data load, every fetch, and every optimistic write |
| cleared by | **only** `clearCache()` — sign-out (`AuthManager`) and a failed sync validation (`SyncManager`) |
| NOT cleared by | switching lists, backgrounding, or a normal sync pass |

A sync pass *replaces* entries rather than clearing the dictionary, so a task the
server no longer returns stays in memory until a full clear. That is intentional
for offline (a task created offline must survive a pass that cannot see it yet),
and it is the same shape that let lists deleted on web reappear until
`SyncOrphanPrune` was added — the equivalent prune for tasks does not exist.

### `ListService.cachedLists` / `.lists`

Same shape and the same two clear points. `SyncOrphanPrune` handles the
server-deleted case for lists specifically: a cached list that the server no
longer returns is dropped, but only when it is `synced` or `pending_delete` and
not a `temp_` local id, so an offline-created list is never pruned before it
syncs.

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
- `clearMemoryCache()` documents itself as "call this when app becomes active to
  refresh images from server" and **is never called** from anywhere. Either the
  foreground refresh it describes should be wired up, or the method should go —
  right now it reads as a behaviour the app has and does not.

### `ProfileCache`, `UserImageCache`

Sign-out only. Both are read-through with no invalidation of individual entries,
so a user who changes their avatar is reflected only after the URL changes or the
app is reinstalled — acceptable because the avatar URL is content-addressed, but
worth knowing before assuming a stale avatar is a rendering bug.
