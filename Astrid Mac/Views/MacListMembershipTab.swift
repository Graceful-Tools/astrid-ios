//  MacListMembershipTab.swift
//  Astrid for Mac — the Membership half of List Settings (AITD-388).
//
//  Replaces `MacListMembersView`, which was missing most of what iOS and Web have had for a
//  while. The gaps were not cosmetic:
//
//  PENDING INVITATIONS WERE SHOWN AS MEMBERS. `ListMemberService.fetchMembers` maps every row the
//  server returns into `membersByList`, invitations included, and `ListMember` carries no `type`
//  to tell them apart. So an invited-but-not-joined person appeared as a full member with a role
//  picker and a Remove button — and Remove called `DELETE /members/{id}`, which is not how an
//  invitation is cancelled. Invitations come from `list.invitations` here, through the shared
//  `ListMembershipRoster`, exactly as iOS reads them.
//
//  There was NO WAY TO LEAVE A LIST, no way to add or remove an AI agent, and the privacy pickers
//  named three options without saying what any of them did.
//
//  TRANSFER OWNERSHIP used to be the gap here: web POSTed to a legacy `/api/lists/...` path with
//  no `/api/v1` equivalent, and ASTRID.md rule 5 says the apps call v1 only, so an owner got an
//  explanation instead of a control. The v1 routes exist now and it is a real control (AITD-392).
//
//  It still degrades to that explanation when the server does not answer the probe: astrid-web
//  deploys by hand, so a shipped build can meet a server that has never heard of the route. See
//  `ListOwnershipTransfer` — the state is `.unavailable`, not an error.

#if os(macOS)
import SwiftUI

struct MacListMembershipTab: View {
    let list: TaskList

    @StateObject private var svc = ListMemberService.shared
    @StateObject private var listService = ListService.shared
    @State private var email = ""
    @State private var inviteRole = "member"
    @State private var privacy = "PRIVATE"
    @State private var publicType = "collaborative"
    @State private var contactSuggestions: [ContactSearchResult] = []
    @State private var loadingMembers = true
    @State private var profileTarget: MacProfileTarget?
    @State private var availableAgents: [User] = []
    @State private var loadingAgents = false
    @State private var confirmingLeave = false
    /// Starts `.unavailable` so a server that never answers shows the honest explanation
    /// rather than a control that cannot work (AITD-392).
    @State private var transferAvailability: ListOwnershipTransfer.Availability = .unavailable
    @State private var successorId = ""
    @State private var confirmingTransfer = false

    private static let roles = ["member", "admin"]

    /// The freshest copy of this list, so an invitation cancelled a moment ago actually vanishes.
    /// `list` is a snapshot taken when the window opened.
    private var currentList: TaskList {
        listService.lists.first { $0.id == list.id } ?? list
    }

    private var members: [ListMember] { svc.membersByList[list.id] ?? [] }

    /// Invitations nobody has accepted, via the SHARED rule (AITD-388).
    private var pendingInvitations: [ListInvite] {
        ListMembershipRoster.pendingInvitations(in: currentList)
    }

    private var canManage: Bool {
        ListPermissions.canEditSettings(currentList, userId: AuthManager.shared.userId)
    }

    private func isOwner(_ m: ListMember) -> Bool { currentList.role(for: m.userId) == .owner }

    private var leaveOption: ListMembershipRoster.LeaveOption {
        ListMembershipRoster.leaveOption(for: currentList, userId: AuthManager.shared.userId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                membersSection
                if canManage { inviteSection }
                if canManage { agentsSection }
                if canManage { privacySection }
                leaveSection
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $profileTarget) { MacUserProfileView(userId: $0.id) }
        .task {
            try? await svc.fetchMembers(listId: list.id)
            loadingMembers = false
            await loadAgents()
        }
        .onAppear {
            privacy = currentList.privacy?.rawValue ?? "PRIVATE"
            publicType = currentList.publicListType ?? "collaborative"
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("lists.members", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)

            if members.isEmpty, !loadingMembers {
                // An empty roster is ambiguous: a non-member viewing a PUBLIC list gets 200 with
                // NO members, because the payload carries email addresses.
                switch ListMemberVisibility.emptyState(userRole: svc.viewerRoleByList[list.id]) {
                case .hiddenFromViewer:
                    Text(NSLocalizedString("lists.members_hidden_from_viewer", comment: ""))
                        .font(.callout).foregroundStyle(Theme.textMuted)
                case .genuinelyEmpty:
                    Text(NSLocalizedString("lists.no_members_yet", comment: ""))
                        .font(.callout).foregroundStyle(Theme.textMuted)
                }
            }
            if loadingMembers && members.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(NSLocalizedString("mac.loading_members", comment: ""))
                }.foregroundStyle(Theme.textMuted)
            }

