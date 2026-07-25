//  MacAccountView.swift
//  Astrid for Mac — profile + account management (B1 + B2).
//
//  Profile display/edit, sign-out, and delete-account. All via the shared services
//  (AccountService / AuthManager). Shown in the Settings scene's Account tab.

#if os(macOS)
import SwiftUI
import AppKit

struct MacAccountView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var name = ""
    @State private var savedFlash = false
    @State private var showDelete = false
    @State private var isExporting = false

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

            Section("Your Data") {
                Menu {
                    Button("Export as JSON") { export(format: "json") }
                    Button("Export as CSV") { export(format: "csv") }
                } label: {
                    HStack { Label("Export Data…", systemImage: "square.and.arrow.up")
                        if isExporting { Spacer(); ProgressView().controlSize(.small) } }
                }
                .disabled(isExporting)
            }

            Section {
                Button("Sign Out") { _Concurrency.Task { try? await auth.signOut() } }
            }

            Section("Danger Zone") {
                Button("Delete Account…", role: .destructive) { showDelete = true }
            }
        }
        .formStyle(.grouped).macThemedSurface()
        .frame(width: 460)
        .onAppear { name = auth.currentUser?.name ?? "" }
        .sheet(isPresented: $showDelete) { MacDeleteAccountSheet() }
    }

    /// Fetch the account export from the shared service, then save it via an NSSavePanel.
    private func export(format: String) {
        isExporting = true
        MacActions.perform("Export data") {
            defer { isExporting = false }
            let data = try await AccountService.shared.exportAccountData(format: format)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = MacDataExport.fileName(format: format, date: Date())
            panel.allowedContentTypes = [MacDataExport.contentType(format: format)]
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        }
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
        .background(Theme.bgPrimary)
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
