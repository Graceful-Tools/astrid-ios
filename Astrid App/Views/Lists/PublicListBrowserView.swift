import SwiftUI

struct PublicListBrowserView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    @State private var publicLists: [TaskList] = []
    @State private var isLoading = false
    private let apiClient = RemoteResourceService.shared

    var body: some View {
        Group {
            if isLoading && publicLists.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Theme.accent)
            } else if publicLists.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle(NSLocalizedString("filters.featured_lists", comment: "Featured Lists"))
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(colorScheme == .dark ? Theme.Dark.headerBg : Theme.headerBg, for: .navigationBar)
        .task {
            await loadPublicLists()
        }
    }

    private var listContent: some View {
        List {
            ForEach(publicLists) { list in
                PublicListRow(list: list)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
    }

    private var emptyState: some View {
        ScrollView {
            EmptyStateView(
                message: NSLocalizedString("empty_state.public_list", comment: "")
            )
            .frame(minHeight: UIScreen.main.bounds.height - 200) // Ensure scrollable for pull-to-refresh
        }
        .refreshable {
            await loadPublicLists()
        }
    }

    private func loadPublicLists() async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("📡 [PublicListBrowserView] Fetching public lists...")
            let response = try await apiClient.getPublicLists(limit: 50, sortBy: "popular")

            // Convert PublicListData to TaskList (simplified conversion)
            publicLists = response.lists.map { listData in
                TaskList(
                    id: listData.id,
                    name: listData.name,
                    color: listData.color,
                    imageUrl: listData.imageUrl,
                    privacy: listData.privacy == "PUBLIC" ? .PUBLIC : .PRIVATE,
                    publicListType: listData.publicListType,
                    ownerId: listData.owner.id,
                    owner: User(
                        id: listData.owner.id,
                        email: listData.owner.email,
                        name: listData.owner.name,
                        image: listData.owner.image
                    ),
                    createdAt: listData.createdAt,
                    updatedAt: listData.updatedAt,
                    description: listData.description
                )
            }

            print("✅ [PublicListBrowserView] Fetched \(publicLists.count) public lists")
        } catch {
            print("❌ [PublicListBrowserView] Failed to fetch public lists: \(error)")
            // Fallback to local public lists
            publicLists = listService.lists.filter { $0.privacy == .PUBLIC }
        }
    }
}

struct PublicListRow: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    let list: TaskList
    @State private var isCopying = false
    @State private var selectedListId: String?
    @State private var isViewingFromFeatured = false
    @State private var featuredList: TaskList?
    @State private var navigateToList = false
    private let apiClient = RemoteResourceService.shared

    private var isCollaborative: Bool {
        list.publicListType == "collaborative"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
                HStack(spacing: Theme.spacing12) {
                    ListImageView(list: list, size: 16)

                    Text(list.name)
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundColor(Theme.accent)

                        if isCollaborative {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                if let description = list.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .lineLimit(2)
                }

                HStack {
                    if let taskCount = list.taskCount {
                        Label(String(format: NSLocalizedString("filters.tasks_count", comment: "Tasks count"), taskCount), systemImage: "checkmark.circle")
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }

                    Spacer()

                    if isCollaborative {
                        // Collaborative list - show "View" button
                        Button(NSLocalizedString("filters.view_add", comment: "View & Add")) {
                            // Set up navigation state
                            selectedListId = list.id
                            isViewingFromFeatured = true
                            featuredList = list
                            navigateToList = true
                        }
                        .font(Theme.Typography.caption1())
                        .foregroundColor(Theme.accent)
                    } else {
                        // Copy-only list - show "Copy" button
                        Button(isCopying ? "Copying..." : "Copy") {
                            _Concurrency.Task {
                                await copyList()
                            }
                        }
                        .font(Theme.Typography.caption1())
                        .foregroundColor(isCopying ? Theme.textSecondary : Theme.accent)
                        .disabled(isCopying)
                    }
                }
            }
            .padding(Theme.spacing16)
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .navigationDestination(isPresented: $navigateToList) {
                if isCollaborative {
                    TaskListView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList
                    )
                }
            }
    }

    private func copyList() async {
        isCopying = true
        defer { isCopying = false }

        do {
            print("📡 [PublicListBrowserView] Copying list: \(list.name)")
            let response = try await apiClient.copyList(listId: list.id, includeTasks: true)
            print("✅ List copied successfully: \(response.list.name)")
            print("✅ Copied \(response.copiedTasksCount) tasks")

            // Refresh lists to show the new copied list
            _ = try? await listService.fetchLists()
        } catch {
            print("❌ Failed to copy list: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        PublicListBrowserView()
    }
}
