# Astrid iOS — Single Source of Truth for AI Agents

*Read by **every** AI agent (Claude Code, Codex, and others) working in this repo.*

This file owns **all** architecture, control points, and cross-platform contracts.
[CLAUDE.md](./CLAUDE.md) (Claude Code) and [AGENTS.md](./AGENTS.md) (Codex) are thin
operational adapters — they hold commands and workflow, and they point here for
everything else. **When architecture changes, change it HERE and nowhere else.**
Duplicating architecture into the adapters is how this repo drifted before.

**Read this file before you touch code that involves:** tasks, task completion,
repeating tasks, the Outbox, external sync, chat, list members, or any API call.

---

## 0. Non-negotiable rules

Violating any of these has caused a shipped regression. If you read nothing else, read this.

1. **All backend writes go through the service layer.** Never call `AstridAPIClient`
   directly from a view, timer, notification handler, or sync worker. If a service
   lacks the method you need, add it to the service first. (See §2.)
2. **Complete a task ONLY via `TaskService.completeTask(...)`.** Never
   `updateTask(completed: true)` — that path skips repeat rollover. (See §4.)
3. **When completing from a view that lets the user edit fields first**, copy the
   edited fields (`dueDateTime`, `isAllDay`, `repeating`, `repeatingData`, `repeatFrom`)
   into the `task:` argument before calling `completeTask`, so rollover anchors on
   what the user sees, not stale cache. (See §2, §4.)
4. **Next-occurrence math lives ONLY in `RepeatingTaskCalculator`.** Never inline
   pattern math anywhere else. Mirror any change into `astrid-web/types/repeating.ts`. (See §4.)
5. **Preserve offline behavior.** Writes journal through the Outbox; local-first
   caching and dedup must keep working. Don't bypass the Outbox. (See §3.)
6. **All API paths are versioned `/api/v1/...`.** There are no `/api/user/...` or
   `/api/chat/...` paths in this app — those are dead. (See §7 for the list.)
7. **TDD for bug fixes:** write a RED regression test naming the task id, watch it
   fail, then make it green. Run `npm run predeploy` before declaring a task done.
8. **For breaking API changes, add a new app/API version** — keep the existing
   version working. Never break the deployed contract.

---

## 1. Agent Working Agreements

Distilled from recurring friction. Applies to every agent.

- **TDD, minimal change.** RED test first, then implement to green. Prefer the
  smallest behavior-preserving change; over-eager "clean" rewrites have broken
  existing tests. All tests pass before a task is complete.
- **Task tooling:** when filing/updating Astrid tasks via the `astrid-web` scripts,
  use the **`listIds`** array field (not `listId`), and confirm **list ID vs task ID**
  before closing a task — the wrong field orphans tasks and causes `400`s on comment
  posts. The iOS To-do list id is `aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`.
- **Communication:** lead with the outcome, then detail. Keep turns short during
  long builds/multi-file work — overlong turns have truncated sessions.
- **Per-task process** (canonical, cross-repo): post a strategy comment → RED-GREEN-refactor
  TDD with a task-id-linked regression test → run quality gates → post a completion
  report → then mark complete. Full flow: `astrid-web/ASTRID_WORKFLOW.md`.

---

## 2. Canonical Control Points (the service layer)

Every write to a backend-backed resource flows through a service. The service layer
is where optimistic updates, the offline Outbox, the CoreData cache, and dedup live,
and it's where iOS stays aligned with the web's logic contract.

**Rule of thumb:** if a service lacks the method you need, add it there first. A one-off
direct `AstridAPIClient` call from a view is exactly how we shipped the weekly-M/W/F
completion regression, the on-device-AI-skips-rollover bug, and the offline-member-mutation
loss bug.

