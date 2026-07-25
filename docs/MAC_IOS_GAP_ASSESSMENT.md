# Mac ↔ iOS/Web UI Gap Assessment

*Feature-parity assessment of Astrid for Mac against the iOS app **and** the web app.
The Mac app shares the full service layer + Core (filters, repeating, board, sync), so gaps are
almost entirely presentation. Last refreshed 2026-07-18 after the Mac UI-mapping work, from a
three-way UI inventory (iOS `Astrid App/Views`, web `astrid-web/components`, Mac `Astrid Mac`).*

## ✅ Closed (this cycle)

- **Auth** — passkey / Google / Apple + offline; backend audience fix for the Mac bundle id.
- **Full sync** — `SyncManager.performFullSync(includeUserTasks:)` on sign-in, so lists + My Tasks
  show everything (not just opened lists).
- **Shared filter/sort** — `Core/Filters/ListTaskFiltering.swift` used by iOS **and** Mac (no fork).
- **Sidebar parity** — brand logo, real list icons (`MacListIcon`), selectable universal **My Tasks**,
  account bar at bottom-left.
- **List view** — iOS-style rows (`MacTaskRow`: priority checkbox + title + due + list chips +
  assignee glyph), reliable single-click selection, sort menu, drag-to-list, context menu,
  multi-select/bulk, inline rename. (Replaced the flat `Table`; dropped the priority column.)
- **Task detail** — title/notes/priority/due+all-day/repeat(+custom editor)/assignee/subtasks/
  comments/timer/attachments(list) + tear-off window.
- **Board / Chat** — board columns + drag; chat with @/#/! autocomplete + file attach.
- **Real-time + offline** — SSE, Outbox runner, error banner, offline banner.
- **Notifications** — local reminder scheduling + dock badge.
- **Settings** — General/Reminders/Sync/AI/Language/Connection/Account tabs.
- **Localization** — core Mac UI strings in all 12 languages.
- **Infra** — hardened runtime, deterministic unit-test host, UI smoke tests.

## ⬜ Remaining gaps (each tracked as a task in the iOS to-do list)

Priority: **3** high · **2** medium · **1** low.

| P | Gap | Task id | iOS / web reference |
|---|-----|---------|---------------------|
| 3 | Wire the remaining keyboard shortcuts (only 4 of 22 work) | `9a60b697` | web `useKeyboardShortcuts`; Mac `KeyboardShortcuts.swift` |
| 3 | Quick Add window: use shared `SmartTaskParser` (not the weak local parser) | `fa267754` | iOS `QuickAddTaskView` |
| 3 | Task **filter editor** (filters are currently read-only) | `a2bf6ccb` | iOS `MyTasksFilterSheet`/`ListSortFiltersTab`; web `list-sort-and-filters` |
| 2 | Attachment **QuickLook preview + delete** on task detail | `6a25494a` | iOS `TaskAttachmentSectionView`/`QuickLookController` |
| 2 | Saved filters / virtual lists (Today, Assigned) + Save-a-filter | `efd05e56` | iOS `SaveFilterDialog`; web saved filters |
| 2 | Apple Reminders (EventKit) connect + link lists | `33d648f2` | iOS `AppleRemindersSettingsView` |
| 2 | Per-list external sync config (Google Tasks/GitHub linking + mode) | `7043e478` | iOS `{GitHubSync,GoogleTasks}SettingsView`; web `ExternalSyncSection` |
| 2 | List admin: default task settings + recently-completed window | `c82173ff` | iOS `ListAdminTab`; web `list-admin-settings` |
| 1 | List image upload (create/edit) | `383b96af` | iOS `ImagePickerView`; web `image-picker` |
| 2 | Per-list board enable/disable + manage statuses | `9e7f37d4` | iOS `ListAdminTab`; web `ManageStatusesPanel` |
| 2 | Per-list privacy toggle + public type + AI agents / agent model | `7d77a054` | iOS `ListMembershipTab`/`ListAgentSettingsView`; web `list-membership` |
| 2 | AI settings: API keys (Claude/OpenAI/Gemini) + OpenClaw | `f8687dfb` | iOS `AIAPIKeyManagerView`/`OpenClawSettingsView` |
| 2 | Chat message actions: reply / edit / delete | `021e5b93` | iOS/web `ChatMessageBubble` |
| 2 | Task-detail comment input: @/#/! autocomplete + attachments | `eda86d23` | iOS `RichTextInput` (comments) |
| 2 | Global task search (full-text, all lists, incl. completed) | `36587d3d` | iOS Search row; web Search view |
| 2 | Rich notification actions: Complete / Snooze + reminder presenter | `32c6f756` | iOS `ReminderView`/`NotificationManager` |
| 1 | Task list row: assignee avatar for others' tasks | `942e49df` | iOS `TaskRowView`; web `task-row-content` |
| 2 | Subtask display in list (indent/splice) + display setting | `3c945236` | iOS/web subtask splicing |
| 1 | Within-list manual drag-reorder | `7b7a17d3` | iOS `.onMove`; web drag-reorder |
| 2 | Task Copy + Share (shortcode URL / native share) on detail | `1171030d` | iOS `ShareTaskView`/`TaskActionsView`; web `TaskActionMenu` |
| 2 | Board: inline “＋ Add task” per column | `db8aacda` | iOS `BoardColumnView`; web `project-status-board` |
| 1 | Account: Data export (JSON/CSV) | `180199c0` | iOS Account; web `AccountSettings` |
| 1 | Appearance: Smart-Task-Creation toggle + Sub-tasks-display setting | `a840511d` | iOS/web Appearance |
| 1 | Contacts-based collaborator invite autocomplete | `3753a521` | iOS `ContactsService`/`AddMemberSheet` |
| 1 | macOS Services / Share-menu “Add to Astrid” quick-create | `3b9883d0` | iOS Share Extension |

