//  MacListMembersView.swift
//  Astrid for Mac — list sharing: members & roles (D2). Via ListMemberService (offline-queued).

#if os(macOS)
import SwiftUI

struct MacListMembersView: View {
    let list: TaskList
    @StateObject private var svc = ListMemberService.shared
    @State private var email = ""
    @Environment(\.dismiss) private var dismiss

    private var members: [ListMember] { svc.membersByList[list.id] ?? [] }
    private var canInvite: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share “\(list.name)”").font(.headline).foregroundStyle(Theme.textPrimary)

            List {
                ForEach(members) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.user?.displayName ?? m.userId).foregroundStyle(Theme.textPrimary)
                            Text(m.role.capitalized).font(.caption).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Button(role: .destructive) { remove(m) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Theme.error)
                        }.buttonStyle(.plain)
                    }
                }
                if members.isEmpty {
                    Text("No members yet").foregroundStyle(Theme.textMuted)
                }
            }
            .frame(minHeight: 180)

            HStack {
                TextField("Invite by email", text: $email).textFieldStyle(.roundedBorder).onSubmit(invite)
                Button("Invite", action: invite).disabled(!canInvite)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.return, modifiers: []) }
        }
        .padding(20)
        .frame(width: 420)
        .task { try? await svc.fetchMembers(listId: list.id) }
    }

    private func invite() {
        guard canInvite else { return }
        let e = email.trimmingCharacters(in: .whitespaces); email = ""
        _Concurrency.Task {
            _ = try? await svc.addMember(listId: list.id, email: e)
            try? await svc.fetchMembers(listId: list.id)
        }
    }

    private func remove(_ m: ListMember) {
        _Concurrency.Task {
            try? await svc.removeMember(listId: list.id, userId: m.userId)
            try? await svc.fetchMembers(listId: list.id)
        }
    }
}
#endif
