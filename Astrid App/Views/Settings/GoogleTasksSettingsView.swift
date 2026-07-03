import SwiftUI

/// GitHub Issues sync settings: connect the account, link Astrid lists to
/// Google Tasks lists, and trigger a manual sync. Mirrors the Apple Reminders settings shape.
struct GoogleTasksSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var sync = GoogleTasksSyncService.shared
    @StateObject private var listService = ListService.shared

    @State private var tasklists: [GoogleTasklistDTO] = []
    @State private var selectedListId: String?
    @State private var selectedTasklist: String?
    @State private var isLinking = false
    @State private var suffixDraft = ""

    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                if sync.isConnected {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text(sync.accountEmail.map { "Connected as \($0)" } ?? "Connected")
                        Spacer()
                        Button("Disconnect", role: .destructive) {
                            _Concurrency.Task { await sync.disconnect() }
                        }
                        .font(Theme.Typography.caption1())
                    }
                } else {
                    Button {
                        _Concurrency.Task {
                            if let url = await sync.authorizeURL() {
                                openURL(url)
                            } else {
                                loadError = "Google Tasks sync isn't configured on the server yet."
                            }
                        }
                    } label: {
                        Label("Connect Google", systemImage: "link")
                    }
                    if let loadError {
                        Text(loadError)
                            .font(Theme.Typography.caption2())
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Tasks in linked Google lists mirror to Astrid tasks (and back), including sub tasks. Google due dates are date-only; times stay in Astrid. Your Google token never leaves the server.")
            }

            if sync.isConnected {
                Section {
                    Picker("Mode", selection: Binding(
                        get: { sync.syncMode },
                        set: { mode in
                            _Concurrency.Task { await sync.setSyncMode(mode, suffix: suffixDraft) }
                        }
                    )) {
                        Text("Linked lists only").tag(GoogleSyncMode.manual)
                        Text("All Google lists → Astrid").tag(GoogleSyncMode.allGoogleToAstrid)
                        Text("All Astrid lists → Google").tag(GoogleSyncMode.allAstridToGoogle)
                    }
                    if sync.syncMode == .allGoogleToAstrid {
                        HStack {
                            TextField("List name suffix, e.g. [GT]", text: $suffixDraft)
                                .font(Theme.Typography.body())
                                .autocorrectionDisabled()
                            if suffixDraft != sync.listSuffix {
                                Button("Save") {
                                    _Concurrency.Task { await sync.setSyncMode(sync.syncMode, suffix: suffixDraft) }
                                }
                                .font(Theme.Typography.caption1())
                            }
                        }
                    }
                } header: {
                    Text("Sync mode")
                } footer: {
                    switch sync.syncMode {
                    case .manual:
                        Text("Only the lists you link below stay in sync.")
                    case .allGoogleToAstrid:
                        Text("Every Google Tasks list mirrors into Astrid — new Google lists are picked up automatically and named with the suffix. Existing same-name Astrid lists are adopted, not duplicated.")
                    case .allAstridToGoogle:
                        Text("Every Astrid list mirrors to Google Tasks as a backup — new Astrid lists are picked up automatically.")
                    }
                }

                Section("Linked lists") {
                    ForEach(sync.links) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(listService.lists.first { $0.id == link.astridListId }?.name ?? link.astridListId)
                                    .font(Theme.Typography.body())
                                Text(link.remoteContainerId)
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Unlink", role: .destructive) {
                                _Concurrency.Task { await sync.unlink(link.id) }
                            }
                            .font(Theme.Typography.caption1())
                        }
                    }
                    if sync.links.isEmpty {
                        Text("No lists linked yet.")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.secondary)
                    }
                }

                Section("Link a list to a Google Tasks list") {
                    Picker("List", selection: $selectedListId) {
                        Text("Choose a list").tag(String?.none)
                        ForEach(listService.lists.filter { !($0.isVirtual ?? false) && $0.listType != "status" }) { list in
                            Text(list.name).tag(String?.some(list.id))
                        }
                    }
                    Picker("Google list", selection: $selectedTasklist) {
                        Text("Choose a Google list").tag(String?.none)
                        ForEach(tasklists) { repo in
                            Text(repo.name).tag(String?.some(repo.id))
                        }
                    }
                    Button(isLinking ? "Linking…" : "Link") {
                        guard let listId = selectedListId, let repo = selectedTasklist else { return }
                        isLinking = true
                        _Concurrency.Task {
                            defer { isLinking = false }
                            try? await sync.linkList(listId, tasklistId: repo)
                            selectedListId = nil
                            selectedTasklist = nil
                        }
                    }
                    .disabled(selectedListId == nil || selectedTasklist == nil || isLinking)
                }

                Section {
                    Button {
                        _Concurrency.Task { await sync.syncAll() }
                    } label: {
                        HStack {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            if sync.isSyncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing || sync.links.isEmpty)
                    if let at = sync.lastSyncedAt {
                        Text("Last synced \(at.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.Typography.caption2())
                            .foregroundColor(.secondary)
                    }
                    if let err = sync.lastError {
                        Text(err)
                            .font(Theme.Typography.caption2())
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle("Google Tasks")
        .task {
            await sync.refreshStatus()
            suffixDraft = sync.listSuffix
            await loadTasklists()
        }
        .refreshable {
            await sync.refreshStatus()
            await loadTasklists()
        }
    }

    /// Load the account's tasklists, surfacing failures (a silent empty picker
    /// hid Tasks-API-disabled / expired-token errors).
    private func loadTasklists() async {
        guard sync.isConnected else { return }
        do {
            tasklists = try await AstridAPIClient.shared.getGoogleTasklists().tasklists
            if tasklists.isEmpty {
                sync.lastError = "Google returned no task lists for this account."
            }
        } catch {
            sync.lastError = "Couldn't load Google task lists: \(error.localizedDescription)"
        }
    }
}
