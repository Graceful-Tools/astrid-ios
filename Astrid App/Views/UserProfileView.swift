import SwiftUI
import Combine

struct UserProfileView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: UserProfileViewModel
    @EnvironmentObject var authManager: AuthManager
    @State private var showEditProfile = false
    @State private var accountDataForEdit: AccountData?

    init(userId: String) {
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId))
    }

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(message: error)
            } else if let profile = viewModel.profile {
                profileContent(profile: profile)
            }
        }
        .navigationBarHidden(true)
        .task(id: viewModel.userId) {
            await viewModel.loadProfile()
        }
        .sheet(isPresented: $showEditProfile) {
            if let accountData = accountDataForEdit {
                NavigationStack {
                    EditProfileView(accountData: accountData)
                        .environmentObject(authManager)
                }
            }
        }
        .swipeToDismiss()
    }

    // MARK: - Load Account Data

    private func loadAccountDataAndShowEdit() {
        _Concurrency.Task {
            do {
                let response: AccountResponse = try await APIClient.shared.request(.getAccount)
                accountDataForEdit = response.user
                showEditProfile = true
            } catch {
                print("❌ [UserProfileView] Failed to load account data: \(error)")
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: Theme.spacing16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(NSLocalizedString("profile.loading", comment: ""))
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: Theme.spacing24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(Theme.error)

            Text(message)
                .font(Theme.Typography.headline())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing32)

            Button {
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "arrow.left")
                    Text(NSLocalizedString("profile.go_back", comment: ""))
                }
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .padding(.horizontal, Theme.spacing24)
                .padding(.vertical, Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .cornerRadius(Theme.radiusMedium)
            }
        }
    }

    // MARK: - Profile Content

    private func profileContent(profile: UserProfileResponse) -> some View {
        VStack(spacing: 0) {
            // Native iOS header (like Settings)
            FloatingTextHeader(NSLocalizedString("profile.title", comment: ""), icon: "person.circle", showBackButton: true, onBack: {
                    NotificationCenter.default.post(name: .closeProfile, object: nil)
                })
                .padding(.top, Theme.spacing8)

            // Content
            ScrollView {
                VStack(spacing: Theme.spacing16) {
                    // User info card
                    userInfoCard(user: profile.user)

                    // Statistics cards
                    statsGrid(stats: profile.stats)

                    // Shared tasks section - only show if there are shared tasks
                    if !profile.sharedTasks.isEmpty {
                        sharedTasksSection(tasks: profile.sharedTasks, isOwnProfile: profile.isOwnProfile, user: profile.user)
                    }
                }
                .padding(Theme.spacing16)
            }
        }
    }

    // MARK: - User Info Card

    private func userInfoCard(user: UserProfileData) -> some View {
        let isOwnProfile = viewModel.profile?.isOwnProfile ?? false

        return VStack(spacing: Theme.spacing16) {
            HStack(alignment: .top, spacing: Theme.spacing16) {
                // Avatar - tappable for own profile
                Group {
                    if let imageUrl = user.image, let url = URL(string: imageUrl) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Theme.accent)
                                .overlay {
                                    Text(user.initials)
                                        .foregroundColor(.white)
                                        .font(.system(size: 32, weight: .bold))
                                }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 80, height: 80)
                            .overlay {
                                Text(user.initials)
                                    .foregroundColor(.white)
                                    .font(.system(size: 32, weight: .bold))
                            }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isOwnProfile {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                            .offset(x: -4, y: -4)
                    }
                }
                .onTapGesture {
                    if isOwnProfile {
                        loadAccountDataAndShowEdit()
                    }
                }

                // User details
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    HStack(spacing: Theme.spacing8) {
                        Text(user.displayName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .onTapGesture {
                                if isOwnProfile {
                                    loadAccountDataAndShowEdit()
                                }
                            }

                        if user.isAIAgent == true {
                            Text(NSLocalizedString("profile.ai_agent", comment: ""))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.spacing8)
                                .padding(.vertical, Theme.spacing4)
                                .background(Theme.accent)
                                .cornerRadius(Theme.radiusSmall)
                        }
                    }

                    Text(user.email)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text(String(format: NSLocalizedString("profile.joined", comment: ""), monthYearFormatter.string(from: user.createdAt)))
                            .font(Theme.Typography.caption1())
                    }
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }

                Spacer()
            }
        }
        .padding(Theme.spacing16)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
        .cornerRadius(Theme.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Stats Grid

    private func statsGrid(stats: UserStats) -> some View {
        VStack(spacing: Theme.spacing12) {
            // Completed tasks
            statCard(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                label: NSLocalizedString("stats.completed", comment: ""),
                value: stats.completed,
                tagline: NSLocalizedString("stats.completed_tagline", comment: "")
            )

            // Inspired tasks
            statCard(
                icon: "lightbulb.fill",
                iconColor: .yellow,
                label: NSLocalizedString("stats.inspired", comment: ""),
                value: stats.inspired,
                tagline: NSLocalizedString("stats.inspired_tagline", comment: "")
            )

            // Supported tasks
            statCard(
                icon: "heart.fill",
                iconColor: .blue,
                label: NSLocalizedString("stats.supported", comment: ""),
                value: stats.supported,
                tagline: NSLocalizedString("stats.supported_tagline", comment: "")
            )
        }
    }

    private func statCard(icon: String, iconColor: Color, label: String, value: Int, tagline: String) -> some View {
        HStack(spacing: Theme.spacing12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: Theme.spacing4) {
                // First line: "13 Completed" - both same size, slightly larger
                HStack(spacing: 6) {
                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Text(label)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }

                // Second line: "Getting it done!" (no label prefix)
                Text(tagline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
            }

            Spacer()
        }
        .padding(Theme.spacing16)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
        .cornerRadius(Theme.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Shared Tasks Section

    private func sharedTasksSection(tasks: [Task], isOwnProfile: Bool, user: UserProfileData) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing12) {
            // Section header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                Text(isOwnProfile ? NSLocalizedString("profile.your_tasks", comment: "") : String(format: NSLocalizedString("profile.shared_tasks_with", comment: ""), user.displayName))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                Text("\(tasks.count)")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .padding(.horizontal, Theme.spacing8)
                    .padding(.vertical, Theme.spacing4)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                    )
            }
            .padding(.horizontal, Theme.spacing16)
            .padding(.top, Theme.spacing16)

            // Tasks list
            VStack(spacing: Theme.spacing8) {
                ForEach(tasks) { task in
                    CompactTaskRow(task: task, onToggle: {
                        // Read-only profile view - no toggle action
                    })
                    .padding(.horizontal, Theme.spacing8)
                }
            }
            .padding(.bottom, Theme.spacing16)
        }
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
        .cornerRadius(Theme.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Date Formatter

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
}

