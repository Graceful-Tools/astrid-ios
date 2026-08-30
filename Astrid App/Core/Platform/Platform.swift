//  Platform.swift
//  Astrid — cross-platform shim (M0)
//
//  SHARED code. Intended final home: the shared source set compiled by BOTH the iOS
//  and macOS targets (e.g. move to `Astrid App/Core/Platform/` and give it membership in
//  both targets, or into the future `AstridCore` package). It lives under `Astrid Mac/`
//  for now only so it doesn't auto-join the iOS synchronized group before it's reviewed.
//
//  Rule: shared code must NEVER write raw `UIKit`/`AppKit`. Route platform differences
//  through this file so the 14 UIKit-coupled files (see docs/MAC_M0_NOTES.md) compile on
//  both platforms. No business logic here — presentation/platform glue only.

import Foundation
import SwiftUI
import AuthenticationServices
import UserNotifications

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#endif

/// App-level actions that differ per platform (badge, settings, review prompt, lifecycle).
public enum PlatformApplication {

    /// `UIApplication.didBecomeActiveNotification` ↔ `NSApplication.didBecomeActiveNotification`.
    public static var didBecomeActiveNotification: Notification.Name {
        #if canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #else
        return NSApplication.didBecomeActiveNotification
        #endif
    }

    /// Set the Dock / app-icon badge. Pass 0 to clear.
    public static func setBadgeCount(_ count: Int) {
        #if canImport(UIKit)
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error {
                print("❌ [PlatformApplication] Failed to set badge count: \(error)")
            }
        }
        #elseif canImport(AppKit)
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        #endif
    }

    /// Open this app's system settings pane.
    public static func openAppSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        // macOS has no per-app settings pane; open Notifications settings as the closest analog.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Open a URL in the default handler (browser, mail client, etc.).
    public static func open(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    /// Window to anchor ASAuthorization / ASWebAuthenticationSession UI to.
    @MainActor public static func presentationAnchor() -> ASPresentationAnchor {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window available")
        }
        return window
        #elseif canImport(AppKit)
        // Prefer a real, presentable window. `windows.first` is non-deterministic in a
        // multi-scene app (can be the menu-bar-extra/hidden window), and a throwaway
        // NSWindow() is never on screen — ASWebAuthenticationSession then fails to present
        // and its callback never fires, hanging sign-in. Pick key → main → first visible.
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeKey })
            ?? NSApplication.shared.windows.first(where: { $0.isVisible })
            ?? NSApplication.shared.windows.first
            ?? NSWindow()
        #endif
    }
}

public extension PlatformImage {
    /// PNG data on both platforms (UIImage.pngData / NSImage via bitmap representation).
    func pngDataCompat() -> Data? {
        #if canImport(UIKit)
        return pngData()
        #elseif canImport(AppKit)
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}

public extension Image {
    /// Cross-platform `Image(uiImage:)` / `Image(nsImage:)`.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Haptics: real on iOS, no-op on macOS (or NSHapticFeedbackManager where meaningful).
public enum Haptics {
    public enum Impact { case light, medium, heavy }
    public static func impact(_ style: Impact = .medium) {
        #if canImport(UIKit)
        let s: UIImpactFeedbackGenerator.FeedbackStyle = style == .light ? .light : style == .heavy ? .heavy : .medium
        UIImpactFeedbackGenerator(style: s).impactOccurred()
        #endif
    }
    public static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
