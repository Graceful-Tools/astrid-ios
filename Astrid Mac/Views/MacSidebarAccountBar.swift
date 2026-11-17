//  MacSidebarAccountBar.swift
//  Astrid for Mac — account + settings at the bottom-left of the sidebar (Mac UI mapping).
//  Mirrors the iOS profile row (avatar + name + email) but anchored at the bottom per the
//  Mac layout: the user card on the left, the Settings gear on the right (ADEV-78: no menu).

#if os(macOS)
import SwiftUI
import AppKit

struct MacSidebarAccountBar: View {
    @StateObject private var auth = AuthManager.shared
    /// OBSERVED, not read from the cached global (AITD-307). This view otherwise depends only on
    /// AuthManager, so without this its body never re-runs on a theme change and the footer keeps
    /// whatever colour it painted first — which is what "white in all themes" was.
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    var body: some View {
        HStack(spacing: 10) {
            // Your photo and name open Settings, as web's user menu does (AITD-493), and so does
            // the gear; your profile is in Settings ▸ Account (ADEV-78).
            SettingsLink {
                HStack(spacing: 10) {
                    avatar.frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(auth.currentUser?.displayName ?? NSLocalizedString("account", comment: ""))
                            .macFont(.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        if let email = auth.currentUser?.email, !email.isEmpty {
                            Text(email).macFont(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macPointingHand()
            .help(NSLocalizedString("settings", comment: ""))
            .accessibilityIdentifier("mac.sidebar.userCard")
            Spacer(minLength: 4)
            // The gear opens Settings — no menu, no chevron (ADEV-78). Your profile and Sign Out
            // are in Settings ▸ Account. `SettingsLink` is the supported way to open Settings
            // (macOS 14+); a private `showSettingsWindow:` selector did nothing from here (32a1a10c).
            SettingsLink {
                Image(systemName: "gearshape").foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macPointingHand()
            .accessibilityLabel(NSLocalizedString("settings", comment: ""))
            .accessibilityIdentifier("mac.sidebar.settings")
            .help(NSLocalizedString("mac.account_settings", comment: ""))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // The same strip the container behind it paints, from the same definition and from a mode
        // this view observes — `Theme.bgPrimary` would resolve through a cache nothing here reads
        // again (AITD-307).
        .background(MacSidebarChrome.background(mode: themeMode.rawValue))
    }

    @ViewBuilder private var avatar: some View {
        if let image = auth.currentUser?.image, !image.isEmpty, let url = URL(string: image) {
            CachedAsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                initialsCircle
            }
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        Circle().fill(Theme.accent)
            .overlay(Text(auth.currentUser?.initials ?? "?")
                .macFont(.caption).bold().foregroundStyle(.white))
    }
}
#endif
