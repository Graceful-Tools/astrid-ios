import SwiftUI

/// Inline assignee picker for selecting task assignee
struct InlineAssigneePicker: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var authManager: AuthManager

    let label: String
    @Binding var assigneeId: String?
    let taskListIds: [String]
    let taskId: String?
    let availableLists: [TaskList]
    let onSave: ((String?) async -> Void)?
    var showLabel: Bool = true
    /// Avatar only, no name and no chevron — tap to change (Task 42013da7).
    var compact: Bool = false

    @State private var isEditing = false
    // Initialize with cached agents to prevent flash on first render
    @State private var aiAgents: [User] = AIAgentCache.shared.load() ?? []
    @State private var isLoadingAgents = false

    // Get all unique members from task's lists, including AI agents
    private var availableMembers: [User] {
        var membersMap: [String: User] = [:]

        // Get lists that this task belongs to
        let taskLists = availableLists.filter { taskListIds.contains($0.id) }

        for list in taskLists {
            // Owner + listMembers are the canonical member sources.
            if let owner = list.owner {
                membersMap[owner.id] = owner
            }
            if let listMembers = list.listMembers {
                for listMember in listMembers {
                    if let user = listMember.user {
                        membersMap[user.id] = user
                    }
                }
            }
        }

        // Add AI agents fetched from API (based on user's configured API keys)
        for agent in aiAgents {
            membersMap[agent.id] = agent
        }

        // For tasks without lists (e.g., "My Tasks"), add current user
        if taskLists.isEmpty, let currentUser = authManager.currentUser {
            membersMap[currentUser.id] = currentUser
        }

        return Array(membersMap.values).sorted { u1, u2 in
            // Sort by: AI agents first, then current user, then alphabetically
            let u1IsAI = u1.isAIAgent == true
            let u2IsAI = u2.isAIAgent == true
            if u1IsAI && !u2IsAI { return true }
            if !u1IsAI && u2IsAI { return false }

            if let currentUser = authManager.currentUser {
                if u1.id == currentUser.id { return true }
                if u2.id == currentUser.id { return false }
            }

            // Stable sort: use name first, then ID as tiebreaker
            let name1 = (u1.name ?? u1.email ?? "")
            let name2 = (u2.name ?? u2.email ?? "")
            if name1 != name2 {
                return name1 < name2
            }
            return u1.id < u2.id
        }
    }

    // Fetch fresh AI agents from API (cache already loaded at init)
    private func fetchAIAgents() async {
        guard !isLoadingAgents else { return }

        // Only show loading indicator if we have no cached data
        if aiAgents.isEmpty {
            isLoadingAgents = true
        }

        // Fetch fresh data from API
        do {
            let users = try await RemoteResourceService.shared.searchUsersWithAIAgents(
                query: "",
                taskId: taskId,
                listIds: taskListIds.isEmpty ? nil : taskListIds
            )
            let agents = users.filter { $0.isAIAgent == true }

            // Check if agent set has changed (ignore order differences)
            let newAgentIds = Set(agents.map { $0.id })
            let currentAgentIds = Set(aiAgents.map { $0.id })
            let hasChanged = newAgentIds != currentAgentIds

            await MainActor.run {
                if hasChanged {
                    self.aiAgents = agents
                    // Cache AI agent images in UserImageCache for avatar display
                    for agent in agents {
                        UserImageCache.shared.cacheUser(agent)
                    }
                }
                self.isLoadingAgents = false
            }

            // Cache for offline use (only if changed)
            if hasChanged {
                AIAgentCache.shared.save(agents)
            }
        } catch {
            print("❌ [InlineAssigneePicker] Failed to fetch AI agents: \(error)")
            await MainActor.run {
                self.isLoadingAgents = false
            }
        }
    }

    // Find the current assignee User object from assigneeId
    private var currentAssignee: User? {
        guard let id = assigneeId else { return nil }
        return availableMembers.first { $0.id == id }
    }

    var body: some View {
        // Hide assignee picker for local-only users
        if authManager.isLocalOnlyMode {
            EmptyView()
        } else {
            pickerContent
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            if isEditing && !compact {
                editor
            } else {
                trigger
            }
        }
        // The compact trigger is a 26pt avatar; its editor belongs in a sheet, at the full width
        // the date picker's has always had (42013da7).
        .sheet(isPresented: Binding(get: { compact && isEditing },
                                    set: { isEditing = $0 })) {
            NavigationStack {
                ScrollView { editor.padding(Theme.spacing16) }
                    .navigationTitle(label)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var editor: some View {
                VStack(spacing: Theme.spacing12) {
                    // Unassigned option
                    assigneeOption(
                        id: nil,
                        name: "Unassigned",
                        email: nil,
                        image: nil,
                        icon: "person.slash",
                        isAIAgent: false
                    )

                    // Loading indicator for AI agents
                    if isLoadingAgents {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("picker.loading_agents", comment: "Loading AI agents..."))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                        .padding(.vertical, Theme.spacing8)
                    }

                    // Available members (includes AI agents)
                    ForEach(availableMembers) { member in
                        assigneeOption(
                            id: member.id,
                            name: member.displayName,
                            email: member.email,
                            image: member.image,
                            icon: nil,
                            isAIAgent: member.isAIAgent == true
                        )
                    }
                }
                .padding(compact ? 0 : Theme.spacing12)
                .background(compact ? Color.clear
                                    : (colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .task {
                    // Fetch AI agents when picker opens
                    await fetchAIAgents()
                }
    }

    @ViewBuilder private var trigger: some View {
                Button {
                    isEditing = true
                } label: {
                    HStack {
                        if compact {
                            // Avatar AND name (42013da7): a face alone is only recognisable if
                            // you already know it, and a shared list can hold people you do not.
                            if let assignee = currentAssignee {
                                HStack(spacing: Theme.spacing4) {
                                    CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Circle().fill(Theme.accent)
                                            Text(assignee.initials)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 26, height: 26)
                                    .clipShape(Circle())

                                    Text(assignee.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        .lineLimit(1)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(Text(assignee.displayName))
                            } else {
                                SlashedSymbol(systemName: "person",
                                              color: colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .frame(width: 26, height: 26)
                                    .accessibilityLabel(Text(NSLocalizedString("assignee.unassigned", comment: "")))
                            }
                        } else if let assignee = currentAssignee {
                            HStack(spacing: Theme.spacing8) {
                                // Avatar - use cachedImageURL to leverage UserImageCache
                                CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.accent)
                                        Text(assignee.initials)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())

                                Text(assignee.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            }
                        } else {
                            HStack(spacing: Theme.spacing8) {
                                Image(systemName: "person.slash")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                Text("Unassigned")
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        }
                        if !compact {
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                    .padding(.horizontal, compact ? Theme.spacing4 : Theme.spacing12)
                    .padding(.vertical, compact ? Theme.spacing4 : Theme.spacing12)
                    .background(compact ? Color.clear
                                        : (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
        // Note: aiAgents initialized from cache at declaration to prevent flash on first render
    }

    @ViewBuilder
    private func assigneeOption(id: String?, name: String, email: String?, image: String?, icon: String?, isAIAgent: Bool = false) -> some View {
        Button {
            // Optimistic update: Update binding immediately for instant UI feedback - no blocking "smooth as butter"
            assigneeId = id
            isEditing = false

            // Haptic feedback for immediate response
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            // Capture onSave before entering detached task (Swift 6 concurrency fix)
            let saveAction = onSave

            // Fire-and-forget save in background
            _Concurrency.Task.detached {
                if let saveAction = saveAction {
                    await saveAction(id)
                }
            }
        } label: {
            HStack(spacing: Theme.spacing12) {
                // Avatar or icon
                if let icon = icon {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                } else {
                    CachedAsyncImage(url: image.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Theme.accent)
                            // Compute initials: first+last initial if space exists, else first 2 chars
                            Text({
                                let components = name.split(separator: " ")
                                if components.count >= 2 {
                                    return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
                                } else {
                                    return String(name.prefix(2)).uppercased()
                                }
                            }())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    if let currentUser = authManager.currentUser, id == currentUser.id {
                        Text(NSLocalizedString("assignee.you", comment: "You"))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    } else if isAIAgent {
                        Text(NSLocalizedString("picker.ai_agent", comment: "AI Agent"))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                Spacer()

                if assigneeId == id {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, Theme.spacing8)
            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let mockList = TaskList(
        id: "list1",
        name: "Test List",
        owner: User(id: "user1", email: "owner@test.com", name: "Owner"),
        members: [
            User(id: "user2", email: "member@test.com", name: "Member 1"),
            User(id: "user3", email: "member2@test.com", name: "Member 2")
        ]
    )

    return VStack(spacing: 24) {
        InlineAssigneePicker(
            label: "Who",
            assigneeId: .constant(nil),
            taskListIds: ["list1"],
            taskId: nil,
            availableLists: [mockList],
            onSave: nil
        )
        .environmentObject(AuthManager.shared)
        .padding()
    }
    .background(Theme.bgPrimary)
}
