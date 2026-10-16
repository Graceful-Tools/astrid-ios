//  QuickAddPickerSheet.swift
//  The priority and assignee picker quick add opens from its checkbox, moved out of
//  QuickAddTaskView so that file stays under its size ceiling (AITD-491).

import SwiftUI

// MARK: - Quick Add Picker Sheet

/// Sheet for selecting priority and assignee when adding a task
struct QuickAddPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    @Binding var selectedPriority: Task.Priority
    @Binding var selectedAssigneeId: String?
    let availableMembers: [User]
    let colorScheme: ColorScheme
    var listIds: [String]? = nil

    @State private var aiAgents: [User] = []
    @State private var isLoadingAgents = false

    private let priorities: [Task.Priority] = [.none, .low, .medium, .high]

    /// A board that refuses a priority (AITD-491) is not offered one: the new task would drop it.
    private var offersPriority: Bool {
        TaskCapabilities.allows(.priority, listIds: listIds ?? [], lists: ListService.shared.lists)
    }

    // Combine available members with AI agents
    private var allMembers: [User] {
        var memberMap: [String: User] = [:]
        // Add AI agents first
        for agent in aiAgents {
            memberMap[agent.id] = agent
        }
        // Add available members (won't overwrite AI agents)
        for member in availableMembers {
            if memberMap[member.id] == nil {
                memberMap[member.id] = member
            }
        }
        // Sort: AI agents first, then current user, then alphabetically
        return Array(memberMap.values).sorted { u1, u2 in
            let u1IsAI = u1.isAIAgent == true
            let u2IsAI = u2.isAIAgent == true
            if u1IsAI && !u2IsAI { return true }
            if !u1IsAI && u2IsAI { return false }
            if let currentUser = authManager.currentUser {
                if u1.id == currentUser.id { return true }
                if u2.id == currentUser.id { return false }
            }
            return (u1.name ?? u1.email ?? "") < (u2.name ?? u2.email ?? "")
        }
    }

    var body: some View {
        // Use VStack instead of ScrollView to allow swipe-down-to-dismiss gesture
        // Content fits within .medium detent for typical team sizes
        VStack(alignment: .leading, spacing: Theme.spacing24) {
            // Priority Section - using same design as task details
            if offersPriority {
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    Text(NSLocalizedString("tasks.priority", comment: ""))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    HStack(spacing: Theme.spacing12) {
                        ForEach(priorities, id: \.self) { priority in
                            QuickAddPriorityButton(
                                priority: priority,
                                isSelected: selectedPriority == priority,
                                colorScheme: colorScheme
                            ) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                selectedPriority = priority
                                dismiss()
                            }
                        }
                    }
                }
            }

            // Only show assignee section for logged-in users
            if authManager.isAuthenticated {
                if offersPriority { Divider() }

                // Assignee Section - scrollable for large teams
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    Text(NSLocalizedString("tasks.assignee", comment: ""))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    ScrollView {
                        VStack(spacing: Theme.spacing8) {
                            // Unassigned option
                            AssigneeOptionButton(
                                user: nil,
                                isSelected: selectedAssigneeId == nil,
                                isCurrentUser: false,
                                colorScheme: colorScheme
                            ) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                selectedAssigneeId = nil
                                dismiss()
                            }

                            // Member options (including AI agents)
                            ForEach(allMembers) { member in
                                AssigneeOptionButton(
                                    user: member,
                                    isSelected: selectedAssigneeId == member.id,
                                    isCurrentUser: member.id == authManager.currentUser?.id,
                                    isAIAgent: member.isAIAgent == true,
                                    colorScheme: colorScheme
                                ) {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    selectedAssigneeId = member.id
                                    dismiss()
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            Spacer()
        }
        .padding(Theme.spacing16)
        .padding(.top, Theme.spacing8)
        .task {
            // Fetch AI agents when sheet appears
            await fetchAIAgents()
        }
    }

    private func fetchAIAgents() async {
        guard !isLoadingAgents else { return }
        isLoadingAgents = true

        // Try to load from cache first for instant display
        if let cachedAgents = AIAgentCache.shared.load() {
            await MainActor.run {
                self.aiAgents = cachedAgents
            }
        }

        // Then try to fetch fresh data from API
        do {
            let users = try await RemoteResourceService.shared.searchUsersWithAIAgents(
                query: "",
                taskId: nil,
                listIds: listIds
            )
            let agents = users.filter { $0.isAIAgent == true }
            await MainActor.run {
                self.aiAgents = agents
                self.isLoadingAgents = false
            }
            // Cache for offline use
            AIAgentCache.shared.save(agents)
        } catch {
            AppLog.debug("❌ [QuickAddPickerSheet] Failed to fetch AI agents: \(error)")
            await MainActor.run {
                // Keep cached agents if we have them, otherwise aiAgents stays as loaded from cache
                self.isLoadingAgents = false
            }
        }
    }
}

// MARK: - Quick Add Priority Button (matches task details design)

private struct QuickAddPriorityButton: View {
    let priority: Task.Priority
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var priorityColor: Color {
        switch priority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    /// Symbol matching mobile web design
    private var symbol: String {
        switch priority {
        case .none: return "○"   // Circle (U+25CB)
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 48, height: 44)
                .foregroundColor(isSelected ? .white : priorityColor)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(isSelected ? priorityColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(priorityColor, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Assignee Option Button

private struct AssigneeOptionButton: View {
    let user: User?
    let isSelected: Bool
    let isCurrentUser: Bool
    var isAIAgent: Bool = false
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing12) {
                // Avatar or icon
                if let user = user {
                    CachedAsyncImage(url: user.image.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Theme.accent)
                            Text(user.name?.prefix(1).uppercased() ?? user.email?.prefix(1).uppercased() ?? "?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.accentText)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.slash")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                // Name and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? NSLocalizedString("assignee.unassigned", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    if isCurrentUser {
                        Text(NSLocalizedString("assignee.you", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    } else if user?.isAIAgent == true {
                        Text(NSLocalizedString("profile.ai_agent", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, Theme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(isSelected
                          ? (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
