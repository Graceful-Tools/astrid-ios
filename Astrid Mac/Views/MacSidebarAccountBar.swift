//  MacSidebarAccountBar.swift
//  Astrid for Mac — account + settings at the bottom-left of the sidebar (Mac UI mapping).
//  Mirrors the iOS profile row (avatar + name + email) but anchored at the bottom per the
//  Mac layout: the user card on the left, a settings/profile/sign-out menu on the right.

#if os(macOS)
import SwiftUI
import AppKit

struct MacSidebarAccountBar: View {
    @StateObject private var auth = AuthManager.shared
    /// OBSERVED, not read from the cached global (AITD-307). This view otherwise depends only on
    /// AuthManager, so without this its body never re-runs on a theme change and the footer keeps
    /// whatever colour it painted first — which is what "white in all themes" was.
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @State private var profileTarget: MacProfileTarget?   // the gear menu's Profile → your profile

    var body: some View {
        HStack(spacing: 10) {
            // Your photo and name open Settings, as web's user menu does (AITD-493). The profile
            // they used to open is in the gear's menu.
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
            Menu {
                // `SettingsLink` is the supported way to open Settings (macOS 14+). The old
                // NSApp.sendAction(Selector("showSettingsWindow:")) relied on a private selector
                // travelling the responder chain, and from a Menu in the sidebar it did nothing —
                // the gear looked dead (task 32a1a10c).
                SettingsLink { Text(NSLocalizedString("settings", comment: "")) }
                if let userId = MacProfileLink.ownUserId(auth.currentUser) {
                    Button(NSLocalizedString("profile.title", comment: "")) {
                        profileTarget = MacProfileTarget(id: userId)
                    }
                }
                Divider()
                Button(NSLocalizedString("sign_out", comment: "")) { _Concurrency.Task { try? await auth.signOut() } }
                    .accessibilityIdentifier("account.destructive.signOut")
            } label: {
                Image(systemName: "gearshape").foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help(NSLocalizedString("mac.account_settings", comment: ""))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // The same strip the container behind it paints, from the same definition and from a mode
        // this view observes — `Theme.bgPrimary` would resolve through a cache nothing here reads
        // again (AITD-307).
        .background(MacSidebarChrome.background(mode: themeMode.rawValue))
        .sheet(item: $profileTarget) { target in MacUserProfileView(userId: target.id) }
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
