import SwiftUI

/// GitHub Issues sync settings: connect the account, link Astrid lists to
/// repos, and trigger a manual sync. Mirrors the Apple Reminders settings shape.
struct GitHubSyncSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var sync = GitHubSyncService.shared
    @StateObject private var listService = ListService.shared

    @State private var repos: [GitHubRepoDTO] = []
    @State private var selectedListId: String?
    @State private var selectedRepo: String?
    @State private var isLinking = false
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                if sync.isConnected {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text(sync.accountLogin.map { String(format: NSLocalizedString("sync.connected_as", comment: "Connected as X"), $0) } ?? NSLocalizedString("sync.connected", comment: "Connected"))
                        Spacer()
                        Button(NSLocalizedString("sync.disconnect", comment: "Disconnect"), role: .destructive) {
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
                                loadError = NSLocalizedString("sync.github_not_configured", comment: "GitHub sync not configured")
                            }
                        }
                    } label: {
                        Label(NSLocalizedString("sync.connect_github", comment: "Connect GitHub"), systemImage: "link")
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
                Text(Brand.localized("sync.github_footer"))
            }

            if sync.isConnected {
                Section(NSLocalizedString("sync.linked_lists", comment: "Linked lists")) {
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

                Section(NSLocalizedString("sync.link_list_repo", comment: "Link a list to a repo")) {
                    Picker(NSLocalizedString("sync.list", comment: "List"), selection: $selectedListId) {
                        Text(NSLocalizedString("sync.choose_list", comment: "Choose a list")).tag(String?.none)
                        ForEach(listService.lists.filter { !($0.isVirtual ?? false) && $0.listType != "status" }) { list in
                            Text(list.name).tag(String?.some(list.id))
                        }
                    }
                    Picker(NSLocalizedString("sync.repository", comment: "Repository"), selection: $selectedRepo) {
                        Text(NSLocalizedString("sync.choose_repo", comment: "Choose a repo")).tag(String?.none)
                        ForEach(repos) { repo in
                            Text(repo.name).tag(String?.some(repo.id))
                        }
                    }
                    Button(isLinking ? NSLocalizedString("sync.linking", comment: "Linking") : NSLocalizedString("sync.link", comment: "Link")) {
                        guard let listId = selectedListId, let repo = selectedRepo else { return }
                        isLinking = true
                        _Concurrency.Task {
                            defer { isLinking = false }
                            try? await sync.linkList(listId, repo: repo)
                            selectedListId = nil
                            selectedRepo = nil
                        }
                    }
                    .disabled(selectedListId == nil || selectedRepo == nil || isLinking)
                }

                Section {
                    Button {
                        _Concurrency.Task { await sync.syncAll() }
                    } label: {
                        HStack {
                            Label(NSLocalizedString("sync.sync_now", comment: "Sync now"), systemImage: "arrow.triangle.2.circlepath")
                            if sync.isSyncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing || sync.links.isEmpty)
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
        .navigationTitle("GitHub Issues")
        .task {
            await sync.refreshStatus()
            if sync.isConnected {
                repos = (try? await RemoteResourceService.shared.getGitHubRepos().repos) ?? []
            }
        }
        .refreshable {
            await sync.refreshStatus()
            if sync.isConnected {
                repos = (try? await RemoteResourceService.shared.getGitHubRepos().repos) ?? []
            }
        }
    }
}