            ForEach(members) { m in memberRow(m) }

            if !pendingInvitations.isEmpty {
                Text(NSLocalizedString("lists.pending_invitations", comment: ""))
                    .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                    .padding(.top, 6)
                ForEach(pendingInvitations) { invitationRow($0) }
            }
        }
    }

    private func memberRow(_ m: ListMember) -> some View {
        HStack {
            HStack(spacing: 8) {
                MacAuthorAvatar(display: MacAuthorDisplay.of(authorId: m.userId, author: m.user,
                                                             currentUser: nil),
                                size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.user?.displayName ?? m.userId).foregroundStyle(Theme.textPrimary)
                    Text(MacMemberRoleLabel.title(for: isOwner(m) ? "owner" : m.role))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .contentShape(Rectangle())
            .macOpensProfile(MacProfileLink.userId(authorId: m.userId,
                                                   isAgent: m.user?.isAIAgent == true),
                             target: $profileTarget)
            Spacer()
            if canManage && !isOwner(m) {
                Picker("", selection: Binding(get: { m.role }, set: { setRole(m, $0) })) {
                    ForEach(Self.roles, id: \.self) {
                        Text(MacMemberRoleLabel.title(for: $0)).tag($0)
                    }
                }
                .labelsHidden().frame(width: 110)
                Button(role: .destructive) { remove(m) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.error)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("actions.remove", comment: ""))
            }
        }
    }

    /// A pending invitation. Visibly NOT a member: it has an email and no face, it says "Invited",
    /// and its controls go to the invitation endpoints rather than the member ones.
    private func invitationRow(_ invite: ListInvite) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(invite.email).foregroundStyle(Theme.textPrimary)
                    Text(NSLocalizedString("lists.invited", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            if canManage {
                Picker("", selection: Binding(get: { invite.role },
                                              set: { setInviteRole(invite, $0) })) {
                    ForEach(Self.roles, id: \.self) {
                        Text(MacMemberRoleLabel.title(for: $0)).tag($0)
                    }
                }
                .labelsHidden().frame(width: 110)
                Button(role: .destructive) { cancelInvite(invite) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.error)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("lists.cancel_invite", comment: ""))
            }
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !contactSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contactSuggestions) { c in
                        Button { email = c.email; contactSuggestions = [] } label: {
                            Text(MacContactPick.display(name: c.name, email: c.email))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                TextField(NSLocalizedString("members.invite_email", comment: ""), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(invite)
                    .onChange(of: email) { searchContacts() }
                Picker("", selection: $inviteRole) {
                    ForEach(Self.roles, id: \.self) {
                        Text(MacMemberRoleLabel.title(for: $0)).tag($0)
                    }
                }.labelsHidden().frame(width: 110)
                Button(NSLocalizedString("mac.invite", comment: ""), action: invite)
                    .disabled(!canInvite)
            }
        }
    }

    private var canInvite: Bool { email.contains("@") && email.contains(".") }

    // MARK: - AI agents

    /// Agents you have keys for, added to or removed from the list like any other member — which
    /// is what they are. Mac could only ever DISPLAY an agent that was already a member.
    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(NSLocalizedString("lists.ai_agents", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)

            if loadingAgents {
                Text(NSLocalizedString("lists.loading_ai_agents", comment: ""))
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else if availableAgents.isEmpty {
                Text(NSLocalizedString("lists.no_ai_agents_hint", comment: ""))
                    .font(.caption).foregroundStyle(Theme.textMuted)
            } else {
                ForEach(availableAgents) { agent in
                    HStack {
                        HStack(spacing: 8) {
                            MacAuthorAvatar(display: MacAuthorDisplay.of(authorId: agent.id,
                                                                         author: agent,
                                                                         currentUser: nil),
                                            size: 26)
                            Text(agent.displayName).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        if isAgentMember(agent) {
                            Button(NSLocalizedString("lists.remove_ai_agent", comment: "")) {
                                removeAgent(agent)
                            }
                        } else {
                            Button(NSLocalizedString("lists.add_ai_agent", comment: "")) {
                                addAgent(agent)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The SHARED rule (AITD-399). The Mac's roster is `ListMemberService.membersByList`, which
    /// iOS does not read — hence `roster:`.
    private func isAgentMember(_ agent: User) -> Bool {
        ListMembershipRoster.isMember(email: agent.email, of: currentList, roster: members)
    }

    // MARK: - Privacy

    /// Every option now says what it DOES. The pickers named "Private / Shared / Public" and
    /// "Collaborative / Copy only" with no hint of the consequence — and those five labels were
    /// hardcoded English besides (ASTRID.md rule 8). Web spells each one out; so does this.
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Picker(NSLocalizedString("mac.privacy", comment: ""), selection: $privacy) {
                ForEach(MacListPrivacy.privacy) { Text($0.label).tag($0.value) }
            }
            .onChange(of: privacy) { savePrivacy() }

            Text(MacListPrivacy.privacyDescription(privacy))
                .font(.caption).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            if privacy == "PUBLIC" {
                Picker(NSLocalizedString("lists.public_type", comment: ""), selection: $publicType) {
                    ForEach(MacListPrivacy.publicType) { Text($0.label).tag($0.value) }
                }
                .onChange(of: publicType) { savePrivacy() }

                Text(MacListPrivacy.publicTypeDescription(publicType))
                    .font(.caption).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Leaving

    @ViewBuilder
    private var leaveSection: some View {
        switch leaveOption {
        case .leave:
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Button(NSLocalizedString("lists.leave_list", comment: ""), role: .destructive) {
                    confirmingLeave = true
                }
            }
            .confirmationDialog(NSLocalizedString("lists.leave_list", comment: ""),
                                isPresented: $confirmingLeave) {
                Button(NSLocalizedString("lists.leave_list", comment: ""), role: .destructive,
                       action: leave)
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("lists.leave_confirm", comment: ""))
            }
        case .transferOwnership:
            // An owner cannot simply leave — ownership is what `canDelete` keys on, so it has to
            // be handed over explicitly. Which of these four the server says decides what shows;
            // `.unavailable` is the pre-deploy state and keeps the old explanation (AITD-392).
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                switch transferAvailability {
                case .unavailable:
                    Text(NSLocalizedString("lists.owner_cannot_leave_yet", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                case .notPermitted:
                    // The server says this caller is not the owner after all. It outranks the
                    // local roster, so offer nothing.
                    EmptyView()

                case .noEligibleOwners:
                    Text(NSLocalizedString("lists.transfer_ownership_none", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                case .available(let successors):
                    Text(String(format: NSLocalizedString("lists.transfer_ownership_prompt",
                                                          comment: ""), currentList.name))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker(NSLocalizedString("lists.transfer_ownership_select", comment: ""),
                           selection: $successorId) {
                        ForEach(successors) { successor in
                            Text(successor.displayName).tag(successor.id)
                        }
                    }
                    .labelsHidden()

                    Button(NSLocalizedString("lists.transfer_and_leave", comment: ""),
                           role: .destructive) {
                        confirmingTransfer = true
                    }
                    .disabled(successorId.isEmpty)
                    .confirmationDialog(
                        NSLocalizedString("lists.transfer_ownership", comment: ""),
                        isPresented: $confirmingTransfer
                    ) {
                        Button(NSLocalizedString("lists.transfer_and_leave", comment: ""),
                               role: .destructive, action: transferOwnership)
                        Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text(String(format: NSLocalizedString("lists.transfer_ownership_confirm",
                                                              comment: ""), currentList.name))
                    }
                    .onAppear {
                        // Pre-select, so the button is live rather than disabled for no visible
                        // reason on a list with exactly one eligible successor.
                        if successorId.isEmpty { successorId = successors[0].id }
                    }
                }
            }
            .task(id: currentList.id) { await loadTransferAvailability() }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func searchContacts() {
        let q = email.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !q.contains("@") else { contactSuggestions = []; return }
        _Concurrency.Task {
            let hits = (try? await ContactsService.shared.searchContacts(query: q,
                                                                        excludeListId: list.id)) ?? []
            contactSuggestions = Array(hits.prefix(5))
        }
    }

    /// Shared with iOS (AITD-399). The cache WRITE came with it: this side only ever read
    /// `AIAgentCache`, so the offline fallback was empty unless the phone had filled it.
    private func loadAgents() async {
        loadingAgents = true
        defer { loadingAgents = false }
        availableAgents = await ListMembershipActions.availableAgents()
    }

    private func savePrivacy() {
        AppActions.perform("Update list privacy") {
            _ = try await ListService.shared.updateListAdvanced(
                listId: list.id,
                updates: MacListPrivacy.updates(privacy: privacy, publicType: publicType))
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func invite() {
        guard canInvite else { return }
        let e = email.trimmingCharacters(in: .whitespaces)
        let role = inviteRole
        AppActions.perform("Invite \(e)") {
            _ = try await ListMembershipActions.addMember(listId: list.id, email: e, role: role)
            email = ""
            try? await svc.fetchMembers(listId: list.id)
            _ = try? await ListService.shared.fetchLists()   // picks up the new invitation row
        }
    }

    private func setRole(_ m: ListMember, _ role: String) {
        guard role != m.role else { return }
        AppActions.perform("Change role") {
            try await ListMembershipActions.changeRole(listId: list.id, userId: m.userId, to: role)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    private func remove(_ m: ListMember) {
        AppActions.perform("Remove member") {
            try await ListMembershipActions.removeMember(listId: list.id, userId: m.userId)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    /// An invitation is addressed by EMAIL on its own resource — it has no userId to remove.
    private func cancelInvite(_ invite: ListInvite) {
        AppActions.perform("Cancel invitation") {
            try await ListMembershipActions.cancelInvitation(listId: list.id, invitationId: invite.id,
                                                            email: invite.email)
        }
    }

    private func setInviteRole(_ invite: ListInvite, _ role: String) {
        guard role != invite.role else { return }
        AppActions.perform("Change invitation role") {
            try await ListMembershipActions.changeInvitationRole(listId: list.id, invitationId: invite.id,
                                                                 email: invite.email, to: role)
        }
    }

    private func addAgent(_ agent: User) {
        AppActions.perform("Add \(agent.displayName)") {
            try await ListMembershipActions.addAgent(agent, toList: list.id)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    /// Resolving the agent's user id from its email is shared (AITD-399) — this used to be a
    /// bare `guard ... else { return }`, so an agent that was not on the list failed silently.
    private func removeAgent(_ agent: User) {
        AppActions.perform("Remove \(agent.displayName)") {
            try await ListMembershipActions.removeAgent(agent, fromList: currentList, roster: members)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    private func leave() {
        AppActions.perform("Leave list") {
            try await ListService.shared.leaveList(listId: list.id)
        }
    }

    /// Ask the server who this list may be handed to (AITD-392).
    ///
    /// Through `ListService`, never `AstridAPIClient` — ASTRID.md §0 rule 1. It cannot throw:
    /// every outcome is a state to render, including the server not knowing the route.
    private func loadTransferAvailability() async {
        transferAvailability = await ListService.shared
            .ownershipTransferAvailability(listId: list.id)
    }

    /// Hand it over and leave, in ONE call — the server does both in a single transaction, so
    /// there is deliberately no `leaveList` after this.
    private func transferOwnership() {
        guard !successorId.isEmpty else { return }
        AppActions.perform("Transfer list ownership") {
            try await ListMembershipActions.transferOwnership(listId: list.id, to: successorId)
        }
    }
}
#endif
