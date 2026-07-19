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
            Text("Share “\(list.name)”").font(.headline).foregroundStyle(Theme.textPrimary)

            // Privacy + public type (owner/admin only) — Task 7d77a054.
            if canManage {
                HStack {
                    Picker("Privacy", selection: $privacy) {
                        ForEach(MacListPrivacy.privacy) { Text($0.label).tag($0.value) }
                    }.onChange(of: privacy) { savePrivacy() }
                    if privacy == "PUBLIC" {
                        Picker("Type", selection: $publicType) {
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
                                ForEach(Self.roles, id: \.self) { Text($0.capitalized).tag($0) }
                            }
                            .labelsHidden().frame(width: 110)
                            Button(role: .destructive) { remove(m) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.error)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if members.isEmpty {
                    Text("No members yet").foregroundStyle(Theme.textMuted)
                }
            }
            .frame(minHeight: 180)

            if canManage {
                HStack {
                    TextField("Invite by email", text: $email).textFieldStyle(.roundedBorder).onSubmit(invite)
                    Picker("", selection: $inviteRole) {
                        ForEach(Self.roles, id: \.self) { Text($0.capitalized).tag($0) }
                    }.labelsHidden().frame(width: 110)
                    Button("Invite", action: invite).disabled(!canInvite)
                }
            } else {
                Text("Only the list owner or an admin can manage members.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
            }

            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.return, modifiers: []) }
        }
        .padding(20)
        .frame(width: 440)
        .task { try? await svc.fetchMembers(listId: list.id) }
        .onAppear {
            privacy = list.privacy?.rawValue ?? "PRIVATE"
            publicType = list.publicListType ?? "collaborative"
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