## Excluded — strong macOS reason (intentionally NOT tracked)

- **No tab bar / sliding overlay sidebar** — Mac correctly uses `NavigationSplitView` (3-column).
- **Haptics** (UIImpactFeedbackGenerator etc.) — no macOS equivalent; not applicable.
- **Home-screen widgets / PWA install** — N/A (iOS has no widgets either).
- **Mobile quick-add bar, swipe-to-open sidebar, pull-to-refresh, iPad 2/3-column split** — touch/
  form-factor patterns replaced by desktop equivalents (menu-bar, ⌘R, split view).
- **Web-only URL surfaces** — public list/profile pages, shortcode landing pages, invite-accept
  pages, SEO/marketing, admin dashboards, OAuth/MCP discovery docs — these are the web's job.
- **API Access / ChatGPT-MCP / webhook config screens** — power-user/dev config that belongs on web;
  low value inside the desktop app. (Revisit only if requested.)
- **Web push / calendar `.ics`/webcal subscribe** — the desktop uses native notifications + Calendar
  app; not re-implemented.

## Quality pass — style/UX, tests, performance (2026-07-24)

After feature parity, a three-way quality analysis (style/UX vs native-Mac conventions, test
coverage, performance) found the gaps below; each is tracked as a task.

**Key findings.** Style: a real white-on-white bug (detail chrome in Auto theme on a dark Mac);
zero hover/pointer affordances anywhere; Settings + all sheets + login unthemed; chat is a flat
transcript vs iOS bubbles; missing loading/branded-empty states; almost no animation; ad-hoc
typography; two disagreeing detail designs. Performance: the rows pipeline recomputes 3–5× per
body eval on every task mutation; macOS Theme tokens read UserDefaults per color access; search
is un-debounced; the board is O(columns×tasks×lists); onChange reschedules all notifications per
mutation. Tests: 171 pure-helper tests vs iOS's 1156 — the view-composition/dispatch glue, a
mocks tier, interaction UI tests, and composed-pipeline perf budgets are missing.

| P | Task | id |
|---|------|----|
| 3 | Fix white-on-white detail (Auto + dark system) | `98c6c6d5` |
| 3 | Hover + pointer affordances everywhere | `77225941` |
| 3 | Compute rows once per render + memoize pipeline | `4e0ce183` |
| 2 | Cache theme mode (no per-access UserDefaults) | `3c34c411` |
| 2 | Debounce search + one-pass board grouping | `6042bde0` |
| 2 | Coalesce task-change side-effects + split child views | `c38b177b` |
| 2 | Theme Settings, sheets, login, account bar | `55f435c2` |
| 2 | Chat visual parity (bubbles/avatars/agent/typing) | `eb1b7da6` |
| 2 | Loading + branded Astrid empty states | `1c3562e9` |
| 2 | Animate state changes | `4c7b9f08` |
| 2 | Unify detail design + Typography scale | `913216a9` |
| 2 | View-composition + dispatch glue tests (mock tier) | `0b1ee8f7` |
| 1 | UI interaction tests beyond launch smoke | `60dee573` |
| 1 | Perf budgets (composed pipeline) + QuickAdd edges | `1c21489d` |

## Notes
- Everything tracked above is Mac-native UI over already-shared services — no new business logic.
- Cross-platform contracts (repeating, permissions, board, wire shapes) are inherited via `Core`, so
  Mac stays aligned with web/iOS automatically. Keep new shared logic in `Core`, not duplicated.
