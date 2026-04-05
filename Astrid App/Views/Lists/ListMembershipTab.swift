import SwiftUI
import Contacts

/// Membership tab for list settings
struct ListMembershipTab: View {
    @Environment(\.colorScheme) var colorScheme

    let list: TaskList
    let onUpdate: (TaskList) -> Void
    @Binding var removedMemberEmails: Set<String>
    var onLeave: (() -> Void)?

    @State private var showingAddMember = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // AI Agents state - now stores full User objects with profile photos
    @State private var availableAiAgents: [User] = []
    @State private var loadingAiProviders = false
    @State private var removingAgents = Set<String>()
    @State private var showingShareList = false
    @State private var isGitHubConnected = false

    private let listService = ListService.shared
    private let apiClient = AstridAPIClient.shared

    /// Check if current user can edit settings (is owner or admin)
    private var canEditSettings: Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return false
        }

        // Check if user is owner (check both ownerId field and owner object)
        // API may return ownerId or owner object depending on the endpoint
        if list.ownerId == currentUserId || list.owner?.id == currentUserId {
            return true
        }

        // Check if user is admin
        if let admins = list.admins, admins.contains(where: { $0.id == currentUserId }) {
            return true
        }

        // Check in listMembers for admin role
        if let listMembers = list.listMembers {
            if listMembers.contains(where: { $0.user?.id == currentUserId && $0.role == "admin" }) {
                return true
            }
        }

        return false
    }

    /// Filter invitations to only show truly pending ones (exclude users who have already accepted)
    private var pendingInvitations: [ListInvite] {
        guard let invitations = list.invitations else { return [] }

        // Get all member emails (from both legacy members and listMembers)
        var memberEmails = Set<String>()

        // Add emails from legacy members array
        if let members = list.members {
            memberEmails.formUnion(members.compactMap { $0.email })
        }

        // Add emails from listMembers
        if let listMembers = list.listMembers {
            memberEmails.formUnion(listMembers.compactMap { $0.user?.email })
        }

        // Add owner email
        if let ownerEmail = list.owner?.email {
            memberEmails.insert(ownerEmail)
        }

        // Filter out invitations where user has already accepted (email exists in members)
        return invitations.filter { !memberEmails.contains($0.email) }
    }

    @State private var showingLoginSheet = false

    var body: some View {
        // For local-only users, show sign-in CTA instead of member management
        if AuthManager.shared.isLocalOnlyMode {
            localUserMembershipView
        } else {
            membershipForm
        }
    }

    // MARK: - Local User View

    private var localUserMembershipView: some View {
        Form {
            Section {
                VStack(spacing: Theme.spacing16) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                    Text(NSLocalizedString("membership.requires_account", comment: "List sharing requires an account"))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("membership.requires_account_description", comment: "Sign in to invite collaborators and share lists with others."))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        showingLoginSheet = true
                    } label: {
                        Text(NSLocalizedString("membership.sign_in_to_share", comment: "Sign in to share lists"))
                            .font(Theme.Typography.body().weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing12)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, Theme.spacing16)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .sheet(isPresented: $showingLoginSheet) {
            NavigationStack {
                LoginView()
            }
        }
    }

    // MARK: - Regular Membership Form

    private var membershipForm: some View {
        Form {
            // Members Section
            Section(NSLocalizedString("lists.members", comment: "")) {
                // Owner
                if let owner = list.owner {
                    ZStack(alignment: .leading) {
                        NavigationLink(destination: UserProfileView(userId: owner.id)) {
                            EmptyView()
                        }
                        .opacity(0)

                        HStack(spacing: Theme.spacing12) {
                            CachedAsyncImage(url: owner.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accent)
                                    Text(owner.initials)
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(owner.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(owner.email ?? NSLocalizedString("profile.no_email", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }

                            Spacer()

                            Text(NSLocalizedString("lists.owner", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                }

                // Admins (exclude owner to prevent duplicate display)
                if let admins = list.admins, !admins.isEmpty {
                    ForEach(admins.filter { $0.id != list.owner?.id }) { admin in
                        ZStack(alignment: .leading) {
                            NavigationLink(destination: UserProfileView(userId: admin.id)) {
                                EmptyView()
                            }
                            .opacity(0)

                            HStack(spacing: Theme.spacing12) {
                                CachedAsyncImage(url: admin.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.accent)
                                        Text(admin.initials)
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(admin.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text(admin.email ?? NSLocalizedString("profile.no_email", comment: ""))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                }

                                Spacer()

                                if canEditSettings {
                                    Menu {
                                        Button {
                                            changeRole(userId: admin.id, currentRole: "admin", newRole: "member")
                                        } label: {
                                            Label(NSLocalizedString("lists.make_member", comment: ""), systemImage: "person")
                                        }

                                        Button(role: .destructive) {
                                            removeMember(userId: admin.id, email: admin.email ?? "")
                                        } label: {
                                            Label(NSLocalizedString("lists.remove", comment: ""), systemImage: "trash")
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(NSLocalizedString("lists.admin_role", comment: ""))
                                                .font(Theme.Typography.caption1())
                                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                            Image(systemName: "ellipsis")
                                                .rotationEffect(.degrees(90))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(NSLocalizedString("lists.admin_role", comment: ""))
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }
                    }
                }

                // Regular Members (from legacy members array)
                if let members = list.members, !members.isEmpty {
                    ForEach(members) { member in
                        ZStack(alignment: .leading) {
                            NavigationLink(destination: UserProfileView(userId: member.id)) {
                                EmptyView()
                            }
                            .opacity(0)

                            HStack(spacing: Theme.spacing12) {
                                CachedAsyncImage(url: member.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ZStack {
                                        Circle()
                                            .fill(Theme.accent)
                                        Text(member.initials)
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text(member.email ?? NSLocalizedString("profile.no_email", comment: ""))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                }

                                Spacer()

                                if canEditSettings {
                                    Menu {
                                        Button {
                                            changeRole(userId: member.id, currentRole: "member", newRole: "admin")
                                        } label: {
                                            Label(NSLocalizedString("lists.make_admin", comment: ""), systemImage: "star")
                                        }

                                        Button(role: .destructive) {
                                            removeMember(userId: member.id, email: member.email ?? "")
                                        } label: {
                                            Label(NSLocalizedString("lists.remove", comment: ""), systemImage: "trash")
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(NSLocalizedString("lists.member_role", comment: ""))
                                                .font(Theme.Typography.caption1())
                                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                            Image(systemName: "ellipsis")
                                                .rotationEffect(.degrees(90))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(NSLocalizedString("lists.member_role", comment: ""))
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }
                    }
                }

                // ListMembers (from new listMembers table with roles, exclude owner to prevent duplicate)
                if let listMembers = list.listMembers, !listMembers.isEmpty {
                    ForEach(listMembers.filter { $0.user?.id != list.owner?.id }) { listMember in
                        if let user = listMember.user {
                            ZStack(alignment: .leading) {
                                NavigationLink(destination: UserProfileView(userId: user.id)) {
                                    EmptyView()
                                }
                                .opacity(0)

                                HStack(spacing: Theme.spacing12) {
                                    CachedAsyncImage(url: user.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Circle()
                                                .fill(Theme.accent)
                                            Text(user.initials)
                                                .font(Theme.Typography.caption1())
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Text(user.email ?? NSLocalizedString("profile.no_email", comment: ""))
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    }

                                    Spacer()

                                    if canEditSettings {
                                        Menu {
                                            Button {
                                                let newRole = listMember.role == "admin" ? "member" : "admin"
                                                changeRole(userId: user.id, currentRole: listMember.role, newRole: newRole)
                                            } label: {
                                                if listMember.role == "admin" {
                                                    Label(NSLocalizedString("lists.make_member", comment: ""), systemImage: "person")
                                                } else {
                                                    Label(NSLocalizedString("lists.make_admin", comment: ""), systemImage: "star")
                                                }
                                            }

                                            Button(role: .destructive) {
                                                removeMember(userId: user.id, email: user.email ?? "")
                                            } label: {
                                                Label(NSLocalizedString("lists.remove", comment: ""), systemImage: "trash")
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text(listMember.role == "admin" ? NSLocalizedString("lists.admin_role", comment: "") : NSLocalizedString("lists.member_role", comment: ""))
                                                    .font(Theme.Typography.caption1())
                                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                                Image(systemName: "ellipsis")
                                                    .rotationEffect(.degrees(90))
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text(listMember.role == "admin" ? NSLocalizedString("lists.admin_role", comment: "") : NSLocalizedString("lists.member_role", comment: ""))
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    }
                                }
                            }
                        }
                    }
                }

                // Pending Invitations (only show to admins/owners)
                if canEditSettings && !pendingInvitations.isEmpty {
                    ForEach(pendingInvitations) { invitation in
                        HStack(spacing: Theme.spacing12) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(invitation.email)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                HStack(spacing: 4) {
                                    Text(NSLocalizedString("messages.loading", comment: ""))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.orange)
                                    Text("·")
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    Text(invitation.role == "admin" ? NSLocalizedString("lists.admin_role", comment: "") : NSLocalizedString("lists.member_role", comment: ""))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                removeInvitation(invitationId: invitation.id, email: invitation.email)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add Member Section - Only for admins/owners
            if canEditSettings {
                Section {
                    Button(action: { showingAddMember = true }) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("lists.add_member", comment: ""))
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }

            // Share List Section
            Section {
                Button(action: { showingShareList = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(Theme.accent)
                        Text(NSLocalizedString("lists.share_list", comment: ""))
                            .foregroundColor(Theme.accent)
                    }
                }
            } header: {
                Text(NSLocalizedString("actions.share", comment: ""))
            } footer: {
                Text(NSLocalizedString("lists.share_list_description", comment: ""))
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            // AI Agents Section - Only show if user can edit AND has AI agents available
            if canEditSettings && !availableAiAgents.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing12) {
                        Text(NSLocalizedString("lists.available_agents", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        if loadingAiProviders {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(NSLocalizedString("lists.loading_ai_agents", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        } else {
                            ForEach(availableAiAgents) { agent in
                                let agentDescription: String = {
                                    if isGitHubConnected {
                                        switch agent.aiAgentType {
                                        case "claude_agent":
                                            return NSLocalizedString("lists.claude_coding_description", comment: "")
                                        case "openai_agent":
                                            return NSLocalizedString("lists.openai_coding_description", comment: "")
                                        case "gemini_agent":
                                            return NSLocalizedString("lists.gemini_coding_description", comment: "")
                                        default:
                                            return NSLocalizedString("lists.default_agent_description", comment: "")
                                        }
                                    } else {
                                        switch agent.aiAgentType {
                                        case "claude_agent":
                                            return NSLocalizedString("lists.claude_task_description", comment: "")
                                        case "openai_agent":
                                            return NSLocalizedString("lists.openai_task_description", comment: "")
                                        case "gemini_agent":
                                            return NSLocalizedString("lists.gemini_task_description", comment: "")
                                        default:
                                            return NSLocalizedString("lists.default_agent_description", comment: "")
                                        }
                                    }
                                }()
                                let isMember = isAgentMember(agentEmail: agent.email)
                                let isRemoving = removingAgents.contains(agent.id)

                                HStack(spacing: Theme.spacing12) {
                                    // Agent Profile Photo - same style as member photos
                                    CachedAsyncImage(url: agent.cachedImageURL.flatMap { URL(string: $0) }) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ZStack {
                                            Circle()
                                                .fill(Color.purple.opacity(0.2))
                                            Image(systemName: "cpu")
                                                .font(.system(size: 16))
                                                .foregroundColor(.purple)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())

                                    // Agent Info
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(agent.displayName)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                                        Text(agentDescription)
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    // Add/Remove Button
                                    if isMember {
                                        Button(action: {
                                            removeCodingAgent(agent: agent)
                                        }) {
                                            Text(isRemoving ? NSLocalizedString("messages.deleting", comment: "") : NSLocalizedString("actions.remove", comment: ""))
                                                .font(Theme.Typography.caption1())
                                                .foregroundColor(.red)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.red.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        .disabled(isRemoving)
                                        .buttonStyle(.plain)
                                    } else {
                                        Button(action: {
                                            addCodingAgent(agent: agent)
                                        }) {
                                            Text(NSLocalizedString("actions.add", comment: ""))
                                                .font(Theme.Typography.caption1())
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, Theme.spacing8)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .foregroundColor(.purple)
                        Text(isGitHubConnected ? NSLocalizedString("lists.ai_coding_agents", comment: "") : NSLocalizedString("lists.ai_agents", comment: ""))
                    }
                } footer: {
                    if !isGitHubConnected {
                        Text(NSLocalizedString("lists.connect_github_description", comment: ""))
                            .font(Theme.Typography.caption2())
                    }
                }
            }

            // Privacy Section - Only for admins/owners
            if canEditSettings {
                Section(NSLocalizedString("lists.list_privacy", comment: "")) {
                if list.privacy != .PUBLIC {
                    Button(action: {
                        var updated = list
                        updated.privacy = .PUBLIC
                        onUpdate(updated)
                    }) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.green)
                            Text(NSLocalizedString("lists.make_public", comment: ""))
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    Button(action: {
                        var updated = list
                        updated.privacy = .SHARED
                        onUpdate(updated)
                    }) {
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("lists.make_private", comment: ""))
                                .foregroundColor(.orange)
                        }
                    }
                }

                // Privacy explanation
                if list.privacy == .PUBLIC {
                    Text(NSLocalizedString("lists.public_description", comment: ""))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                } else {
                    Text(NSLocalizedString("lists.private_description", comment: ""))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }
            }

            // Leave List - shown for non-owner members
            if let onLeave = onLeave {
                Section {
                    Button(role: .destructive, action: onLeave) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(NSLocalizedString("lists.leave_list", comment: "Leave List"))
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .task {
            await loadAiProviders()
        }
        .sheet(isPresented: $showingShareList) {
            ShareListView(list: list)
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(
                onAdd: { email, role in
                    addMember(email: email, role: role)
                },
                excludeListId: list.id,
                showRolePicker: true,
                autoDismiss: true
            )
        }
    }

    // MARK: - Member Management Functions

    private func addMember(email: String, role: String) {
        isProcessing = true

        _Concurrency.Task {
            do {
                _ = try await apiClient.addListMember(
                    listId: list.id,
                    email: email,
                    role: role
                )

                // Refresh list data — parent chain propagates via onChange guard
                _ = try? await listService.fetchLists()
            } catch {
                errorMessage = error.localizedDescription
            }

            isProcessing = false
        }
    }

    private func changeRole(userId: String, currentRole: String, newRole: String) {
        _Concurrency.Task {
            do {
                _ = try await apiClient.updateListMember(
                    listId: list.id,
                    userId: userId,
                    role: newRole
                )

                // Refresh list data — parent chain propagates via onChange guard
                _ = try? await listService.fetchLists()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeMember(userId: String, email: String) {
        // Track removal so UI stays correct even if stale data flows in
        if !email.isEmpty {
            removedMemberEmails.insert(email)
        }

        // Optimistic update: remove member from list immediately
        var updatedList = list
        updatedList.admins?.removeAll { $0.id == userId }
        updatedList.members?.removeAll { $0.id == userId }
        updatedList.listMembers?.removeAll { $0.userId == userId || $0.user?.id == userId }
        onUpdate(updatedList)

        // Sync with server in background
        _Concurrency.Task {
            do {
                _ = try await apiClient.removeListMember(
                    listId: list.id,
                    userId: userId
                )

                print("✅ [ListMembershipTab] Removed member from list")
            } catch {
                // Revert on failure
                if !email.isEmpty {
                    removedMemberEmails.remove(email)
                }
                onUpdate(list)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeInvitation(invitationId: String, email: String) {
        // For invitations, we need the userId from the invitation
        // Since invitations don't have userId yet (user hasn't accepted), this is a special case
        // For now, we'll handle this by email-based removal when backend supports it
        _Concurrency.Task {
            errorMessage = "Removing pending invitations will be supported in a future update"
        }
    }

    // MARK: - AI Agents Functions

    private func loadAiProviders() async {
        loadingAiProviders = true

        do {
            print("🤖 [ListMembershipTab] Loading AI agents with profile photos")

            // First check GitHub status for UI context
            let status = try await apiClient.getGitHubStatus()
            isGitHubConnected = status.isGitHubConnected

            // Fetch actual AI agent User objects (with profile photos) based on user's API keys
            let users = try await apiClient.searchUsersWithAIAgents(
                query: "",
                taskId: nil,
                listIds: nil
            )

            // Filter to only AI agents and cache them
            let agents = users.filter { $0.isAIAgent == true }
            availableAiAgents = agents

            // Cache agents for offline support
            AIAgentCache.shared.save(agents)

            print("✅ [ListMembershipTab] Found \(agents.count) AI agents with photos, GitHub connected: \(status.isGitHubConnected)")
        } catch {
            print("❌ [ListMembershipTab] Failed to load AI agents: \(error)")

            // Try to load from cache as fallback
            if let cachedAgents = AIAgentCache.shared.load() {
                availableAiAgents = cachedAgents
                print("📦 [ListMembershipTab] Using \(cachedAgents.count) cached AI agents")
            } else {
                availableAiAgents = []
            }
            isGitHubConnected = false
        }

        loadingAiProviders = false
    }

    private func isAgentMember(agentEmail: String?) -> Bool {
        guard let email = agentEmail else { return false }

        // If we've locally removed this member, it's not a member regardless of stale list data
        if removedMemberEmails.contains(email) { return false }

        // Check in all member sources
        if list.owner?.email == email { return true }
        if list.admins?.contains(where: { $0.email == email }) == true { return true }
        if list.members?.contains(where: { $0.email == email }) == true { return true }
        if list.listMembers?.contains(where: { $0.user?.email == email }) == true { return true }

        return false
    }

    private func addCodingAgent(agent: User) {
        guard let email = agent.email else { return }

        // Clear any stale removal tracking for this agent
        removedMemberEmails.remove(email)

        _Concurrency.Task {
            do {
                print("🤖 [ListMembershipTab] Adding \(email) to list")

                // Add agent to list members
                _ = try await apiClient.addListMember(
                    listId: list.id,
                    email: email,
                    role: "member"
                )

                print("✅ [ListMembershipTab] Added \(email) to list")

                // Refresh list data — parent chain propagates via onChange guard
                _ = try? await listService.fetchLists()
            } catch {
                print("❌ [ListMembershipTab] Failed to add agent: \(error)")
                errorMessage = "Failed to add AI agent: \(error.localizedDescription)"
            }
        }
    }

    private func removeCodingAgent(agent: User) {
        // Set loading state
        removingAgents.insert(agent.id)

        guard let email = agent.email else { return }
        print("🤖 [ListMembershipTab] Removing \(email) from list")

        // Track removal so UI stays correct even if stale data flows in
        removedMemberEmails.insert(email)

        // Find agent in list members by email
        var agentUserId: String?

        if list.owner?.email == email {
            agentUserId = list.owner?.id
        } else if let admin = list.admins?.first(where: { $0.email == email }) {
            agentUserId = admin.id
        } else if let member = list.members?.first(where: { $0.email == email }) {
            agentUserId = member.id
        } else if let listMember = list.listMembers?.first(where: { $0.user?.email == email }) {
            agentUserId = listMember.userId
        }

        guard let userId = agentUserId else {
            print("⚠️ [ListMembershipTab] Agent \(email) not found in list members")
            removingAgents.remove(agent.id)
            return
        }

        // Optimistic update: remove agent from list immediately
        var updatedList = list
        updatedList.admins?.removeAll { $0.id == userId }
        updatedList.members?.removeAll { $0.id == userId }
        updatedList.listMembers?.removeAll { $0.userId == userId || $0.user?.id == userId }
        onUpdate(updatedList)

        // Sync with server in background
        _Concurrency.Task {
            defer {
                removingAgents.remove(agent.id)
            }

            do {
                _ = try await apiClient.removeListMember(
                    listId: list.id,
                    userId: userId
                )

                print("✅ [ListMembershipTab] Removed \(email) from list")
            } catch {
                // Revert on failure
                print("❌ [ListMembershipTab] Failed to remove agent: \(error)")
                removedMemberEmails.remove(email)
                onUpdate(list)
                errorMessage = "Failed to remove AI agent: \(error.localizedDescription)"
            }
        }
    }
}
