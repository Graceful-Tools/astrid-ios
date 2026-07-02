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
                        Text(sync.accountLogin.map { "Connected as \($0)" } ?? "Connected")
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
                                loadError = "GitHub sync isn't configured on the server yet."
                            }
                        }
                    } label: {
                        Label("Connect GitHub", systemImage: "link")
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
                Text("Issues in linked repos mirror to tasks (and back). Astrid stays the source of truth; your GitHub token never leaves the server.")
            }

            if sync.isConnected {
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

                Section("Link a list to a repo") {
                    Picker("List", selection: $selectedListId) {
                        Text("Choose a list").tag(String?.none)
                        ForEach(listService.lists.filter { !($0.isVirtual ?? false) && $0.listType != "status" }) { list in
                            Text(list.name).tag(String?.some(list.id))
                        }
                    }
                    Picker("Repository", selection: $selectedRepo) {
                        Text("Choose a repo").tag(String?.none)
                        ForEach(repos) { repo in
                            Text(repo.name).tag(String?.some(repo.id))
                        }
                    }
                    Button(isLinking ? "Linking…" : "Link") {
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
        .navigationTitle("GitHub Issues")
        .task {
            await sync.refreshStatus()
            if sync.isConnected {
                repos = (try? await AstridAPIClient.shared.getGitHubRepos().repos) ?? []
            }
        }
        .refreshable {
            await sync.refreshStatus()
            if sync.isConnected {
                repos = (try? await AstridAPIClient.shared.getGitHubRepos().repos) ?? []
            }
        }
    }
}
