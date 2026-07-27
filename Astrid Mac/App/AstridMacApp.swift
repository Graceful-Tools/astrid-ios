//  AstridMacApp.swift
//  Astrid for Mac — app shell skeleton (M0)
//
//  macOS entry point. Replaces the iOS `WindowGroup → MainTabView` shell (AstridApp.swift)
//  with a Mac-native scene graph. Business/feature views are REUSED from the shared source;
//  only the container and chrome are new. Wire the shared app-state / service objects here
//  the same way AstridApp.swift injects them on iOS (see the TODOs).
//
//  Guarded by `#if os(macOS)` so it is inert if ever compiled for iOS (avoids a second @main).
//  Not yet a member of any target — the macOS target is created in Xcode (see docs/MAC_M0_NOTES.md).

#if os(macOS)
import SwiftUI

@main
struct AstridMacApp: App {

    init() {
        // Under XCTest the app is the unit-test host; skip launch side-effects entirely (Task 90fa7975).
        guard !MacRuntime.isRunningTests else { return }
        // Make remote feature flags eligible to refresh this launch (mirrors AstridApp.swift).
        // Without this, refreshIfStale short-circuits and the Mac never honors remote rollouts.
        FeatureFlagService.recordAppLaunch()
    }

    // Under XCTest, keep every scene's CONTENT inert (SceneBuilder can't take control flow, so we
    // gate at the view level). This makes the unit-test host launch fast + reliable instead of
    // spinning up the auth gate / menu-bar / quick-add UI, which made the CLI/CI suite hang (90fa7975).
    private var underTest: Bool { MacRuntime.isRunningTests }

    var body: some Scene {
        // Main window: auth gate → sign-in when signed out, shell when signed in.
        WindowGroup(id: "main") {
            if underTest {
                Color.clear.frame(width: 1, height: 1)
            } else {
                MacAuthGateView()
                    .onAppear { Self.normalizeWindowForUITestingIfNeeded() }
            }
        }
        .commands { AstridCommands() }              // full menu bar (M1)

        // Menu-bar extra: glanceable tasks + quick add (v1.1).
        MenuBarExtra(Brand.appName, systemImage: "checklist") {
            if !underTest { MacMenuBarView() }
        }
        .menuBarExtraStyle(.window)

        // ⌘, Settings — native Mac settings wired to the shared settings services.
        Settings {
            if !underTest { MacSettingsView() }
        }

        // Global quick-entry target window (M0 de-risk / M2).
        Window("Quick Add", id: QuickEntryHotKeyController.windowID) {
            if !underTest { QuickEntryView() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Tear-off: open a single task in its own window (v1.1).
        WindowGroup(id: "task", for: String.self) { $taskId in
            if !underTest { MacTaskWindowView(taskId: taskId) }
        }
    }

    /// UI tests restore whatever window frame the last run saved — which can be TALLER than the
    /// screen, leaving bottom UI (quick-add) off-screen and "not hittable". Clamp the main window
    /// to the visible screen and bring it frontmost so XCUITest coordinates are always on-screen.
    private static func normalizeWindowForUITestingIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        DispatchQueue.main.async {
            guard let win = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
            let vis = win.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let w = min(1100, vis.width), h = min(760, vis.height)
            win.setFrame(NSRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h),
                         display: true)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }
}
#endif