| Domain | Canonical service | Entry point(s) | Notes |
|--------|-------------------|----------------|-------|
| Tasks (CRUD) | `TaskService` | `createTask`, `updateTask`, `deleteTask`, `copyTask` | Writes journal through the unified Outbox; CDTask is the cache/reconcile store. |
| Task completion (incl. repeat rollover) | `TaskService.completeTask` | See §4 for all entry points. | MUST go through this — never `updateTask(completed: true)`. |
| Lists | `ListService` | `createList`, `updateList`, `deleteList`, `toggleFavorite`, `fetchLists` | Lists/members are still legacy (no Outbox kinds yet). |
| List members (add / role / remove) | `ListMemberService` | `addMember`, `updateMemberRole`, `removeMember`, `cancelInvitation` | Offline queue via CDMember. |
| Comments | `CommentService` | `createComment`, `updateComment`, `deleteComment` | Outbox-backed (create/update/delete kinds). |
| Chat | `ChatService` | `sendMessage`, `getAIAssistantSettings`, `postAgentResponse` | AI-assistant helpers cached (60s TTL). |
| Attachments | `AttachmentService` | `saveLocallyAndUploadAsync`, … | |
| User smart-task settings | `UserSettingsService` ↔ `AstridAPIClient.getSmartTaskSettings` / `updateSmartTaskSettings` | `/api/v1/users/me/settings` | UserDefaults-first, 300ms debounce to server. |
| My Tasks preferences | `MyTasksPreferencesService` ↔ `AstridAPIClient.getMyTasksPreferences` / `updateMyTasksPreferences` | `/api/v1/users/me/my-tasks-preferences` | UserDefaults-first, 300ms debounce to server. |
| Reminder/notification completion | `ReminderPresenter` → `TaskService.completeTask(task:)` | Pass `task:` so rollover doesn't depend on cache state. |
| Apple Reminders sync | `AppleRemindersService` → `TaskService.completeTask(task:)` | |
| On-device AI complete action | `AppleFoundationModelService` → `TaskService.completeTask` | Must NOT use `updateTask(completed: true)`. |

`TaskService.completeTask` signature:
`completeTask(id:completed:task:timerDuration:lastTimerValue:source:completedAt:)`.

**Detail-view-style callers** (any view where the user edits fields before confirming
completion/submit/save): propagate ALL edited fields — at minimum `dueDateTime`,
`isAllDay`, `repeating`, `repeatingData`, `repeatFrom` — into the `task:` argument
before calling `completeTask` / `updateTask`. Otherwise rollover anchors on stale values.

**Alignment with web:** the service layer is the boundary that keeps iOS aligned with
the reference implementation in `astrid-web`. When you add a field to a request/response
on one platform, mirror it on the other. `CanonicalControlPointsTests` locks down the
JSON wire shape of shared types (`MyTasksPreferences`, `UserSettings`) so silent drift
fails a unit test instead of shipping.

---

## 3. Unified Outbox (the only write path)

All backend writes for **tasks, comments, chat sends, and attachment uploads** journal
through `Astrid App/Core/Outbox/` (journal + runner + per-kind handlers). Eight kinds:
`createTask`, `updateTask`, `deleteTask`, `createComment`, `updateComment`,
`deleteComment`, `sendChatMessage`, `uploadAttachment`.

- Entries carry a `clientRequestId` (server-side idempotency), retry with backoff, and
  dead-letter on permanent errors (surfaced in Settings → Outbox).
- `dependsOn` chains sequence dependent work (upload → comment/send).
- Local-state waits return `.blocked` (no attempt burn).
- CDTask/CDChatMessage remain the cache/reconcile store; the Outbox is the write journal.
- Lists/ListMembers and chat *deletes* remain legacy (no Outbox kinds yet).
- Sign-out wipes the journal.

Details: `docs/LOCAL_FIRST_PATTERN.md`.

---

## 4. Repeating Tasks

**Single source of truth for next-occurrence math:**
`Astrid App/Utilities/RepeatingTaskHandler.swift` (`RepeatingTaskCalculator`). Mirrors
`astrid-web/types/repeating.ts` + `astrid-web/lib/repeating-task-handler.ts` and must
stay behavior-compatible.

**Production entry point:** `TaskService.completeTask(...)` → `calculateNextOccurrence`
→ `RepeatingTaskCalculator`. `TaskService.calculateNextOccurrence(for:)` is a **thin
delegator** — do NOT inline pattern math there. A prior inline version ignored
`weekdays`, `monthRepeatType`, `monthWeekday`, and yearly `month`/`day`, breaking
weekly M/W/F rollover.

**Every completion entry point in the app** (keep this list in sync when you add one):

