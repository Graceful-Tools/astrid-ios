//  MacAccountView.swift
//  Astrid for Mac — profile + account management (B1 + B2).
//
//  Profile display/edit, sign-out, and delete-account. All via the shared services
//  (AccountService / AuthManager). Shown in the Settings scene's Account tab.

#if os(macOS)
import SwiftUI

struct MacAccountView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var name = ""
    @State private var savedFlash = false
    @State private var showDelete = false

    var body: some View {
        Form {
            Section("Profile") {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading) {
                        Text(auth.currentUser?.displayName ?? "—").font(.headline)
                        Text(auth.currentUser?.email ?? "").font(.caption).foregroundStyle(Theme.textMuted)
                    }
                }
                TextField("Name", text: $name).onSubmit(saveName)
                if savedFlash { Text("Saved").font(.caption).foregroundStyle(Theme.success) }
            }

            Section {
                Button("Sign Out") { _Concurrency.Task { try? await auth.signOut() } }
            }

            Section("Danger Zone") {
                Button("Delete Account…", role: .destructive) { showDelete = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { name = auth.currentUser?.name ?? "" }
        .sheet(isPresented: $showDelete) { MacDeleteAccountSheet() }
    }

    @ViewBuilder private var avatar: some View {
        if let s = auth.currentUser?.image, let url = URL(string: s) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 44, height: 44).clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill").resizable().frame(width: 44, height: 44)
                .foregroundStyle(Theme.accent)
        }
    }

    private func saveName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != auth.currentUser?.name else { return }
        MacActions.perform("Update name") {
            _ = try await AccountService.shared.updateAccount(name: n, email: nil, image: nil)
            savedFlash = true
        }
    }
}

/// Delete-account confirmation — requires typing DELETE, then wipes + signs out.
struct MacDeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete Account").font(.headline).foregroundStyle(Theme.error)
            Text("This permanently deletes your account and all data. This cannot be undone.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            TextField("Type DELETE to confirm", text: $confirm).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
                Button("Delete Account", role: .destructive, action: delete)
                    .buttonStyle(.borderedProminent).tint(Theme.error)
                    .disabled(confirm != "DELETE" || working)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func delete() {
        working = true
        MacActions.perform("Delete account") {
            defer { working = false }
            try await AccountService.shared.deleteAccount(confirmationText: confirm)
            try? await AuthManager.shared.signOut()
            dismiss()
        }
    }
}
#endif
