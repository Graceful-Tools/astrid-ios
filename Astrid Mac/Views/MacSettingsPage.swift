//  MacSettingsPage.swift
//  Astrid for Mac — the one design for a settings surface (ADEV-395).
//
//  Jon, 2026-11-28: "Project Settings design is horrible … Doesn't respond to font size change,
//  width of the modal is wrong … Design of web settings is actually much, much better. Let's adapt
//  the web overall settings as a design standard and then apply it to list settings, project
//  settings, etc."
//
//  So this is web's settings page (`components/Settings/*`), drawn natively:
//
//  - a header: the page's icon, a bold title and one muted line saying what the page is for;
//  - one readable column (web's `max-w-2xl`), centred, that scrolls inside the window;
//  - titled cards on the secondary surface with a hairline border (web's `Card` with
//    `CardHeader` / `CardTitle` / `CardDescription` / `CardContent`);
//  - a label ABOVE each field, never a placeholder standing in for one;
//  - the actions in a bar pinned below the scroll, so Save never scrolls away.
//
//  Every font goes through `.macFont`, so View ▸ Bigger / Smaller reaches every word. The surface
//  is `Theme.bgPrimary` (white in Ocean, which Jon called fine for settings), carried by
//  `macThemedSurface()` so system-drawn controls stay legible on it.

#if os(macOS)
import SwiftUI

/// Sizes for a settings surface: the window and the column inside it. Pure, so it is tested.
enum MacSettingsLayout {
    /// The column's widest (web `max-w-2xl`, 42rem).
    static let columnMaxWidth: CGFloat = MacLayout.settingsColumnMaxWidth

    /// The window: the List Settings size (AITD-553: wider where there is room, tall enough for
    /// the longest tab), so every settings window is one size and not each its own guess.
    static func windowSize(screen: CGSize) -> CGSize {
        MacListChrome.settingsPopoverSize(screen: screen)
    }

    static var windowSize: CGSize {
        windowSize(screen: NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900))
    }
}

/// The page: header, scrolling column of cards, and a pinned action bar.
struct MacSettingsPage<Content: View, Actions: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing20) {
                MacSettingsHeader(systemImage: systemImage, title: title, subtitle: subtitle)
                content()
            }
            .frame(maxWidth: MacSettingsLayout.columnMaxWidth, alignment: .leading)
            .padding(Theme.spacing24)
            .frame(maxWidth: .infinity)
        }
        // The action bar sits below the scroll, never inside it, so Save never scrolls away.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Theme.spacing8) {
                Spacer()
                actions()
            }
            .padding(.horizontal, Theme.spacing24)
            .padding(.vertical, Theme.spacing12)
            .background(Theme.bgPrimary)
            .overlay(alignment: .top) { Divider() }
        }
        .macThemedSurface()
    }
}

/// The page's header: icon, title, and what the page is for.
struct MacSettingsHeader: View {
    let systemImage: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            Image(systemName: systemImage)
                .macFont(.title)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing2) {
                Text(title)
                    .macFont(.title2).bold()
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .macFont(.callout)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A titled card: what a group of settings is, a muted line about it, then its controls.
struct MacSettingsCard<Content: View>: View {
    var systemImage: String?
    let title: String
    var description: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Label {
                    Text(title).macFont(.headline).foregroundStyle(Theme.textPrimary)
                } icon: {
                    if let systemImage {
                        Image(systemName: systemImage).macFont(.headline).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityAddTraits(.isHeader)
                if let description, !description.isEmpty {
                    Text(description)
                        .macFont(.callout)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(Theme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
    }
}

/// A field with its label above it, in the Mac text size.
struct MacSettingsField<Content: View>: View {
    let label: String
    var help: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Text(label).macFont(.subheadline).bold().foregroundStyle(Theme.textSecondary)
            content()
            if let help, !help.isEmpty {
                Text(help).macFont(.caption).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
