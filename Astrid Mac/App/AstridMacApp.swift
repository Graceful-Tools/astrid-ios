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

    // TODO(M1): inject the SAME shared observable app-state / services the iOS app uses
    // (e.g. @StateObject private var appState = AppState()) — do NOT create Mac-only state.
    @StateObject private var hotKeyController = QuickEntryHotKeyController()

    var body: some Scene {
        // Main window: sidebar + content + detail (see MacRootView).
        WindowGroup(id: "main") {
            MacRootView()
                // .environmentObject(appState)
                .task { hotKeyController.registerIfNeeded() }
        }
        .commands { AstridCommands() }              // full menu bar (M1)

        // Menu-bar extra: glanceable tasks + quick add (v1.1).
        MenuBarExtra("Astrid", systemImage: "checklist") {
            MacMenuBarView()
        }
        .menuBarExtraStyle(.window)

        // ⌘, Settings — native Mac settings wired to the shared settings services.
        Settings {
            MacSettingsView()
        }

        // Global quick-entry target window (M0 de-risk / M2).
        Window("Quick Add", id: QuickEntryHotKeyController.windowID) {
            QuickEntryView()
                // .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Tear-off: open a single task in its own window (v1.1).
        WindowGroup(id: "task", for: String.self) { $taskId in
            MacTaskWindowView(taskId: taskId)
        }
    }
}
#endif
