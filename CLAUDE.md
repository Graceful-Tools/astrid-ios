# Claude Code CLI - Operational Context

*Local Claude Code CLI workflow for the Astrid iOS app*

**Repository:** https://github.com/Graceful-Tools/astrid-ios
**Web App:** https://github.com/Graceful-Tools/astrid-web (separate repo)

---

## Quick Start

```bash
# Open in Xcode
open "Astrid App.xcodeproj"

# Run predeploy checks before pushing
npm run predeploy
```

---

## Quality Gates

```bash
# Quick check (localizations + build only)
npm run predeploy:quick

# Standard check (localizations + build + unit tests)
npm run predeploy

# Full check with UI tests (slower)
npm run predeploy:full

# Run specific test suites
npm run test          # Unit tests only
npm run test:ui       # UI tests only
npm run test:all      # Both unit and UI tests

# Localization validation
npm run check:localizations
```

---

## Deployment Workflow

**IMPORTANT: Push to main triggers Xcode Cloud build automatically.**

### Before Pushing

Always run predeploy checks:

```bash
npm run predeploy
```

This validates:
1. All localizations are complete (12 languages)
2. Project builds successfully
3. Unit tests pass

### Deployment Steps

```bash
# 1. Run predeploy checks
npm run predeploy

# 2. Commit changes
git add -A
git commit -m "feat: your changes"

# 3. Push to main (triggers Xcode Cloud)
git push origin main
```

### Xcode Cloud

- Push to main triggers automatic build
- TestFlight builds are distributed automatically
- Check build status in App Store Connect

---

## User Approval Points

### Always Ask Before:

1. **Pushing to main** - Triggers production build
2. **Significant changes** - Architecture, API changes
3. **Deleting files** - Confirm with user first

### Autonomous Actions (No Approval Needed)

- Code analysis and exploration
- Local builds and tests
- Implementation and testing
- Local commits
- Documentation updates

---

## Workflow Trigger: "Let's Fix Stuff"

When user says "let's fix stuff", "just fix stuff", or similar (or use `/fixstuff`):

```bash
# 1. Ensure environment is set up
# Copy .env.local from astrid-web if not present
cp ../astrid-web/.env.local .env.local 2>/dev/null || true

# 2. Pull tasks from Astrid iOS To-do list
cd ../astrid-web && npx tsx scripts/get-astrid-tasks.ts ios
```

Present tasks to the user and ask which to work on. Run `npm run predeploy` **after** implementation, not before.

### Required Shared Workflow

