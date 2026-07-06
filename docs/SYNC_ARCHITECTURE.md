# External Sync Architecture

How Astrid iOS mirrors content with Apple Reminders, Google Tasks, and GitHub
Issues. Astrid's server stays the source of truth for task *content*; external
providers are mirrors.

## Orchestration (there is no central coordinator)

Each provider worker (`Core/Sync/GoogleTasksSyncService`,
`GitHubSyncService`, and `Core/Services/AppleRemindersService`) self-schedules a
debounced pass off two triggers:

- **`.externalSyncRefresh`** — a server SSE nudge (GitHub webhook → SSE).
- **`OutboxManager.didEnqueueMutation`** — any local write, so pushes don't wait
  for foreground/refresh.

> Name clash: `Core/Services/SyncManager` is unrelated — it's the Astrid-backend
> 60s pull, not an external-sync coordinator.

## My Tasks ↔ Google default list

Unlisted tasks assigned to the current user mirror against Google's default
tasklist. Only active in the all-lists modes.

- `GoogleSyncAPI` exposes the default list's real id via `tasklists.defaultId`
  (the `@default` alias resolved server-side).
- `GoogleAutoLink.myTasksPhaseActive(...)` gates the phase; it's skipped when a
  legacy setup already list-linked the default tasklist, and the default
  tasklist is excluded from list auto-linking.
- `GoogleTasksSyncService.syncMyTasks(tasklistId:)` runs the full pipeline in
  "direct" mode (no `ExternalListLink` row → always a full pull, per-item
  watermarks) against `pullGoogleTasksDirect` / the `tasklistId` push variant.

## Deletion ledgers & tombstones (`SyncDeletionLedger`)

Per-provider UserDefaults ledgers, captured **at delete time** (before the
server link row cascades away):

- `pending` (remoteId → containerId): remote deletions to execute next pass.
- Local tombstones (cap 500, oldest-first eviction) + a **separate**
  server-tombstone store (cap 5000), UNIONed in `tombstonedRemoteIds`. The
  separation stops a large server-tombstone merge from evicting this device's
  own tombstones (which would let a deleted task resurrect via backfill — a
  GitHub twin is only *closed*, not deleted). Server tombstones merge in via
  `mergeServerTombstones` on `refreshStatus`.

## Client-acknowledged cursor

Incremental pulls send `deferCursor=1`: the server returns the next cursor but
does **not** persist it on GET. The client commits it (`commitGoogleCursor` /
`commitGitHubCursor`) only after a fully-applied pass, so a kill mid-pass
re-pulls the window (idempotent via dual watermarks) instead of skipping remote
edits. Backward-compatible — omitting the param restores GET-time advance.

## Born-completed backfill

Completed history imports (20/pass) are created **born completed + backdated**
via `TaskService.createTask(..., presumeCompletedAt:)`, so the optimistic row
never flashes as an open task and the recently-completed window (keyed on
`completedAt`) keeps history hidden.

## Sign-out reset contract

`SyncStateReset.userDefaultsKeys` (in `Core/Sync/SyncDeletionPolicy.swift`) +
`AuthManager` sign-out wipe every per-user sync key so nothing leaks to the next
account on a shared device. **Rule:** any NEW persisted sync key must be added
to `SyncStateReset` (locked by `SyncStateResetTests`).

## Pure, tested planners

Decision logic is extracted and unit-tested: `SyncSuppression`,
`GoogleDueMapping`, `SyncPullOrdering`, `GoogleAutoLink`, `CommentSyncPlanner`,
`SyncDeletionPolicy` / `SyncDeletionLedger`, `CompletionDriftPolicy`,
`CompletedBackfill`, `SyncContainerGuard`, `AppleExportPlanner`, `RFC3339`.
