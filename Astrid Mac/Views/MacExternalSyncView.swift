//  MacExternalSyncView.swift
//  Astrid for Mac — per-list external sync config for Google Tasks + GitHub (Task 7043e478).
//
//  The Sync tab only connected/disconnected the account. iOS links individual lists ↔ Google
//  tasklists / GitHub repos and sets a sync mode. These sheets do that over the SAME shared
//  GoogleTasksSyncService / GitHubSyncService — no new sync logic.

#if os(macOS)
import SwiftUI

/// Pure helpers (testable without services).
enum MacSyncLinks {
    static func link(_ links: [ExternalListLinkDTO], for listId: String) -> ExternalListLinkDTO? {
        links.first { $0.astridListId == listId }
    }
    static func googleModeLabel(_ m: GoogleSyncMode) -> String {
        switch m {
        case .manual:             return "Link lists manually"
        case .allGoogleToAstrid:  return "All Google → \(Brand.appName)"
        case .allAstridToGoogle:  return "All \(Brand.appName) → Google"
        case .allBidirectional:   return "Two-way (all lists)"
        }
    }
}

// MARK: - Google Tasks

struct MacGoogleTasksLinksView: View {
    @StateObject private var google = GoogleTasksSyncService.shared
    @StateObject private var listService = ListService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var suffix = ""

    private var realLists: [TaskList] { listService.lists.filter { $0.isVirtual != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Google Tasks")
            Form {
                Section(NSLocalizedString("sync.sync_mode", comment: "")) {
                    Picker(NSLocalizedString("sync.mode", comment: ""), selection: Binding(
                        get: { google.syncMode },
                        set: { newMode in _Concurrency.Task { await google.setSyncMode(newMode, suffix: suffix) } }
                    )) {
                        ForEach(GoogleSyncMode.allCases, id: \.self) { Text(MacSyncLinks.googleModeLabel($0)).tag($0) }
                    }
                    if google.syncMode != .manual {
                        TextField(NSLocalizedString("mac.name_suffix", comment: ""), text: $suffix)
                            .onSubmit { _Concurrency.Task { await google.setSyncMode(google.syncMode, suffix: suffix) } }
                    }
                }
                if google.syncMode == .manual {
                    Section(NSLocalizedString("reminders.linked_lists", comment: "")) {
                        ForEach(realLists) { list in
                            HStack {
                                Text(list.name)
                                Spacer()
                                if let l = MacSyncLinks.link(google.links, for: list.id) {
                                    Text(l.remoteContainerName ?? "Linked").foregroundStyle(Theme.textSecondary)
                                    Button(NSLocalizedString("reminders.unlink", comment: ""), role: .destructive) { _Concurrency.Task { await google.unlink(l.id) } }
                                } else {
                                    Button(NSLocalizedString("mac.create_and_link", comment: "")) {
                                        MacActions.perform("Link Google Tasks") {
                                            _ = try await google.createGoogleTasklistAndLink(listId: list.id, listName: list.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                syncNowSection(isSyncing: google.isSyncing, lastSync: google.lastSyncedAt) { await google.syncAll() }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 460, height: 480)
        .task { suffix = google.listSuffix; await google.refreshStatus() }
    }
}

// MARK: - GitHub

struct MacGitHubLinksView: View {
    @StateObject private var github = GitHubSyncService.shared
    @StateObject private var listService = ListService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var repoDrafts: [String: String] = [:]

    private var realLists: [TaskList] { listService.lists.filter { $0.isVirtual != true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("GitHub Issues")
            Form {
                Section(NSLocalizedString("reminders.linked_lists", comment: "")) {
                    ForEach(realLists) { list in
                        HStack {
                            Text(list.name)
                            Spacer()
                            if let l = MacSyncLinks.link(github.links, for: list.id) {
                                Text(l.remoteContainerName ?? "Linked").foregroundStyle(Theme.textSecondary)
                                Button(NSLocalizedString("reminders.unlink", comment: ""), role: .destructive) { _Concurrency.Task { await github.unlink(l.id) } }
                            } else {
                                TextField(NSLocalizedString("mac.owner_repo", comment: ""), text: Binding(
                                    get: { repoDrafts[list.id] ?? "" },
                                    set: { repoDrafts[list.id] = $0 }
                                )).frame(width: 130)
                                Button(NSLocalizedString("reminders.link", comment: "")) { linkGitHub(list) }
                                    .disabled((repoDrafts[list.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                syncNowSection(isSyncing: github.isSyncing, lastSync: github.lastSyncedAt) { await github.syncAll() }
            }
            .formStyle(.grouped).macThemedSurface()
        }
        .frame(width: 460, height: 460)
        .task { await github.refreshStatus() }
    }

    private func linkGitHub(_ list: TaskList) {
        let repo = (repoDrafts[list.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !repo.isEmpty else { return }
        MacActions.perform("Link GitHub repo") { try await github.linkList(list.id, repo: repo) }
    }
}

// MARK: - shared chrome

private extension View {
    func header(_ title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            DismissButton()
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
    }

    @ViewBuilder func syncNowSection(isSyncing: Bool, lastSync: Date?, sync: @escaping () async -> Void) -> some View {
        Section {
            Button {
                _Concurrency.Task { await sync() }
            } label: {
                HStack { Label(NSLocalizedString("sync_now", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                    if isSyncing { Spacer(); ProgressView().controlSize(.small) } }
            }
            .disabled(isSyncing)
            if let d = lastSync { LabeledContent("Last sync") { Text(d, style: .relative) } }
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return) }
}
#endif
