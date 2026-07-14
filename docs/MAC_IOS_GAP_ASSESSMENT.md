# Mac ↔ iOS Gap Assessment

*Assessment of feature gaps between Astrid for Mac and the iOS app, and their closure status.
The Mac app shares the full service layer; gaps are almost entirely presentation.*

## ✅ Closed

### Functional parity (the critical ones)
- **Outbox runner** — `OutboxManager.start()` now runs at launch. *Previously the Mac app queued
  writes but never synced them.*
- **Real-time (SSE)** — connect on sign-in / disconnect on sign-out (`SSEClient`), so data
  live-updates like iOS.
- **Sync workers** — GitHub + Google Tasks `refreshStatus()` + `scheduleSync()` on sign-in.
- **Task hydration** — a list's tasks are fetched from the server on selection.
- **Passkey** — shared RP (`astrid.cc`); web/iOS-compatible (see `docs/MAC_PASSKEY.md`).

### UI parity
- Auth (passkey-first), account (profile/edit/delete), lists (CRUD/favorite/**sharing/members**),
  tasks (Table/multi-select/bulk/sort/**cross-list move**), **task detail** (title/notes/priority/
  due+all-day/**repeat**/**assignee**/subtasks/comments), board, chat, quick-entry, ⌘K palette,
  menu-bar extra, Settings (appearance/reminders/account), offline banner, iOS `Theme`.

## ⬜ Remaining gaps (tracked as tasks)

| Gap | iOS reference | Notes |
|-----|---------------|-------|
| **Sync provider settings** — connect/config Google Tasks, GitHub, Apple Reminders | `Views/Settings/{GoogleTasks,GitHubSync,AppleReminders}SettingsView` | Each needs its connect/OAuth flow surfaced |
| **AI settings** — assistant, default agent, API keys, OpenClaw | `Views/Settings/{AIAssistant,DefaultAgentPicker,AIAPIKeyManager,OpenClaw}SettingsView` | |
| **Language + Server/connection settings** | `Views/Settings/{Language,Server}SettingsView` | |
| **Full reminder settings** — offset, quiet-hours times, digest time | `Views/Settings/ReminderSettingsView` | Mac has the 4 toggles only |
| **Attachments** — add/preview on tasks + chat | `Views/Tasks/TaskAttachmentSectionView`, `Views/Components/{ImagePickerView,AttachmentThumbnail,QuickLookController}` | Upload via `AttachmentService` + QuickLook |
| **Task timer** | `Views/Tasks/TaskTimerView` | |
| **Per-task reminder offset** | task detail reminder row | |
| **Custom repeat editor** | `Views/Components/CustomRepeatingPatternEditor` | Mac has simple daily/weekly/monthly/yearly; custom pattern editor pending |
| **Filters / My Tasks / saved filters** | `Views/Tasks/MyTasksFilterSheet`, `Views/Lists/{ListFilters,SaveFilterDialog}` | Mac has Due/Priority/Title sort only |
| **Public list browser** | `Views/Lists/PublicListBrowserView` | |
| **Onboarding welcome** | `Views/Onboarding/WelcomeChoiceView` | Login serves as first-run today |
| **Local notifications / reminder scheduling on Mac** | `NotificationManager`, `ReminderPresenter` | Reminder UI + macOS `UNUserNotification` scheduling |
| **Dock badge count** | `BadgeManager.updateBadge` | Wire on task changes |
| **Rich chat** — @/#/! autocomplete + attachments | `Views/Chat/ChatInputView` | Mac chat sends plain text |

## Notes
- Everything above is Mac-native UI over already-shared services — no new business logic.
- Cross-platform contracts (repeating, permissions, wire shapes) are inherited via the shared
  `Core`, so Mac stays aligned with web/iOS automatically.
