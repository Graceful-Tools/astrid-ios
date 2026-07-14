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

### A. Create the macOS target (one-time, in Xcode)
1. **New target:** File → New → Target → **macOS · App**. Product Name **`Astrid Mac`**, SwiftUI
   lifecycle, Swift. (Xcode derives the module name **`Astrid_Mac`** — this MUST match
   `@testable import Astrid_Mac` in `KeyboardShortcutsParityTests.swift`. If you name it
   differently, tell me and I'll update the import.)
2. **Delete the generated `ContentView.swift` + `<name>App.swift`** — the shell's `@main` comes from
   `Astrid Mac/App/AstridMacApp.swift`.
3. **Add `Astrid Mac/` to the target:** drag the `Astrid Mac/` folder in as a *file-system-synchronized
   group* of the macOS target. This pulls in the shell, Platform shim, GlobalHotKey, QuickEntry, and
   the KeyboardShortcuts table.
4. **Share the existing code:** give the macOS target membership in the `Astrid App` synchronized group,
   then add **membership exceptions** (Xcode 16 synchronized-group feature) to EXCLUDE:
   - `AstridApp.swift` (that's the iOS `@main`), `Views/MainTabView.swift`, and the **Bucket-B**
     iOS-only files (see §B). Everything else (Models, Core/*, most Views, Utilities, Extensions) is shared.
5. **Link frameworks** the shim/hotkey need: `Carbon` (GlobalHotKey), `StoreKit`, `EventKit`
   (AppKit/SwiftUI are implicit).
6. **Set `MACOSX_DEPLOYMENT_TARGET`** to the two-most-recent-majors floor (pin the number). Add a
   dev signing identity so it builds.
7. **Build "My Mac".** Fix compile errors by applying the Bucket-A guard table (§B) — that's the
   expected, mechanical work. Ping me and I'll apply the guards as reviewed edits once CI can verify them.

### A′. Create the macOS test target + CI lane
1. File → New → Target → **macOS · Unit Testing Bundle** named **`Astrid MacTests`**, host app `Astrid Mac`.
2. Add `Astrid Mac/Keyboard/KeyboardShortcutsParityTests.swift` to it. Run ⌘U — the parity test must pass.
3. **Xcode Cloud:** add a workflow (or extend the existing one) that builds + tests the **`Astrid Mac`**
   scheme on a macOS destination, so `KeyboardShortcutsParityTests` (and future Mac tests) gate every push.

> **Note on the App Store build:** folding these into a real build changes the iOS/Mac binaries — bump
> `CURRENT_PROJECT_VERSION` again (currently 122, reserved for the in-flight 1.8.3 App Store submission)
> before the next upload. Don't reuse 122.

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
