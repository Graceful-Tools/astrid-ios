//  MacUserProfileView.swift
//  Astrid for Mac — a user's profile (Task 0994eabb).
//
//  Mirrors iOS UserProfileView: avatar, name, email, member-since, the three stat cards
//  (completed / inspired / supported) and the tasks you share with that person. Data comes from
//  the SHARED ProfileCache, so the Mac shows exactly what iOS and web show.

#if os(macOS)
import SwiftUI

struct MacUserProfileView: View {
    let userId: String
    @Environment(\.dismiss) private var dismiss

    @State private var profile: UserProfileResponse?
    @State private var errorMessage: String?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.callout).foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center).padding(24)
                } else if let profile {
                    ScrollView { content(profile) .padding(20) }
                        .macScrollBars(false)
                        .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 460, height: 560)
        .background(Theme.bgPrimary)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text(NSLocalizedString("profile.title", comment: "")).font(.headline)
            Spacer()
            Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder private func content(_ profile: UserProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                MacAuthorAvatar(display: MacAuthorDisplay.of(authorId: profile.user.id,
                                                             author: User(id: profile.user.id,
                                                                          email: profile.user.email,
                                                                          name: profile.user.name,
                                                                          image: profile.user.image),
                                                             currentUser: AuthManager.shared.currentUser),
                                size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.user.name ?? profile.user.email)
                        .font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    Text(profile.user.email).font(.callout).foregroundStyle(Theme.textSecondary)
                    Text(profile.user.createdAt, style: .date)
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }

            ForEach(MacProfileStats.cards(profile.stats), id: \.labelKey) { card in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(card.tint.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: card.symbol).font(.title3).foregroundStyle(card.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.label).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(card.tagline).font(.caption).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Text("\(card.value)").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                }
                .padding(12)
                .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12))
            }

            if !profile.sharedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: NSLocalizedString("profile.shared_tasks_with", comment: ""),
                                profile.user.name ?? profile.user.email))
                        .font(.headline).foregroundStyle(Theme.textPrimary)
                    ForEach(profile.sharedTasks) { task in
                        HStack(spacing: 8) {
                            MacTaskCheckbox(completed: task.completed, priority: task.priority, size: 16,
                                            repeating: MacCheckboxAsset.isRepeating(task.repeating))
                            Text(task.title).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await ProfileCache.shared.loadProfile(userId: userId)
        } catch {
            let status = (error as? APIError).flatMap { apiError -> Int? in
                if case .httpError(let code, _) = apiError { return code }
                return nil
            }
            errorMessage = MacProfileState.message(forStatus: status ?? 0)
        }
    }
}
#endif
