//  MacListMembersView.swift
//  Astrid for Mac — list sharing: members & roles (D2, Task e3413a5b). Via ListMemberService
//  (offline-queued). Role selection on invite + per-member role changes, permission-gated so
//  only an owner/admin sees management controls; the list owner is never editable/removable.

#if os(macOS)
import SwiftUI

struct MacListMembersView: View {
    let list: TaskList
    @StateObject private var svc = ListMemberService.shared
    @State private var email = ""
    @State private var inviteRole = "member"
    @State private var privacy = "PRIVATE"
    @State private var publicType = "collaborative"
    @State private var contactSuggestions: [ContactSearchResult] = []
    @State private var loadingMembers = true      // first-fetch spinner (1c3562e9)
    @Environment(\.dismiss) private var dismiss

    private static let roles = ["member", "admin"]

    private var members: [ListMember] { svc.membersByList[list.id] ?? [] }
    private var canInvite: Bool { email.contains("@") && email.contains(".") }

    /// The current user's role on this list ("owner" via ownerId, else their member role).
    private var myRole: String? {
        let uid = AuthManager.shared.userId
        if list.ownerId == uid { return "owner" }
        return members.first { $0.userId == uid }?.role
    }
    private var canManage: Bool { myRole == "owner" || myRole == "admin" }
    private func isOwner(_ m: ListMember) -> Bool { m.userId == list.ownerId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: NSLocalizedString("mac.share_title", comment: ""), list.name)).font(.headline).foregroundStyle(Theme.textPrimary)

            // Privacy + public type (owner/admin only) — Task 7d77a054.
            if canManage {
                HStack {
                    Picker(NSLocalizedString("mac.privacy", comment: ""), selection: $privacy) {
                        ForEach(MacListPrivacy.privacy) { Text($0.label).tag($0.value) }
                    }.onChange(of: privacy) { savePrivacy() }
                    if privacy == "PUBLIC" {
                        Picker(NSLocalizedString("mac.type", comment: ""), selection: $publicType) {
                            ForEach(MacListPrivacy.publicType) { Text($0.label).tag($0.value) }
                        }.onChange(of: publicType) { savePrivacy() }
                    }
                }
            }

            List {
                ForEach(members) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.user?.displayName ?? m.userId).foregroundStyle(Theme.textPrimary)
                            Text(isOwner(m) ? "Owner" : m.role.capitalized)
                                .font(.caption).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        // Only owner/admin can change roles, and never the list owner's row.
                        if canManage && !isOwner(m) {
                            Picker("", selection: Binding(
                                get: { m.role },
                                set: { setRole(m, $0) }
                            )) {
                                ForEach(Self.roles, id: \.self) { Text(MacMemberRoleLabel.title(for: $0)).tag($0) }
                            }
                            .labelsHidden().frame(width: 110)
                            Button(role: .destructive) { remove(m) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.error)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if members.isEmpty {
                    if loadingMembers {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(NSLocalizedString("mac.loading_members", comment: "")) }
                            .foregroundStyle(Theme.textMuted)
                    } else {
                        Text(NSLocalizedString("mac.no_members", comment: "")).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            .frame(minHeight: 180)

            if canManage {
                // Contacts autocomplete (server-synced contacts via the shared ContactsService) — 3753a521.
                if !contactSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(contactSuggestions) { c in
                            Button { email = c.email; contactSuggestions = [] } label: {
                                Text(MacContactPick.display(name: c.name, email: c.email))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 3).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    TextField(NSLocalizedString("members.invite_email", comment: ""), text: $email).textFieldStyle(.roundedBorder)
                        .onSubmit(invite)
                        .onChange(of: email) { searchContacts() }
                    Picker("", selection: $inviteRole) {
                        ForEach(Self.roles, id: \.self) { Text(MacMemberRoleLabel.title(for: $0)).tag($0) }
                    }.labelsHidden().frame(width: 110)
                    Button(NSLocalizedString("mac.invite", comment: ""), action: invite).disabled(!canInvite)
                }
            } else {
                Text(NSLocalizedString("mac.members_admin_only", comment: ""))
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }

            HStack { Spacer(); Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.return, modifiers: []) }
        }
        .padding(20)
        .frame(width: 440)
        .background(Theme.bgPrimary)
        .task { try? await svc.fetchMembers(listId: list.id); loadingMembers = false }
        .onAppear {
            privacy = list.privacy?.rawValue ?? "PRIVATE"
            publicType = list.publicListType ?? "collaborative"
        }
    }

    /// Autocomplete the invite field from server-synced contacts (shared ContactsService).
    private func searchContacts() {
        let q = email.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, !q.contains("@") else { contactSuggestions = []; return }
        _Concurrency.Task {
            let hits = (try? await ContactsService.shared.searchContacts(query: q, excludeListId: list.id)) ?? []
            contactSuggestions = Array(hits.prefix(5))
        }
    }

    private func savePrivacy() {
        MacActions.perform("Update list privacy") {
            _ = try await ListService.shared.updateListAdvanced(
                listId: list.id, updates: MacListPrivacy.updates(privacy: privacy, publicType: publicType))
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func invite() {
        guard canInvite else { return }
        let e = email.trimmingCharacters(in: .whitespaces)
        let role = inviteRole
        // Surface failures and keep the email in the field until it actually succeeds.
        MacActions.perform("Invite \(e)") {
            _ = try await svc.addMember(listId: list.id, email: e, role: role)
            email = ""
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    private func setRole(_ m: ListMember, _ role: String) {
        guard role != m.role else { return }
        MacActions.perform("Change role") {
            try await svc.updateMemberRole(listId: list.id, userId: m.userId, role: role)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    private func remove(_ m: ListMember) {
        MacActions.perform("Remove member") {
            try await svc.removeMember(listId: list.id, userId: m.userId)
            try? await svc.fetchMembers(listId: list.id)
        }
    }
}
#endif
