//  MacSidebarAccountBar.swift
//  Astrid for Mac — account + settings at the bottom-left of the sidebar (Mac UI mapping).
//  Mirrors the iOS profile row (avatar + name + email) but anchored at the bottom per the
//  Mac layout: profile on the left, a settings/sign-out menu on the right.

#if os(macOS)
import SwiftUI
import AppKit

struct MacSidebarAccountBar: View {
    @StateObject private var auth = AuthManager.shared

    var body: some View {
        HStack(spacing: 10) {
            avatar.frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(auth.currentUser?.displayName ?? "Account")
                    .font(.callout).foregroundStyle(Theme.textPrimary).lineLimit(1)
                if let email = auth.currentUser?.email, !email.isEmpty {
                    Text(email).font(.caption2).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Divider()
                Button("Sign Out") { _Concurrency.Task { try? await auth.signOut() } }
            } label: {
                Image(systemName: "gearshape").foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Account & Settings")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
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
                .font(.caption).bold().foregroundStyle(.white))
    }
}
#endif
