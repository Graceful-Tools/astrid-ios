import SwiftUI

/// GitHub Issues sync settings: connect the account, link Astrid lists to
/// Google Tasks lists, and trigger a manual sync. Mirrors the Apple Reminders settings shape.
struct GoogleTasksSettingsView: View {
    private static let newAstridListSelection = "__new_astrid_list__"
    private static let newGoogleTasklistSelection = "__new_google_tasklist__"

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var sync = GoogleTasksSyncService.shared
    @StateObject private var listService = ListService.shared
    @StateObject private var featureFlags = FeatureFlagService.shared

    @State private var tasklists: [GoogleTasklistDTO] = []
    @State private var selectedListId: String?
    @State private var selectedTasklist: String?
    @State private var isLinking = false
    @State private var suffixDraft = ""

    @State private var loadError: String?

    var body: some View {
        Group {
            if featureFlags.isEnabled(.googleTasks) {
                List {
            Section {
                if sync.isConnected {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text(sync.accountEmail.map { String(format: NSLocalizedString("sync.connected_as", comment: "Connected as X"), $0) } ?? NSLocalizedString("sync.connected", comment: "Connected"))
                        Spacer()
                        Button(NSLocalizedString("sync.disconnect", comment: "Disconnect"), role: .destructive) {
                            _Concurrency.Task { await sync.disconnect() }
                        }
                        .font(Theme.Typography.caption1())
                    }
                } else {
                    Button {
                        _Concurrency.Task {
                            do {
                                // In-app auth session; auto-returns to the app on the callback (task 6745f40f).
                                try await sync.connect()
                            } catch is CancellationError {
                                loadError = NSLocalizedString("sync.google_not_configured", comment: "Google sync not configured")
                            } catch {
                                loadError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("sync.connect_google", comment: "Connect Google"), systemImage: "link")
                    }
                    if let loadError {
                        Text(loadError)
                            .font(Theme.Typography.caption2())
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text(NSLocalizedString("sync.account", comment: "Account"))
            } footer: {
                Text(NSLocalizedString("sync.google_footer", comment: "Google sync footer"))
            }

            if sync.isConnected {
                Section {
                    Picker(NSLocalizedString("sync.mode", comment: "Mode"), selection: Binding(
                        get: { sync.syncMode },
                        set: { mode in
                            _Concurrency.Task { await sync.setSyncMode(mode, suffix: suffixDraft) }
                        }
                    )) {
                        Text(NSLocalizedString("sync.mode_manual", comment: "Linked lists only")).tag(GoogleSyncMode.manual)
                        Text(NSLocalizedString("sync.mode_google_to_astrid", comment: "All Google lists to Astrid")).tag(GoogleSyncMode.allGoogleToAstrid)
                        Text(NSLocalizedString("sync.mode_astrid_to_google", comment: "All Astrid lists to Google")).tag(GoogleSyncMode.allAstridToGoogle)
                        Text(NSLocalizedString("sync.mode_bidirectional", comment: "All lists, both directions")).tag(GoogleSyncMode.allBidirectional)
                    }
                    if sync.syncMode == .allGoogleToAstrid || sync.syncMode == .allBidirectional {
                        HStack {
                            TextField(NSLocalizedString("sync.suffix_placeholder", comment: "List name suffix"), text: $suffixDraft)
                                .font(Theme.Typography.body())
                                .autocorrectionDisabled()
                            if suffixDraft != sync.listSuffix {
                                Button(NSLocalizedString("actions.save", comment: "Save")) {
                                    _Concurrency.Task { await sync.setSyncMode(sync.syncMode, suffix: suffixDraft) }
                                }
                                .font(Theme.Typography.caption1())
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("sync.sync_mode", comment: "Sync mode"))
                } footer: {
                    switch sync.syncMode {
                    case .manual:
                        Text(NSLocalizedString("sync.mode_footer_manual", comment: "Manual mode footer"))
                    case .allGoogleToAstrid:
                        Text(NSLocalizedString("sync.mode_footer_google_to_astrid", comment: "Google to Astrid mode footer"))
                    case .allAstridToGoogle:
                        Text(NSLocalizedString("sync.mode_footer_astrid_to_google", comment: "Astrid to Google mode footer"))
                    case .allBidirectional:
                        Text(NSLocalizedString("sync.mode_footer_bidirectional", comment: "Bidirectional mode footer"))
                    }
                }

                Section(NSLocalizedString("sync.linked_lists", comment: "Linked lists")) {
                    ForEach(sync.links) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(listService.lists.first { $0.id == link.astridListId }?.name ?? link.astridListId)
                                    .font(Theme.Typography.body())
                                Text(googleTasklistDisplayName(for: link))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(NSLocalizedString("sync.unlink", comment: "Unlink"), role: .destructive) {
                                _Concurrency.Task { await sync.unlink(link.id) }
                            }
                            .font(Theme.Typography.caption1())
                        }
                    }
                    if sync.links.isEmpty {
                        Text(NSLocalizedString("sync.no_lists_linked", comment: "No lists linked yet"))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.secondary)
                    }
                }

                Section(NSLocalizedString("sync.link_list_tasklist", comment: "Link a list to a Google Tasks list")) {
                    Picker(NSLocalizedString("sync.list", comment: "List"), selection: $selectedListId) {
                        Text(NSLocalizedString("sync.choose_list", comment: "Choose a list")).tag(String?.none)
                        Text(NSLocalizedString("sync.new_list", comment: "New List")).tag(String?.some(Self.newAstridListSelection))
                        ForEach(listService.lists.filter { !($0.isVirtual ?? false) && $0.listType != "status" }) { list in
                            Text(list.name).tag(String?.some(list.id))
                        }
                    }
                    Picker(NSLocalizedString("sync.google_list", comment: "Google list"), selection: $selectedTasklist) {
                        Text(NSLocalizedString("sync.choose_google_list", comment: "Choose a Google list")).tag(String?.none)
                        Text(NSLocalizedString("sync.new_list", comment: "New List")).tag(String?.some(Self.newGoogleTasklistSelection))
                        ForEach(tasklists) { tasklist in
                            Text(tasklist.name).tag(String?.some(tasklist.id))
                        }
                    }
                    Button(isLinking ? NSLocalizedString("sync.linking", comment: "Linking") : NSLocalizedString("sync.link", comment: "Link")) {
                        guard let listId = selectedListId, let tasklistId = selectedTasklist else { return }
                        isLinking = true
                        _Concurrency.Task {
                            defer { isLinking = false }
                            await linkSelectedPair(listId: listId, tasklistId: tasklistId)
                            selectedListId = nil
                            selectedTasklist = nil
                        }
                    }
                    .disabled(!canLinkSelectedPair || isLinking)
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
                    .disabled(sync.isSyncing || (sync.links.isEmpty && sync.syncMode == .manual))
                    if let at = sync.lastSyncedAt {
                        Text(String(format: NSLocalizedString("sync.last_synced", comment: "Last synced X"), at.formatted(date: .omitted, time: .shortened)))
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
            } else {
                ContentUnavailableView(
                    "Google Tasks unavailable",
                    systemImage: "lock",
                    description: Text("This feature is not enabled for your account.")
                )
            }
        }
        .navigationTitle("Google Tasks")
        .task {
            guard featureFlags.isEnabled(.googleTasks) else { return }
            await sync.refreshStatus()
            suffixDraft = sync.listSuffix
            await loadTasklists()
        }
        .refreshable {
            guard featureFlags.isEnabled(.googleTasks) else { return }
            await sync.refreshStatus()
            await loadTasklists()
        }
    }

    /// Human name for a linked tasklist — never the opaque id.
    private func googleTasklistDisplayName(for link: ExternalListLinkDTO) -> String {
        if let live = tasklists.first(where: { $0.id == link.remoteContainerId })?.name {
            return live
        }
        if let stored = link.remoteContainerName, stored != link.remoteContainerId {
            return stored
        }
        return NSLocalizedString("sync.google_list", comment: "Google list")
    }

    /// Load the account's tasklists, surfacing failures (a silent empty picker
    /// hid Tasks-API-disabled / expired-token errors).
    private func loadTasklists() async {
        guard sync.isConnected else { return }
        do {
            tasklists = try await RemoteResourceService.shared.getGoogleTasklists().tasklists
            if tasklists.isEmpty {
                sync.lastError = "Google returned no task lists for this account."
            }
        } catch {
            sync.lastError = "Couldn't load Google task lists: \(error.localizedDescription)"
        }
    }

    private var canLinkSelectedPair: Bool {
        guard let listId = selectedListId, let tasklistId = selectedTasklist else { return false }
        return !(listId == Self.newAstridListSelection && tasklistId == Self.newGoogleTasklistSelection)
    }

    private func linkSelectedPair(listId: String, tasklistId: String) async {
        do {
            if listId == Self.newAstridListSelection {
                guard let tasklist = tasklists.first(where: { $0.id == tasklistId }) else { return }
                try await sync.createAstridListAndLink(tasklistId: tasklist.id, tasklistName: tasklist.name)
            } else if tasklistId == Self.newGoogleTasklistSelection {
                guard let list = listService.lists.first(where: { $0.id == listId }) else { return }
                let created = try await sync.createGoogleTasklistAndLink(listId: list.id, listName: list.name)
                if !tasklists.contains(where: { $0.id == created.id }) {
                    tasklists.append(created)
                }
            } else {
                try await sync.linkList(listId, tasklistId: tasklistId)
            }
            await loadTasklists()
        } catch {
            sync.lastError = "Couldn't link Google list: \(error.localizedDescription)"
        }
    }
}