The canonical, cross-environment process is
[astrid-web/ASTRID_WORKFLOW.md](https://github.com/Graceful-Tools/astrid-web/blob/main/ASTRID_WORKFLOW.md).
For each task: post a strategy comment, use RED–GREEN–refactor TDD for bug fixes with a
task-ID-linked regression test, run required quality gates, then post a
completion report before marking the task complete.

This file is the iOS adapter and adds mandatory mobile safeguards: backend
writes go through the service layer; preserve unified-outbox and offline
behavior; preserve repeating-task contracts; and support the existing API
version while introducing a new app/API version for breaking changes.

### Environment Setup

Required variables (in `.env.local`, copied from astrid-web):
- `ASTRID_OAUTH_CLIENT_ID` - OAuth client ID
- `ASTRID_OAUTH_CLIENT_SECRET` - OAuth client secret
- `ASTRID_IOS_LIST_ID` - iOS task list ID (`aa41c1a3-bd63-4c6d-9b87-42c6e0aafa36`)

---

## Testing

### Test Commands

| Command | Description |
|---------|-------------|
| `npm run test` | Run unit tests |
| `npm run test:ui` | Run UI tests only |
| `npm run test:all` | Run both unit and UI tests |

### Test File Locations

| Test Type | Location |
|-----------|----------|
| Unit tests | `Astrid AppTests/Tests/UnitTests/` |
| Integration tests | `Astrid AppTests/Tests/IntegrationTests/` |
| Test mocks | `Astrid AppTests/Tests/Mocks/` |
| UI tests | `Astrid AppUITests/` |

### Xcode Commands (Alternative)

```bash
# Build
xcodebuild build -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -quiet

# Run unit tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppTests" -quiet

# Run UI tests
xcodebuild test -scheme "Astrid App" -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:"Astrid AppUITests" -quiet
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `npm run predeploy:quick` | Quick check (build only) |
| `npm run predeploy` | Standard check (build + unit tests) |
| `npm run predeploy:full` | Full check (includes UI tests) |
| `npm run test` | Run unit tests |
| `npm run test:all` | Run all tests |
| `npm run check:localizations` | Validate translations |
| `npm run build` | Build app (quiet mode) |

### Common Workflows

| Scenario | Action |
|----------|--------|
| Before pushing | `npm run predeploy` |
| After localization changes | `npm run check:localizations` |
| Full validation | `npm run predeploy:full` |
| Debug build issues | `npm run build:verbose` |

---

## Canonical Control Points

Every write to a backend-backed resource must flow through a service layer — never call `AstridAPIClient` directly from a view, timer, notification handler, or other non-service module. The service layer is where optimistic updates, offline queue, CoreData cache, and dedup live, and it's where iOS stays aligned with the web's logic contract.

**Rule of thumb:** if a service is missing the method you need, add it first. Adding a one-off direct `AstridAPIClient` call from a view is how we introduced the weekly-M/W/F completion regression, the on-device-AI-skips-rollover bug, and the offline-member-mutation loss bug — all in the last few days.

| Domain | Canonical service | Entry point | Notes |
|--------|-------------------|-------------|-------|
| Tasks (CRUD) | `TaskService` | `createTask`, `updateTask`, `deleteTask`, `copyTask` | Writes journal through the unified Outbox; CDTask is the cache/reconcile store. |
| Task completion (incl. repeat rollover) | `TaskService.completeTask` | See "Repeating Tasks" below for all six entry points. | MUST go through this — never `updateTask(completed: true)`. |
| Lists | `ListService` | `createList`, `updateList`, `deleteList`, `toggleFavorite`, `fetchLists` | |
| List members (add / role / remove) | `ListMemberService` | `addMember`, `updateMemberRole`, `removeMember`, `cancelInvitation` | Offline queue via CDMember. |
| Comments | `CommentService` | `createComment`, `updateComment`, `deleteComment` | Outbox-backed (create/update/delete kinds). |
| Chat | `ChatService` | `sendMessage`, `getAIAssistantSettings`, `postAgentResponse` | AI-assistant helpers are cached (60s TTL). |
| Attachments | `AttachmentService` | `saveLocallyAndUploadAsync`, etc. | |
| User smart-task settings | `UserSettingsService` ↔ `AstridAPIClient.getSmartTaskSettings` / `updateSmartTaskSettings` | `/api/v1/users/me/settings` | UserDefaults-first, 300ms debounce to server. |
| My Tasks preferences | `MyTasksPreferencesService` ↔ `AstridAPIClient.getMyTasksPreferences` / `updateMyTasksPreferences` | `/api/v1/users/me/my-tasks-preferences` | UserDefaults-first, 300ms debounce to server. |
| Reminder/notification completion | `ReminderPresenter` → `TaskService.completeTask(task:)` | Must pass `task:` so rollover doesn't depend on cache state. |
| Apple Reminders sync | `AppleRemindersService` → `TaskService.completeTask(task:)` | |
| On-device AI complete action | `AppleFoundationModelService` → `TaskService.completeTask` | Must NOT use `updateTask(completed: true)`. |

**Detail-view-style callers:** when a view lets the user edit fields before confirming (completion, submit, save), propagate ALL edited fields — at minimum `dueDateTime`, `isAllDay`, `repeating`, `repeatingData`, `repeatFrom` — into the `task:` argument before calling `TaskService.completeTask` / `updateTask`. Otherwise rollover anchors on stale values.

**Alignment with web:** the service layer is also the boundary where we keep iOS aligned with the reference implementation in `astrid-web`. When you add a field to a request/response on one platform, mirror it on the other. The `CanonicalControlPointsTests` suite locks down the JSON wire shape of shared types (`MyTasksPreferences`, `UserSettings`) so a silent drift fails a unit test rather than shipping to production.

### Cross-platform contracts to preserve

| Contract | Canonical file (web) | iOS mirror | Test |
|---|---|---|---|
| Repeating task rollover | `astrid-web/types/repeating.ts` | `Utilities/RepeatingTaskHandler.swift` (`RepeatingTaskCalculator`) | `CustomRepeatingPatternTests`, `RepeatingTaskCalculatorTests` |
| All-day task date handling (UTC midnight, Google Calendar / RFC 5545) | `astrid-web/lib/date-comparison.ts`, `date-filter-utils.ts` | `Task.isDueToday` / `Task.isOverdue` in `BadgeManager.swift` + filter in `TaskListView.applyDateFilter` | `AllDayTimezoneTests` |
| List role / permission (listMembers is source of truth — legacy `admins[]`/`members[]` arrays are not populated by server endpoints iOS consumes and must NOT be branched on) | `astrid-web/lib/list-permissions.ts` (`getUserRoleInList`) | `TaskList.role(for:)`, `TaskList.isMember(userId:)`, `TaskList.canUserSaveServerSettings()` | |
| My Tasks empty-state message (single string per list type, no completed-task threshold) | `astrid-web/components/ui/astrid-empty-state.tsx` | `TaskListView.getMyTasksEmptyMessage` | `EmptyStateMessageTests` |
| Preferences + settings wire shape (`/api/v1/users/me/my-tasks-preferences`, `/api/v1/users/me/settings`) | web endpoints under `app/api/user/` | `MyTasksPreferences`, `UserSettings` structs | `CanonicalControlPointsTests` |

---

## Unified Outbox (the only write path)

All backend writes for tasks, comments, chat sends, and attachment uploads journal through `Astrid App/Core/Outbox/` (journal + runner + per-kind handlers). Eight kinds: `createTask`, `updateTask`, `deleteTask`, `createComment`, `updateComment`, `deleteComment`, `sendChatMessage`, `uploadAttachment`. Entries carry a `clientRequestId` (server-side idempotency), retry with backoff, dead-letter on permanent errors (surfaced in Settings → Outbox), and support `dependsOn` chains (upload→comment/send). Local-state waits return `.blocked` (no attempt burn). The legacy per-service sync was deleted; `syncPendingOperations`/`syncPendingComments` are thin drain wrappers. Lists/ListMembers and chat deletes remain legacy (no kinds yet). Sign-out wipes the journal. See `docs/LOCAL_FIRST_PATTERN.md`.

## External sync providers

`Astrid App/Core/Sync/` mirrors content two-way with Apple Reminders, Google Tasks, and GitHub Issues (client-side workers; server stores links/tokens and proxies via `astrid-web /api/v1/sync/*`; GitHub webhook → SSE `external_sync_refresh` nudge). All decision logic is pure and unit-tested: `SyncSuppression` (dual watermarks + `remoteWins` last-write-wins), `GoogleDueMapping`, `SyncPullOrdering` (sub-issue/subtask parents first), `GoogleAutoLink` (modes: manual / all-Google→Astrid with suffix / all-Astrid→Google / bidirectional; server-side `Integration.metadata`), `CommentSyncPlanner` (GitHub comments create/edit/delete, directional canonicality), `SyncDeletionPolicy` + `SyncDeletionLedger` (tombstone-driven remote deletes; complete-listing-guarded local deletes), `CompletionDriftPolicy`, `CompletedBackfill` (completed history 20/pass, backdated, never delays live sync), `RFC3339`. Inbound completion ALWAYS routes through `TaskService.completeTask(task:source:completedAt:)`. Sign-out resets all provider state (`SyncStateReset`, tested).

## Completion metadata & subtasks

- Tasks carry `completedAt` (real completion time, backdatable by sync) and `completedSource` (`astrid|google|github|apple`). The recently-completed window prefers `completedAt` on both platforms; task detail shows "Completed via …" for non-Astrid completions.
- Subtasks: `parentTaskId` self-relation (SetNull on parent delete), inherit the parent's lists, complete via `TaskService.completeTask` per subtask, display per the synced `subtaskDisplay` setting with depth-capped indentation. Maps to Google Tasks `parent` and GitHub sub-issues 1:1.

## Repeating Tasks

**Single source of truth for next-occurrence math:**
`Astrid App/Utilities/RepeatingTaskHandler.swift` (`RepeatingTaskCalculator`). This mirrors `astrid-web/types/repeating.ts` + `astrid-web/lib/repeating-task-handler.ts` and must stay behavior-compatible with them.

**Production entry point:** `TaskService.completeTask(id:completed:task:...)`. Completing a task MUST go through this function — it calls `calculateNextOccurrence`, which delegates to `RepeatingTaskCalculator`. Do NOT complete a task by calling `updateTask(completed: true)` — that path skips repeat rollover.

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

Detail-view completion (and any future caller that supports in-flight edits) must propagate edited fields — at minimum `repeating`, `repeatingData`, `repeatFrom`, `dueDateTime`, `isAllDay` — into the `task:` argument before handing off, so the rollover anchors on what the user sees, not stale state.

`TaskService.calculateNextOccurrence(for:)` itself is a thin delegator. Do NOT inline pattern math there or anywhere else — a prior inline implementation ignored `weekdays`, `monthRepeatType`, `monthWeekday`, and yearly `month`/`day`, breaking weekly M/W/F rollover.

**When changing pattern logic:**
1. Update `RepeatingTaskCalculator` only.
2. Mirror the change in `astrid-web/types/repeating.ts`.
3. Add tests at BOTH levels:
   - `RepeatingTaskCalculatorTests` / `CustomRepeatingPatternTests` — calculator in isolation.
   - `testTaskService_*` cases in `CustomRepeatingPatternTests` — covers the production completion path so isolation-only tests don't mask a broken wire-up.
4. Multi-step progression tests (walk 6+ completions) surface bugs that single-step tests miss.

**Key files:**

| File | Purpose |
|------|---------|
| `Astrid App/Utilities/RepeatingTaskHandler.swift` | Canonical `RepeatingTaskCalculator` |
| `Astrid App/Core/Services/TaskService.swift` (`calculateNextOccurrence`) | Production entry point — delegates only |
| `Astrid App/Models/Task.swift` (`CustomRepeatingPattern`) | Pattern model; marked `nonisolated` so Codable round-trips through `CDTask` |
| `Astrid AppTests/Tests/UnitTests/RepeatingTaskCalculatorTests.swift` | Calculator unit tests |
| `Astrid AppTests/Tests/UnitTests/CustomRepeatingPatternTests.swift` | Round-trip + multi-step progression + TaskService-path tests |

---

## Chat & Agent Features

### Per-List Chat
Every list (including My Tasks) has a chat channel accessible via the chat toggle button in the header. Chat supports:
- **@mentions** for users and AI agents (format: `@[Name](id)`)
- **#list** and **!task** references (format: `#[Name](id)`, `![Name](id)`)
- **File attachments** — photos and documents via paperclip button, with offline queue support
- **AI agent responses** — @mention Astrid or configured agents; server-side processing via `processAstridMessage`
- **Real-time updates** — SSE for live messages + 3-second polling fallback

### Key Chat Files

| File | Purpose |
|------|---------|
| `Views/Chat/ChatPanelView.swift` | Main chat container with channel resolution |
| `Views/Chat/ChatInputView.swift` | Rich input with @/#/! autocomplete + attachments |
| `Views/Chat/ChatMessageBubble.swift` | Message rendering with agent indicators |
| `Views/Chat/ChatMessageListView.swift` | Scrollable message list with pagination |
| `Views/Chat/ChatToggleView.swift` | Header toggle button (tasks ↔ chat) |
| `Core/Services/ChatService.swift` | Local-first service with offline sync |
| `Core/Persistence/CDChatMessage+CoreDataClass.swift` | CoreData persistence |
| `Models/ChatMessage.swift` | ChatChannel + ChatMessage domain models |
| `Models/DTOs/ChatDTOs.swift` | API request/response types |

### Chat API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/chat/channels` | POST | Get or create channel for list/virtual key |
| `/api/v1/chat/channels/{id}/messages` | GET | Paginated messages (cursor-based) |
| `/api/v1/chat/channels/{id}/messages` | POST | Send message (with optional fileId + attachment fields) |
| `/api/v1/users/me/available-agents` | GET | List AI agents for @mention |
| `/api/v1/users/me/ai-preferences` | GET/PATCH | Default agent preferences |

### Attachment Upload Flow
1. User picks photo/document → `AttachmentService.saveLocallyAndUploadAsync(context:)` saves locally + starts background upload
2. Context is `{"listId": "..."}` for list channels or `{"channelId": "..."}` for virtual channels
3. Upload goes to `/api/v1/secure-upload/request-upload` (<4MB) or `/api/v1/secure-upload/get-upload-url` + direct blob (≥4MB)
4. Sends go through the Outbox `sendChatMessage` handler with a `dependsOn` edge on the `uploadAttachment` entry (real fileId read from the dependency's result); reconcile via `ChatService.reconcileOutboxSentMessage`
5. Server associates `SecureFile` with `ChatMessage` via `chatMessageId`
6. Response includes `secureFiles` array for rendering

### Offline Support
- Messages saved to CoreData with `syncStatus: "pending"` and `clientRequestId` for deduplication
- Attachments cached locally with temp IDs, uploaded when online
- Queued sends replay via the Outbox drain on relaunch/reconnect (`syncPendingMessages()` only handles legacy chat deletes)

---

## Documentation

### Root Files

- `CLAUDE.md` - Claude Code CLI context (this file)
- `README.md` - Project overview
- `CONTRIBUTING.md` - Contribution guidelines
- `SECURITY.md` - Security policy
- `CODE_OF_CONDUCT.md` - Community standards

### Technical Docs (in `/docs/`)

- `API_CONTRACT.md` - Backend API specification
- `LOCAL_FIRST_PATTERN.md` - Offline-first architecture
- `GOOGLE_OAUTH_SETUP.md` - Google OAuth configuration
- `SHARE_EXTENSION_SETUP.md` - Share extension setup
- `XCODE_SETUP.md` - Complete Xcode setup

---

## See Also

- **[README.md](./README.md)** - Project overview and setup
- **[docs/API_CONTRACT.md](./docs/API_CONTRACT.md)** - API specification
- **[docs/LOCAL_FIRST_PATTERN.md](./docs/LOCAL_FIRST_PATTERN.md)** - Offline architecture
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - How to contribute

---

*This file is for Claude Code CLI.*
