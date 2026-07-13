# Astrid for Mac — Native App Specification

*Status: Draft v1 · Owner: TBD · Last updated: 2026-07-12*

Build a **native Mac app** for Astrid that feels **performant and powerful**, while staying
**easy to maintain as the web and iOS apps evolve**. Today we ship the iOS binary and run it
on Apple Silicon ("Designed for iPad"); this spec replaces that with a real Mac experience
that shares one codebase.

---

## 1. Goals, non-goals, north stars

### North stars (in priority order)
1. **Maintainable with web + iOS.** The Mac app introduces **zero new business logic**. It
   shares the entire iOS `Core/` layer, so a change on web that flows into iOS's Swift
   services reaches Mac automatically. Mac-only code is presentation and app-shell only.
2. **Powerful.** Keyboard-first, command palette, global quick-entry, Mac-grade multi-select /
   drag-drop / column views. A power user should rarely touch the mouse.
3. **Performant.** Instant launch to usable, 60/120fps scrolling on large lists, sub-frame
   keyboard response. Local-first is already the architecture — Mac must not regress it.

### Goals (v1)
- A dedicated **macOS SwiftUI target** in the existing Xcode project, sharing `Core/` and most views.
- Mac-native shell: sidebar (`NavigationSplitView`), full menu bar (`.commands`), Settings scene, standard window chrome.
- **Keyboard-first + ⌘K command palette** (quick-open tasks/lists, run any action).
- **Global quick-entry hotkey** (capture a task from anywhere).
- **Mac-grade interactions**: multi-select + bulk actions, drag-drop across lists, resizable multi-column table view, inline editing.
- Ship **two builds**: Mac App Store (sandboxed) **and** direct notarized DMG (with auto-update).

### Non-goals (v1 — architecture supports, deferred)
- Menu-bar extra (glanceable tasks / quick add) → **v1.1**.
- Rich multi-window tear-off (open task/list in its own window) → **v1.1** (WindowGroup makes it cheap).
- iPad-specific and Apple-Watch surfaces.
- Any Mac-only feature that would fork business logic from web/iOS.

### Explicitly out of scope
- Rewriting the data/sync layer. It's already portable and correct; we reuse it verbatim.

---

## 2. Where we're starting (grounded in the codebase)

| Fact | Value | Implication |
|------|-------|-------------|
| Swift files / LOC | 217 / ~60K | Large but well-factored. |
| SwiftUI files | 111 | View layer is SwiftUI-first → high reuse. |
| **`Core/` UIKit usage** | **0 in the pure service logic** | Models, Services, Outbox, Persistence, Sync, RealTime, Networking are platform-agnostic. |
| Files importing UIKit | 14 total | The **entire** porting surface. See §5. |
| AppKit / `#if os(macOS)` / Catalyst | 0 / 0 / 0 | Greenfield for Mac — no legacy conditionals to unwind. |
| App shell | `WindowGroup → MainTabView` (per-tab `NavigationStack`) | Replaced by a Mac shell (§6); business views reused. |
| Cross-platform contracts | Mirrored to `astrid-web` and locked by tests | Mac inherits these for free (§10). |

**Takeaway:** this is a presentation-layer port, not a rewrite. The risk is concentrated in
14 files and the app shell — everything else compiles for Mac with a thin shim.

---

## 3. Architecture decision

