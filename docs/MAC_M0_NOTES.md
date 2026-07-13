# Astrid for Mac — M0 Spike Notes

*Foundation for the native Mac app. Companion to [MAC_APP_SPEC.md](./MAC_APP_SPEC.md).*
*Status: scaffolding landed; target-creation + runtime verification pending a Mac/Xcode session.*

M0 covers the three foundation tasks: (1) macOS target + shared `Core/` compiling, (2) the
platform shim for the 14 UIKit files, (3) de-risk the global hotkey and confirm OAuth/SSE/Outbox
run on Mac. This doc records the decisions and the exact remaining steps.

---

## What landed in this commit (code)

New folder **`Astrid Mac/`** — *not yet a member of any Xcode target*, so it does **not** affect
the iOS build (which is CI-only; local sim is broken). Files:

| File | Role | Milestone |
|------|------|-----------|
| `Astrid Mac/Platform/Platform.swift` | Shared shim: `PlatformImage`/`PlatformColor`, `PlatformApplication` (badge / settings / lifecycle notification), `Haptics`. | M0 |
| `Astrid Mac/Support/GlobalHotKey.swift` | `RegisterEventHotKey` (Carbon) wrapper — the sandbox de-risk artifact. | M0 |
| `Astrid Mac/Support/QuickEntryView.swift` | Quick-add window + `QuickEntryHotKeyController` (hotkey → window). | M0/M2 |
| `Astrid Mac/App/AstridMacApp.swift` | `@main` macOS scene graph (WindowGroup + `.commands` + Settings + Quick-Add window). | M1 |
| `Astrid Mac/App/MacRootView.swift` | `NavigationSplitView` sidebar/content/detail skeleton. | M1 |
| `Astrid Mac/App/AstridCommands.swift` | Menu bar + the two-layer keyboard model notes. | M1 |

> All macOS-only files are wrapped in `#if os(macOS)`; the shim uses `canImport(UIKit)`/`canImport(AppKit)`.
> SourceKit will show "cannot find X in scope" / "@main in top-level code" until these files are in
> the macOS target together — expected for un-targeted files, resolves on target creation.

---

## Decision 1 — Sharing model: **shared synchronized-group membership now, package later**

The project uses **Xcode 16 file-system-synchronized groups** (`PBXFileSystemSynchronizedRootGroup` ×6).
That makes the fast path clean:

- **Now (v1):** create a macOS app target and give it membership in the existing shared folders
  (`Astrid App/…` minus the iOS-only Bucket-B files, see below) **plus** the new `Astrid Mac/` folder.
  Synchronized groups mean folder-level membership, so this is mostly point-and-click, not pbxproj surgery.
- **Later (v1.1 hardening):** extract `Core/` into an **`AstridCore` Swift package with no UIKit in its
  API**, which makes "no platform logic in shared code" a *compiler error*. Deferred because extracting
  ~60K LOC is a larger lift than v1 needs, and the `#if os` isolation already ships the guarantee in code review.

Rationale: get a running Mac app fastest without forking logic; upgrade the enforcement mechanism later.

## Decision 2 — Keyboard scheme is a **contract mirrored from web** (not Mac ⌘ defaults)

Bare-key scheme from `astrid-web/hooks/useKeyboardShortcuts.ts` (`KEYBOARD_SHORTCUTS`) is canonical.
⌘-menu items are additive only. See MAC_APP_SPEC.md §7.1 and the `KeyboardShortcutsParityTests` contract (§10.2).

---

## Remaining M0 steps (need a Mac + Xcode — for whoever picks this up)

### A. Create the macOS target
1. Xcode → File → New → Target → **macOS App** ("Astrid Mac"), SwiftUI lifecycle.
2. Delete its generated `@main`/ContentView; instead add the `Astrid Mac/` folder as a synchronized
   group of this target (so `AstridMacApp.swift` provides `@main`).
3. Add the shared source folders to the macOS target's membership: everything the app needs from
   `Astrid App/` **except** the Bucket-B iOS-only files (below) and `AstridApp.swift` (iOS `@main`).
4. Add frameworks the shim/hotkey need: `AppKit`, `Carbon` (for `GlobalHotKey`), `StoreKit`, `EventKit`.
5. Set `MACOSX_DEPLOYMENT_TARGET` to the two-most-recent-majors floor (pin the number).
6. Build for "My Mac". Fix compile errors by applying the guard table below.

### B. Apply the platform guards to the 14 UIKit files

**Bucket A — shared, must compile on Mac (route through `Platform.swift`):**

| File | UIKit touchpoint | Fix |
|------|------------------|-----|
| `GoogleTasksSyncService.swift`, `GitHubSyncService.swift`, `AppleRemindersService.swift`, `FeatureFlagService.swift` | `UIApplication.didBecomeActiveNotification` | `PlatformApplication.didBecomeActiveNotification` |
| `NotificationPromptManager.swift` | `UIApplication.openSettingsURLString` + `.shared.open` | `PlatformApplication.openAppSettings()` |
| `BadgeManager.swift` | `applicationIconBadgeNumber` (+ `UNUserNotification`, cross-platform) | `PlatformApplication.setBadgeCount(_:)` |
| `ReviewPromptManager.swift` | `SKStoreReviewController` + `UIApplication.shared` | StoreKit is cross-platform; guard the `.shared` scene lookup |
| `AttachmentService.swift` | `import UIKit` (UIImage handling) | `PlatformImage`; audit the import |
| `TaskService.swift` | `import UIKit` (audit — likely background-task/scene) | guard iOS-only lifecycle; no logic change |
| `Utilities/ImageCache.swift` | `UIImage` | `PlatformImage` |

**Bucket B — iOS-only UX, EXCLUDE from the macOS target (replace natively per the spec):**
`Views/Components/UIKitWheelPicker.swift`, `Extensions/View+InteractivePopGesture.swift`,
`Extensions/View+TextEditorInsets.swift`, `Utilities/KeyboardEngineWarmer.swift`, and the 12
`UIImpactFeedback` haptic call sites (route through `Haptics` — no-op on Mac).

### C. Prove the runtime path (the actual de-risk)
1. **Global hotkey, sandboxed:** run the **App Store (sandboxed)** scheme, press ⌥Space from another
   app → the Quick Add window must appear. Repeat on the **direct** build. Record both results here.
   - If the sandboxed build fails to register: ship the hotkey in the direct build and a Dock/menu
     quick-add in the store build (documented fallback — MAC_APP_SPEC.md §12).
2. **OAuth:** sign in via `ASWebAuthenticationSession` on Mac; confirm `X-OAuth-Token` calls succeed.
3. **SSE + Outbox:** confirm the real-time client connects and a task created on Mac journals through
   the Outbox and reconciles (offline → online).

---

## Verified vs. pending (maps to the 3 M0 tasks)

| M0 task | Status |
|---------|--------|
| Add macOS target + Core/ compiling | Scaffolding + wiring plan ready (§A/§B). **Target creation + build pending** (Xcode/Mac). |
| Platform shim for the 14 UIKit files | Shim written (`Platform.swift`); per-file guard table ready (§B). **Applying guards + build pending.** |
| De-risk global hotkey + verify OAuth/SSE/Outbox | Hotkey code + quick-add flow written; test procedure defined (§C). **Runtime verification pending** (needs a running Mac build). |

**Bottom line:** everything that can be produced without a Mac build is done and reviewable. The
residual is inherently GUI/runtime work — create the target, apply the guards, press the hotkey.
Suitable to delegate alongside M1+.