// MARK: - View Model

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var profile: UserProfileResponse?
    @Published var isLoading = false
    @Published var error: String?

    let userId: String // Made public for task(id:)
    private let profileCache = ProfileCache.shared
    private var hasLoaded = false

    init(userId: String) {
        self.userId = userId
    }

    func loadProfile() async {
        // Prevent multiple simultaneous loads
        guard !hasLoaded && !isLoading else {
            print("[UserProfileViewModel] Skipping load - already loaded or loading")
            return
        }

        print("[UserProfileViewModel] Starting profile load for user: \(userId)")
        hasLoaded = true
        isLoading = true
        error = nil

        do {
            // Use ProfileCache which checks cache first, then loads from API if needed
            let response = try await profileCache.loadProfile(userId: userId)
            profile = response
            print("[UserProfileViewModel] Profile loaded successfully")
        } catch {
            // For the current user, fall back to locally cached auth data
            if let localProfile = buildOfflineProfile() {
                profile = localProfile
                print("[UserProfileViewModel] Using offline profile from local auth data")
            } else {
                hasLoaded = false // Allow retry on error
                if let apiError = error as? APIError {
                    switch apiError {
                    case .httpError(let statusCode, _):
                        if statusCode == 404 {
                            self.error = NSLocalizedString("profile.error_not_found", comment: "User not found")
                        } else if statusCode == 401 {
                            // For local users, provide a friendlier message
                            self.error = NSLocalizedString("profile.error_not_signed_in", comment: "Sign in to view your profile")
                        } else {
                            self.error = NSLocalizedString("profile.error_load_failed", comment: "Failed to load user profile")
                        }
                    default:
                        self.error = "Failed to load user profile"
                    }
                } else {
                    self.error = "Failed to load user profile"
                }
                print("[UserProfileViewModel] Load failed: \(self.error ?? "unknown")")
            }
        }

        isLoading = false
    }

    /// Build a profile from local auth data when offline (current user only)
    private func buildOfflineProfile() -> UserProfileResponse? {
        guard let currentUser = AuthManager.shared.currentUser,
              currentUser.id == userId else {
            return nil
        }

        let profileData = UserProfileData(
            id: currentUser.id,
            name: currentUser.name,
            email: currentUser.email ?? "",
            image: currentUser.image,
            createdAt: currentUser.createdAt ?? Date(),
            isAIAgent: false,
            aiAgentType: nil
        )

        return UserProfileResponse(
            user: profileData,
            stats: UserStats(completed: 0, inspired: 0, supported: 0),
            sharedTasks: [],
            isOwnProfile: true
        )
    }
}

// MARK: - Helper Extensions

extension UserProfileData {
    var displayName: String {
        name ?? email.split(separator: "@").first.map(String.init) ?? "Unknown User"
    }

    var initials: String {
        if let name = name {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }
        return String(email.prefix(2)).uppercased()
    }
}

#Preview {
    NavigationStack {
        UserProfileView(userId: "test-user-id")
    }
}