| Caller | File |
|--------|------|
| Task list checkbox | `Views/Tasks/TaskListView.swift` |
| Task detail checkbox | `Views/Tasks/TaskDetailViewNew.swift` (`toggleCompletion`) |
| Timer finished | `Views/Tasks/TaskTimerView.swift` |
| Reminder popup "Done" | `Core/Notifications/ReminderPresenter.swift` |
| Subtask checkbox | `Views/Tasks/SubtasksSectionView.swift` |
| Board card checkbox | `Views/Board/BoardTaskCardView.swift` |
| Apple Reminders two-way sync | `Core/Services/AppleRemindersService.swift` |
| On-device AI "complete" AND "update→completed" actions | `Core/Services/AppleFoundationModelService.swift` (`executeCompleteAction` and `executeUpdateAction`'s `completed` case — never `updateTask(completed:)`) |
| Google Tasks inbound (pull / drift / backfill) | `Core/Sync/GoogleTasksSyncService.swift` |
| GitHub Issues inbound (pull / drift / backfill) | `Core/Sync/GitHubSyncService.swift` |

**When changing pattern logic:**
1. Update `RepeatingTaskCalculator` only.
2. Mirror the change in `astrid-web/types/repeating.ts`.
3. Add tests at BOTH levels:
   - `RepeatingTaskCalculatorTests` / `CustomRepeatingPatternTests` — calculator in isolation.
   - `testTaskService_*` cases in `CustomRepeatingPatternTests` — the production completion
     path, so isolation-only tests don't mask a broken wire-up.
4. Multi-step progression tests (walk 6+ completions) surface bugs single-step tests miss.

**Key files:**

| File | Purpose |
|------|---------|
| `Astrid App/Utilities/RepeatingTaskHandler.swift` | Canonical `RepeatingTaskCalculator` |
| `Astrid App/Core/Services/TaskService.swift` (`calculateNextOccurrence`) | Production entry point — delegates only |
| `Astrid App/Models/Task.swift` (`CustomRepeatingPattern`) | Pattern model; `nonisolated` so Codable round-trips through `CDTask` |
| `Astrid AppTests/Tests/UnitTests/RepeatingTaskCalculatorTests.swift` | Calculator unit tests |
| `Astrid AppTests/Tests/UnitTests/CustomRepeatingPatternTests.swift` | Round-trip + multi-step + TaskService-path tests |

---

## 5. Completion metadata & subtasks

- Tasks carry `completedAt` (real completion time, backdatable by sync) and
  `completedSource` (`astrid|google|github|apple`). The recently-completed window
  prefers `completedAt`; task detail shows "Completed via …" for non-Astrid completions.
- **Subtasks:** `parentTaskId` self-relation (SetNull on parent delete), inherit the
  parent's lists, complete via `TaskService.completeTask` per subtask, display per the
  synced `subtaskDisplay` setting with depth-capped indentation. Map to Google Tasks
  `parent` and GitHub sub-issues 1:1.
- Inbound completion from any provider ALWAYS routes through
  `TaskService.completeTask(task:source:completedAt:)`.

---

## 6. External sync providers

`Astrid App/Core/Sync/` mirrors content two-way with **Apple Reminders, Google Tasks,
and GitHub Issues** (client-side workers; server stores links/tokens and proxies via
`astrid-web /api/v1/sync/*`; GitHub webhook → SSE `external_sync_refresh` nudge).

All decision logic is pure and unit-tested: `SyncSuppression` (dual watermarks +
`remoteWins` last-write-wins), `GoogleDueMapping`, `SyncPullOrdering` (sub-issue/subtask
parents first), `GoogleAutoLink` (modes: manual / all-Google→Astrid with suffix /
all-Astrid→Google / bidirectional; server-side `Integration.metadata`),
`CommentSyncPlanner` (GitHub comments create/edit/delete, directional canonicality),
`SyncDeletionPolicy` + `SyncDeletionLedger` (tombstone-driven remote deletes;
complete-listing-guarded local deletes), `CompletionDriftPolicy`, `CompletedBackfill`
(completed history 20/pass, backdated, never delays live sync), `RFC3339`.

Sign-out resets all provider state (`SyncStateReset`, tested).

Details: `docs/SYNC_ARCHITECTURE.md`.

---

## 7. Chat & Agent Features

Every list (including My Tasks) has a chat channel via the header chat toggle. Chat
supports @mentions (`@[Name](id)`), #list / !task refs (`#[Name](id)`, `![Name](id)`),
file attachments (offline-queued), AI agent responses (@mention Astrid or a configured
agent; server-side `processAstridMessage`), and real-time updates (SSE + 3s polling fallback).

**Key files:**

| File | Purpose |
|------|---------|
| `Views/Chat/ChatPanelView.swift` | Container with channel resolution |
| `Views/Chat/ChatInputView.swift` | Rich input with @/#/! autocomplete + attachments |
| `Views/Chat/ChatMessageBubble.swift` | Message rendering with agent indicators |
| `Views/Chat/ChatMessageListView.swift` | Scrollable list with pagination |
| `Views/Chat/ChatToggleView.swift` | Header toggle (tasks ↔ chat) |
| `Core/Services/ChatService.swift` | Local-first service; Outbox-backed sends |
| `Core/Persistence/CDChatMessage+CoreDataClass.swift` | CoreData persistence |
| `Models/ChatMessage.swift` | ChatChannel + ChatMessage domain models |
| `Models/DTOs/ChatDTOs.swift` | API request/response types |

**API endpoints** (all `/api/v1/…`):

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/chat/channels` | POST | Get or create channel for list/virtual key |
| `/api/v1/chat/channels/{id}/messages` | GET | Paginated messages (cursor-based) |
| `/api/v1/chat/channels/{id}/messages` | POST | Send message (optional fileId + attachment fields) |
| `/api/v1/users/me/available-agents` | GET | AI agents for @mention |
| `/api/v1/users/me/ai-preferences` | GET/PATCH | Default agent preferences |

**Attachment upload flow:**
1. User picks photo/document → `AttachmentService.saveLocallyAndUploadAsync(context:)`
   saves locally + starts background upload. Context is `{"listId": "..."}` for list
   channels or `{"channelId": "..."}` for virtual channels.
2. Upload → `/api/v1/secure-upload/request-upload` (<4MB) or
   `/api/v1/secure-upload/get-upload-url` + direct blob (≥4MB).
3. Sends go through the Outbox `sendChatMessage` handler with a `dependsOn` edge on the
   `uploadAttachment` entry (real fileId read from the dependency's result); reconcile
   via `ChatService.reconcileOutboxSentMessage`.
4. Server associates `SecureFile` with `ChatMessage` via `chatMessageId`; response
   includes a `secureFiles` array for rendering.

**Offline support:** messages saved to CoreData with `syncStatus: "pending"` +
`clientRequestId` (dedup); attachments cached with temp IDs. Queued sends replay via
the **Outbox drain** on relaunch/reconnect. (`ChatService.syncPendingMessages()` only
handles legacy chat deletes — it is NOT the send path.)

---

## 8. Cross-platform contracts to preserve

| Contract | Canonical (web) | iOS mirror | Test |
|---|---|---|---|
| Repeating task rollover | `astrid-web/types/repeating.ts` | `Utilities/RepeatingTaskHandler.swift` (`RepeatingTaskCalculator`) | `CustomRepeatingPatternTests`, `RepeatingTaskCalculatorTests` |
| All-day task date handling (UTC midnight, Google Calendar / RFC 5545) | `astrid-web/lib/date-comparison.ts`, `date-filter-utils.ts` | `Task.isDueToday` / `Task.isOverdue` in `BadgeManager.swift` + `TaskListView.applyDateFilter` | `AllDayTimezoneTests` |
| List role / permission (listMembers is source of truth — legacy `admins[]`/`members[]` arrays are NOT populated by the endpoints iOS consumes and must NOT be branched on) | `astrid-web/lib/list-permissions.ts` (`getUserRoleInList`) | `TaskList.role(for:)`, `TaskList.isMember(userId:)`, `TaskList.canUserSaveServerSettings()` | |
| My Tasks empty-state message (single string per list type, no completed-task threshold) | `astrid-web/components/ui/astrid-empty-state.tsx` | `TaskListView.getMyTasksEmptyMessage` | `EmptyStateMessageTests` |
| Preferences + settings wire shape (`/api/v1/users/me/my-tasks-preferences`, `/api/v1/users/me/settings`) | web endpoints under `app/api/` | `MyTasksPreferences`, `UserSettings` structs | `CanonicalControlPointsTests` |

**Cross-repo change order:** make the web API change first, deploy it, then update iOS
to consume it. For breaking changes, add a new API/app version and keep the old one working.

---

## References

- [CLAUDE.md](./CLAUDE.md) — Claude Code operational adapter (commands, deploy, approvals)
- [AGENTS.md](./AGENTS.md) — Codex operational adapter (same content, Codex-branded)
- [README.md](./README.md) — project overview and setup
- `docs/API_CONTRACT.md` — backend API specification
- `docs/LOCAL_FIRST_PATTERN.md` — offline-first / Outbox architecture
- `docs/SYNC_ARCHITECTURE.md` — external sync providers
- `docs/GOOGLE_OAUTH_SETUP.md`, `docs/SHARE_EXTENSION_SETUP.md`, `docs/XCODE_SETUP.md`
- `astrid-web/ASTRID_WORKFLOW.md` — canonical cross-repo per-task process
- `astrid-web/ASTRID.md` — web-side project context

---

*Architecture lives here. The adapters ([CLAUDE.md](./CLAUDE.md), [AGENTS.md](./AGENTS.md))
hold only commands and workflow. Keep it that way.*