**Native SwiftUI macOS target in the same Xcode project, sharing the `Core/` layer and most
SwiftUI views.** (Chosen over Mac Catalyst: Catalyst is close to what we run today and caps
the native-feel/performance ceiling we're trying to raise. Chosen over a separate AppKit app:
that would fork business logic and violate north-star #1.)

### 3.1 Target & module layout
Restructure so shared code lives in one place both apps compile:

```
AstridCore  (Swift package or shared framework — NEW)
  ├─ Models, Services, Outbox, Persistence, Sync, RealTime, Networking, Notifications
  └─ Platform/            ← the abstraction shims (§5)
AstridKitUI (shared SwiftUI — NEW or shared membership)
  └─ Feature views (Tasks, Lists, Board, Chat, Settings, Components) with #if os() adaptation
Astrid (iOS app target)      → thin shell: WindowGroup → MainTabView (existing)
Astrid (macOS app target)    → thin shell: WindowGroup → MacRootView (NavigationSplitView) + .commands (NEW)
```

- **Preferred:** extract `Core/` into an **`AstridCore` Swift package** with **no** `import UIKit`
  in its API. This makes "no UIKit in shared logic" a *compiler-enforced* rule, not a convention —
  the strongest possible guard against platform drift.
- **Pragmatic interim:** if extracting a package is too disruptive for v1, add the macOS target
  and give shared files **membership in both targets**, isolating platform code behind `#if`.
  Migrate to the package in v1.1. (Decide in the spike, §11 M0.)

### 3.2 The one hard rule
> **No business logic in macOS-only files.** Mac-only code is limited to: the app shell,
> menu commands, window/scene management, keyboard handling, the command palette, quick-entry,
> and platform shims. If you're tempted to put task/list/sync logic in a `#if os(macOS)` block,
> add it to the shared service instead (same rule the iOS app follows — see `CLAUDE.md`/`ASTRID.md`
> Canonical Control Points).

---

## 4. Minimum OS & language

- **Deployment target:** the **two most recent macOS majors** (currently **macOS 26** and the
  prior release; pin exact `MACOSX_DEPLOYMENT_TARGET` in the spike). This gives us modern
  `NavigationSplitView`, `MenuBarExtra`, `.commands`, `Table`, and Observation while keeping a
  reasonable install base.
- Availability-guard only the handful of newest-OS-only APIs behind `if #available`.
- Swift 5 today; adopt Swift 6 concurrency checking incrementally (out of scope for v1 shell).

---

## 5. Platform abstraction layer (the entire porting surface)

The 14 UIKit-importing files split into two buckets. **Bucket A** must compile on Mac
(shared logic with light UIKit calls); **Bucket B** is iOS-only UX that Mac replaces natively.

### Bucket A — shared logic needing a shim (make it compile & behave on Mac)
| File | UIKit touchpoint | Mac strategy |
|------|------------------|--------------|
| `Core/Services/TaskService.swift` | app lifecycle / background hooks | `#if os(iOS)` guard; provide a no-op / `NSApplication` equivalent via `PlatformApplication` shim |
| `Core/Services/BadgeManager.swift` | app icon badge | `NSApp.dockTile.badgeLabel` on Mac |
| `Core/Services/AttachmentService.swift` | `UIImage` | `PlatformImage = NSImage`/`UIImage` typealias in `AstridCore/Platform` |
| `Core/Services/AppleRemindersService.swift` | EventKit + UIKit | EventKit is cross-platform; guard the UIKit bits |
| `Core/Services/FeatureFlagService.swift`, `ReviewPromptManager.swift`, `NotificationPromptManager.swift` | `UIApplication`, review/prompt UI | route through `PlatformApplication`; Mac uses `SKStoreReviewController`/`NSApplication` equivalents |
| `Core/Sync/GoogleTasksSyncService.swift`, `GitHubSyncService.swift` | background-task / lifecycle | guard iOS-only background APIs; Mac uses its own lifecycle |
| `Utilities/ImageCache.swift` | `UIImage` | `PlatformImage` typealias |

Introduce a small **`AstridCore/Platform/`** shim so shared code never writes raw UIKit:
```swift
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
enum PlatformApplication { static func openSettings() { … } ; static func setBadge(_:) { … } }
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
enum PlatformApplication { static func openSettings() { … } ; static func setBadge(_:) { … } }
#endif
```

### Bucket B — iOS-only UX, replaced by native Mac equivalents (not ported)
| File | Why it's iOS-only | Mac replacement |
|------|-------------------|-----------------|
| `Views/Components/UIKitWheelPicker.swift` | iOS wheel date picker | native `DatePicker` / `.graphical` |
| `Extensions/View+InteractivePopGesture.swift` | iOS swipe-back | N/A (sidebar + back via toolbar/⌘[) |
| `Extensions/View+TextEditorInsets.swift` | `UITextView` insets | native `TextEditor` styling |
| `Utilities/KeyboardEngineWarmer.swift` | iOS keyboard warm-up | N/A (no soft keyboard) |
| `Views/Components/*` haptics (`UIImpactFeedback`, 12 sites) | Taptic Engine | `NSHapticFeedbackManager` where meaningful, else no-op via a `Haptics` shim |

**Effort estimate:** Bucket A is ~1–2 days of mechanical shimming; Bucket B is replaced as the
corresponding Mac screens are built (§6–7), not up front.

---

## 6. App shell & navigation

Replace the iOS `TabView` shell with a Mac-idiomatic one. Business/feature views are reused;
only the container and chrome are new.

### 6.1 Scenes
```swift
@main struct AstridMacApp: App {
  var body: some Scene {
    WindowGroup { MacRootView() }          // main window: sidebar + content + detail
      .commands { AstridCommands() }        // full menu bar (§7.1)
    Settings { MacSettingsView() }          // ⌘, — reuses existing Settings feature views
    Window("Quick Add", id: "quick-add") { QuickEntryView() }   // global hotkey target (§7.2)
    // v1.1: MenuBarExtra { … }, WindowGroup(for: TaskID.self) { … } tear-off windows
  }
}
```

### 6.2 Three-column layout
`NavigationSplitView`:
- **Sidebar** — lists, favorites, My Tasks, filters, sync sources. Reorderable, collapsible.
- **Content** — the task list for the selection, as a resizable **`Table`** (multi-column) or
  a list view, user-toggleable (§7.3).
- **Detail** — the existing task-detail feature view, reused as-is behind the shim.

Selection state is driven by the same view models the iOS app uses; the split view is just a
different presentation of the same navigation model.

### 6.3 Window chrome
- Native unified toolbar (search field, view toggles, filter, add).
- Standard full-screen, tabbing, restoration. State restoration for last selection + window frame.

---

## 7. Powerful features (v1)

### 7.1 Keyboard model — **parity with web is a contract**

The Mac keyboard scheme **mirrors the web app's** so muscle memory transfers 1:1. The web
scheme is **single-key, modifier-less** (Gmail/Superhuman-style), canonical in
`astrid-web/hooks/useKeyboardShortcuts.ts` → `KEYBOARD_SHORTCUTS`. The Mac app defines a
**mirrored `KeyboardShortcuts` table** that must stay behavior-compatible with it (see the
cross-platform contract in §10.2), and mirrors web's guard: **shortcuts do not fire while a
text field/editor is focused or a modal/sheet is open.**

**Canonical shared shortcuts (mirror web exactly — bare keys, no modifier):**

| Key | Action | | Key | Action |
|-----|--------|-|-----|--------|
| `n` | New task | | `t` | Edit task title |
| `x` | Complete selected task | | `s` | Edit task description |
| `j` / `↓` | Select next task | | `c` | Add task comment |
| `k` / `↑` | Select previous task | | `e` | Assign to "No One" |
| `o` | Open/close task detail panel | | `i` | Edit task lists |
| `l` | Cycle list filters/tags | | `d` | Jump to "Date" |
| `←` | Due date −1 day | | `p` | Postpone 1 week |
| `→` | Due date +1 day | | `v` | Remove due date |
| `0`/`1`/`2`/`3` | Priority None/Low/Med/High | | `Delete`/`Backspace` | Delete task |
| `?` | Show shortcuts help | | | |

> **Do not renumber or reassign these on Mac.** They are a shared contract; changing one means
> changing web + Mac together (§10.2). Any Mac-only additions must use a modifier so they can't
> collide with a bare web key.

**Mac-native additions (layered on top, use modifiers — NOT from web):**
- **⌘-menu equivalents** in the menu bar for discoverability where Mac users expect them
  (File → New Task ⌘N, Edit → Delete ⌘⌫, etc.). These are *additive*; the bare keys above remain
  the canonical shared set and stay active when no field/modal is focused.
- **Command palette (⌘K)** — a floating searchable panel to jump to any task/list (quick-open) and
  run any command by name. Fuzzy match over task titles, list names, and the command registry.
  (Web uses `?` for a static listing; the palette is a Mac power-add and must not shadow a bare key.)
- **Go-to-list ⌘1…9** (with ⌘, to avoid colliding with bare `0–3` priority keys).
- **Full keyboard nav:** type-to-select, space to quick-look detail; no action requires the mouse.

- Define a single **`CommandRegistry`** (Mac-only, presentation layer) mapping command → shared
  service call, so the menu bar, the bare-key handler, and the palette share one source of truth
  and every command routes through `TaskService`/the shared services (never the API directly).

### 7.2 Global quick-entry hotkey
- System-wide hotkey (default ⌥Space, user-rebindable) opens the lightweight **Quick Add** window
  from anywhere; type a task (with natural-language date + list via `#list`/`!task` tokens the app
  already parses), ↵ to save through `TaskService` → Outbox, window dismisses.
- **Registration:** `RegisterEventHotKey` (Carbon) or a thin wrapper — works in **both**
  distributions. Capturing arbitrary global keystrokes (not needed here) would require Accessibility;
  a single registered hotkey does not. **Validate in M0** on both a sandboxed and a direct build.
- Quick Add writes through the same service path as every other client — no bespoke logic.

### 7.3 Mac-grade interactions
- **Multi-select** (⌘-click, ⇧-click, ⌘A) with **bulk actions** (complete, move to list, set due,
  delete) that fan out through `TaskService`/Outbox as individual journaled writes.
- **Drag-drop:** reorder within a list; drag tasks across lists in the sidebar; drag in files to
  attach (existing `AttachmentService` upload path).
- **Multi-column `Table`:** title, due, list, priority, assignee, completed-source; resizable,
  sortable, column show/hide. Toggle between Table (power) and List (compact) views.
- **Inline editing:** rename/title edit in place; quick due-date popover.
- Virtualized rendering so 10k-task lists stay smooth (§9).

---

## 8. Distribution — both channels

| Aspect | Mac App Store build | Direct (notarized DMG) build |
|--------|---------------------|------------------------------|
| Signing | App Store cert, same team as iOS | Developer ID + **notarization** + stapling |
| Sandbox | **Required** (`com.apple.security.app-sandbox`) | Sandbox optional (recommend on) |
| Updates | App Store | **Sparkle** (appcast on our domain) |
| Global hotkey | `RegisterEventHotKey` (allowed) | Same, plus Accessibility fallback if ever needed |
| Login item (launch at login) | `SMAppService` (sandbox-safe) | `SMAppService` |
| Entitlements | app-sandbox, network client, user-selected files (attachments), keychain, App Groups (share w/ iOS?), Apple Reminders/EventKit, Google/GitHub OAuth via ASWebAuthenticationSession | same minus store-only constraints |
| Config | `Astrid-macOS-AppStore.xcconfig` | `Astrid-macOS-Direct.xcconfig` |

- Keep **one macOS target, two configs/schemes** so the code is identical and only entitlements
  + update mechanism differ. A `#if APPSTORE` compile flag gates the update UI (Sparkle off in the
  store build).
- Reuse the existing OAuth flows via `ASWebAuthenticationSession` (cross-platform). Confirm the
  `X-OAuth-Token` API path and SSE real-time client work unchanged on Mac (they should — pure networking).

---

## 9. Performance targets & how we hit them

| Metric | Target | How |
|--------|--------|-----|
| Cold launch → interactive | < 500 ms | Local-first CoreData cache already hydrates instantly; keep startup hydration off the critical path (as iOS already does). |
| List scroll | 120fps on ProMotion, no drops at 10k tasks | `Table`/`List` virtualization; stable identities; avoid per-row heavy work; precomputed row view models. |
| Keyboard action latency | < 1 frame (perceived instant) | Optimistic updates through the Outbox (already the model); never block the main actor on network. |
| Command palette open + first results | < 100 ms | In-memory index; async fuzzy search off the main actor. |
| Memory (typical account) | reasonable for a desktop task app | Image cache bounded; release detail views on deselect. |
| Offline | full function | Outbox + CoreData already provide it; Mac must not add a network-required path. |

**Rule:** Mac uses the **same optimistic, journaled, offline-first write path** as iOS. Any Mac
screen that talks to the network directly (bypassing the service layer) is a bug — it breaks both
performance and the maintenance model.

---

## 10. Maintainability with web + iOS (first-class requirement)

This is the reason for the architecture, restated as an operating model.

### 10.1 How a change propagates
```
web change → mirrored into iOS Core/ service (existing cross-platform contract discipline)
           → Mac shares that exact Core/ code → Mac gets it for free, no Mac edit needed
```
Because Mac adds **no** business logic, the only Mac work for a shared change is *presentation*
(e.g., surfacing a new field in a column) — and often none.

### 10.2 What keeps it from drifting
- **`AstridCore` package with no UIKit API** → the compiler forbids platform logic from leaking in.
- **The "no business logic in macOS-only files" rule** (§3.2), enforced in code review.
- **Existing contract tests** already lock the wire shapes and rules that iOS mirrors from web
  (`CanonicalControlPointsTests`, `RepeatingTaskCalculatorTests`, `AllDayTimezoneTests`, etc.).
  Mac runs the **same** shared tests — if a Mac change breaks a contract, these fail.
- **New contract — keyboard shortcuts.** The Mac bare-key scheme mirrors web
  `astrid-web/hooks/useKeyboardShortcuts.ts` (`KEYBOARD_SHORTCUTS`). Add a `KeyboardShortcutsParityTests`
  that asserts the Mac `KeyboardShortcuts` table matches the web set key-for-action, and add this row
  to the cross-platform contracts table in `ASTRID.md`. Changing a shortcut means changing **both**
  platforms in the same PR.

  | Contract | Canonical (web) | Mac mirror | Test |
  |---|---|---|---|
  | Keyboard shortcuts (bare-key scheme + input/modal guard) | `astrid-web/hooks/useKeyboardShortcuts.ts` (`KEYBOARD_SHORTCUTS`) | macOS `KeyboardShortcuts` table + bare-key handler | `KeyboardShortcutsParityTests` |
- **Docs are already single-source** (`ASTRID.md` owns architecture; `CLAUDE.md`/`AGENTS.md` are
  thin adapters). Add a short **"macOS shell"** section to `ASTRID.md` (Canonical Control Points
  already apply verbatim to Mac) rather than a separate Mac doc that could drift.

### 10.3 Testing
- Shared unit/contract tests run on **both** iOS and macOS destinations in CI (add a macOS test
  action to Xcode Cloud).
- Mac-only tests cover: command registry ↔ service wiring, palette search, quick-entry parsing,
  keyboard navigation, multi-select bulk fan-out.
- Snapshot/UI smoke test for the split-view shell.

### 10.4 CI / release
- Add a macOS build + test lane to Xcode Cloud alongside iOS.
- Direct build: automated notarize + staple + appcast publish step (mirrors the web deploy
  discipline — an explicit, approved release step, not automatic).

---

## 11. Delivery plan (phased)

| Milestone | Scope | Exit criteria |
|-----------|-------|---------------|
| **M0 · Spike (1 wk)** | Add macOS target; get `Core/` compiling on Mac behind the shim; decide package vs shared-membership; **prove global hotkey works in a sandboxed build**; prove OAuth + SSE + Outbox run on Mac. | App launches on Mac, loads real data offline, saves a task through the Outbox, global hotkey opens a window. |
| **M1 · Shell (1–2 wk)** | `NavigationSplitView` sidebar/content/detail; full menu bar; Settings scene; window restoration; reuse existing feature views. | Navigate lists/tasks/detail with mouse + keyboard; Settings works. |
| **M2 · Power (2–3 wk)** | ⌘K command palette; complete keyboard model; multi-select + bulk actions; drag-drop; `Table` multi-column view; quick-entry parsing. | A power user completes a full workflow mouse-free; 10k-task list scrolls at target fps. |
| **M3 · Distribution (1 wk)** | Two schemes/configs; entitlements; Sparkle for direct; notarization pipeline; App Store submission; macOS CI lane. | Both builds installable; auto-update works on direct; CI green on both platforms. |
| **v1.1** | Menu-bar extra; multi-window tear-off; Shortcuts/AppleScript; column presets. | — |

---

## 12. Risks & open questions

| Risk / question | Mitigation / decision needed |
|-----------------|------------------------------|
| Global hotkey under App Store sandbox | **De-risk in M0.** If `RegisterEventHotKey` is insufficient sandboxed, ship the hotkey in the direct build and a menu/Dock quick-add in the store build. |
| `Core/` package extraction cost | M0 decides package vs shared-membership; either way the `#if` isolation ships in v1. |
| SSE real-time client + auth-session on Mac | Verify in M0 (pure networking — expected to work unchanged). |
| App Groups with the iOS Share Extension | Decide if Mac needs a share/quick-capture extension (v1.1). |
| Swift 6 concurrency | Not required for v1; adopt incrementally. |
| Exact min-macOS numbers | Pin `MACOSX_DEPLOYMENT_TARGET` in M0. |

---

## 13. Success criteria

- **Native feel:** indistinguishable from a purpose-built Mac app (sidebar, menus, keyboard, windows).
- **Power:** a task can be captured, triaged, and completed without the mouse; 10k tasks scroll smoothly.
- **Maintenance:** a subsequent web→iOS shared change requires **zero or presentation-only** Mac edits,
  and the shared contract tests pass on both platforms.

---

## See also
- [ASTRID.md](../ASTRID.md) — architecture + Canonical Control Points (apply verbatim to Mac)
- [docs/LOCAL_FIRST_PATTERN.md](./LOCAL_FIRST_PATTERN.md) — Outbox / offline model the Mac app reuses
- [docs/SYNC_ARCHITECTURE.md](./SYNC_ARCHITECTURE.md) — external sync (shared, unchanged on Mac)
- [CLAUDE.md](../CLAUDE.md) — build/test/deploy adapter (add a macOS lane)
