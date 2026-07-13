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
        // iOS 17+: UNUserNotificationCenter.current().setBadgeCount — keep existing call site.
        UIApplication.shared.applicationIconBadgeNumber = count
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
