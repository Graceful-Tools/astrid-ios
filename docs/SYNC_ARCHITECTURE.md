# External Sync Architecture

How Astrid iOS mirrors content with Apple Reminders, Google Tasks, and GitHub
Issues. Astrid's server stays the source of truth for task *content*; external
providers are mirrors.

## Orchestration (there is no central coordinator)

Each provider worker (`Core/Sync/GoogleTasksSyncService`,
`GitHubSyncService`, and `Core/Services/AppleRemindersService`) self-schedules a
debounced pass off two triggers:

- **`.externalSyncRefresh`** — a server nudge (GitHub webhook → the live stream). astrid-core
  reports it as a `needsSync` change and `AppCore` posts the notification.
- **`LocalMutation.didHappen`** — every write `TaskService` / `ListService` makes, tagged with its
  sync source, so pushes don't wait for foreground/refresh and a provider ignores its own writes.

> Name clash: `Core/Services/SyncManager` is unrelated — it asks astrid-core for an Astrid-backend
> pass, not an external-sync coordinator. astrid-core's own external-sync loop is **not** started
> on Apple, so there is never a second pass (see `docs/CORE_MIGRATION.md`, Google Tasks sync).

**Google's pass is astrid-core's** (`syncExternal`, AITD-463). `GoogleTasksSyncService` only
schedules it and owns the connection, links and mode. The rest of this file describes the Swift
passes that remain: GitHub and Apple Reminders.

## Deletion ledgers & tombstones (`SyncDeletionLedger`)

Per-provider UserDefaults ledgers (GitHub; Google's is the core's), captured **at delete time** (before the
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
does **not** persist it on GET. The client commits it (`commitGitHubCursor`) only after a fully-applied pass, so a kill mid-pass
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
`SyncPullOrdering`, `CommentSyncPlanner`,
`SyncDeletionPolicy` / `SyncDeletionLedger`, `CompletionDriftPolicy`,
`CompletedBackfill`, `SyncContainerGuard`, `AppleExportPlanner`, `RFC3339`.
