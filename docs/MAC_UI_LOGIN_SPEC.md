# Astrid for Mac — UI, Login & Account Management Spec

*Status: Draft · Companion to `docs/MAC_APP_SPEC.md`. Scopes the UI/auth work needed to turn the
Mac shell into a usable app.*

The Mac target already shares the full service layer (`TaskService`, `AuthManager`, Outbox, Sync,
…) and has a native shell (sidebar / task `Table` / detail, ⌘K palette, quick-entry, menu-bar
extra, Settings). **What's missing is almost entirely presentation** — the iOS Views are excluded
from the Mac target (they use iOS-only SwiftUI), so Mac has no login, no account UI, and only
minimal task/list UI. The shared **`AuthManager`** already exposes `signInWithApple`,
`signInWithGoogle`, `signInWithPasskey`, `signUpPasswordless` (email), sign-out, and session
restore — and it compiles on macOS. So this is Mac-native UI on top of existing logic.

**Ground rule (unchanged):** no business logic in Mac-only views — everything routes through the
shared services. Reuse the iOS Views listed as the reference behavior; build Mac-native equivalents.

---

## A. Login & session (foundational — unlocks real data)

### A1 · Auth gate + session restore + routing
`AstridMacApp` currently always shows the shell. Make the root observe `AuthManager.shared`:
restore the session on launch; show the **sign-in screen when signed out** and `MacRootView`
when signed in; react to sign-in/out live. iOS ref: `AstridApp.swift` auth routing.
**Done when:** launching signed-out shows login; signing in reveals real lists; sign-out returns to login.

### A2 · Native Mac sign-in screen
A Mac window with **Sign in with Apple**, **Google**, **Passkey**, and **email (passwordless)**,
each calling the matching `AuthManager` method (OAuth via `ASWebAuthenticationSession`, anchored by
the shim's `presentationAnchor()`). Loading + error states. iOS ref: `Views/Authentication/LoginView.swift`,
`SignInPromptView.swift`.
**Done when:** a real account can sign in on Mac via each method and land in the shell.

### A3 · Sign-out + account switching (+ optional session sharing)
Sign-out from the account menu (wipes local session/Outbox per `AuthManager.signOut`). Optional
fast path: share the iOS session via **App Groups + Keychain access group** so a Mac that already
runs the iOS app is signed in automatically. iOS ref: `AuthManager.signOut`.

---

## B. Account management

### B1 · Profile view + edit
Profile (avatar, name, email) and edit (name, avatar upload via `AttachmentService`). iOS ref:
`Views/UserProfileView.swift`, `Views/EditProfileView.swift`, `ViewModels/AccountViewModel.swift`,
`EditProfileViewModel.swift`.

### B2 · Account settings (connection, sign-out, delete account)
Server/connection mode, sign-out, and the **delete-account** flow (confirmation → wipe). iOS ref:
`Views/Settings/AccountSettingsView.swift`, `DeleteAccountView.swift`.

---

## C. Core task UI

### C1 · Full task detail
Replace the minimal `MacTaskDetailView` with full editing: title, notes, due date/time + all-day,
priority, repeat (via `RepeatingTaskCalculator` contract), lists, assignee, reminders — plus
**subtasks, comments, attachments, and the timer**. All writes through `TaskService`. iOS ref:
`Views/Tasks/TaskDetailViewNew.swift`, `SubtasksSectionView.swift`, `CommentSectionViewEnhanced.swift`,
`TaskAttachmentSectionView.swift`, `TaskTimerView.swift`.

### C2 · Task create / full edit sheet
A full new-task/edit sheet (all fields above), beyond the quick-entry parser. iOS ref:
`Views/Tasks/TaskEditView.swift`, `QuickAddTaskView.swift`.

### C3 · Drag-drop reorder + cross-list move
Reorder tasks and drag across lists in the sidebar (deferred from M2 — SwiftUI `Table` reordering).
Writes via `TaskService.updateTask`.

---

## D. List management UI

### D1 · Create / edit / delete / favorite lists + list picker
iOS ref: `Views/Lists/ListEditView.swift`, `ListsView.swift`, `ListPickerView.swift`, `ListRowView.swift`.

### D2 · List sharing, members & roles
Add/remove members, roles, invitations (via `ListMemberService`). iOS ref:
`Views/Lists/ShareListView.swift`, `AddMemberSheet.swift`, `ListMembershipTab.swift`.

### D3 · List settings (filters, sorting, defaults, agent)
iOS ref: `Views/Lists/ListSettingsModal.swift`, `ListFiltersView.swift`, `ListSortFiltersTab.swift`,
`ListDefaultsView.swift`, `ListAgentSettingsView.swift`, `ListAdminTab.swift`.

---

## E. Secondary surfaces

### E1 · Per-list Chat panel
Messages, @/#/! mentions, attachments, AI agents (via `ChatService`). iOS ref: `Views/Chat/*`.

### E2 · Board / kanban view
Column board with drag between statuses. iOS ref: `Views/Board/*`.

### E3 · Settings panels
Appearance, language, and **sync providers** (Google Tasks / GitHub / Apple Reminders/EventKit),
AI assistant/agents, server. iOS ref: `Views/Settings/*` (Appearance, Language, GoogleTasks,
GitHubSync, AppleReminders, AIAssistant, DefaultAgentPicker, OpenClaw, Server).

### E4 · Onboarding + empty/loading/error/connection states
First-run welcome + the empty/loading/error/offline states across the shell. iOS ref:
`Views/Onboarding/WelcomeChoiceView.swift`, `Views/Components/{EmptyStateView,ConnectionStatusBanner,SplashView}.swift`.

---

## Suggested order
**A (auth) first** — it unlocks real-data testing of everything else. Then **B (account)** and
**C1/C2 (task detail/edit)** for a usable daily driver, then **D (lists)**, then **E** surfaces.
Each is Mac-native UI over already-shared logic; the excluded iOS Views are the behavioral spec.
