# Local-First Architecture

*Last updated: July 4, 2026 — reflects the unified Outbox (legacy per-service sync removed) and the external sync providers.*

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

**Kinds (8):** `createTask`, `updateTask`, `deleteTask`, `createComment`, `updateComment`, `deleteComment`, `sendChatMessage`, `uploadAttachment`.

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

### Still on the legacy per-service pattern

`ListService.syncPendingLists`, `ListMemberService.syncPendingOperations`, and chat **deletes** (`ChatService.syncPendingMessages` delete branch) — these have no Outbox kinds yet. `TaskService.syncPendingOperations` and `CommentService.syncPendingComments` still exist but are thin wrappers over `OutboxManager.drain()`.

## Reads and merges

- CoreData seeds memory at launch; server fetches merge via `TaskService.mergeAndSortTasksInBackground` (timestamp-based: newer local wins).
- **Deletion guard**: `recentlyDeletedTaskIds` (ordered, capped at 500, oldest-first eviction) filters every merge and is **retained after the server confirms the delete** — a fetch that started before the delete can still deliver the task after it. Cleared only on sign-out.
- Dedup: `clientRequestId` matching prevents a pending create and its server echo from coexisting.

## External sync providers (`Astrid App/Core/Sync/`)

Client-side sync workers mirror content between Astrid (source of truth) and Apple Reminders / Google Tasks / GitHub Issues. Server stores links + tokens and proxies provider APIs (`astrid-web /api/v1/sync/*`); a GitHub webhook emits an SSE `external_sync_refresh` nudge.

Pure, unit-tested planners drive every decision:

| Planner | Rule |
|---|---|
| `SyncSuppression` | Dual watermarks (echo suppression both directions), `pullWatermark` (task's own stamp, never wall-clock), `remoteWins` (last-write-wins on pull-apply) |
| `GoogleDueMapping` | Date-only due mapping: never clobber a timed local due; all-day = UTC day, timed = local day |
| `SyncPullOrdering` | Parents before children (sub-issues/subtasks) with cycle safety |
| `GoogleAutoLink` | Auto-link modes: manual / all-Google→Astrid (suffix) / all-Astrid→Google / bidirectional; adopt-by-name, never duplicate |
| `CommentSyncPlanner` | GitHub comment create/edit/delete both ways; directional entries decide which side is canonical |
| `SyncDeletionPolicy` | Remote deletes are **tombstone-driven** (captured at delete time — link rows cascade away); local deletes require a **complete remote listing** (failed/truncated fetch never mass-deletes) |
| `CompletionDriftPolicy` | Completion disagreement repair: remote-completed adopts when local never completed or is untouched; un-complete only when untouched |
| `CompletedBackfill` | Completed history imports last, newest-first, budgeted (20/pass) — never delays live items; backdated via `completedAt` |
| `RFC3339` | Fractional-second-tolerant timestamp parsing (Google emits `.000Z`) |

Sync triggers: app foreground, SSE nudge, Outbox mutation nudge, pull-to-refresh, Sync now. Google sync mode + exclusions + tombstones persist server-side in `Integration.metadata` (cross-device); per-device ledgers (`SyncDeletionLedger`) are wiped on sign-out via `SyncStateReset`.

## Completion metadata

Tasks carry `completedAt` (real completion time — backdatable by sync to the provider's timestamp) and `completedSource` (`astrid|google|github|apple`). The recently-completed window prefers `completedAt` over `updatedAt`, so imported history ages correctly.
