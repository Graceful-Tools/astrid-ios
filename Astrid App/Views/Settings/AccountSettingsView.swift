import SwiftUI
import PhotosUI

struct AccountSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = AccountViewModel()

    @State private var showImagePicker = false
    @State private var showExportSheet = false
    @State private var exportFileURL: URL?

    // Passkey state
    @State private var passkeys: [PasskeyManager.PasskeyInfo] = []
    @State private var isLoadingPasskeys = true
    @State private var isAddingPasskey = false
    @State private var passkeyError: String?
    @State private var editingPasskeyId: String?
    @State private var editingPasskeyName: String = ""
    @State private var deletingPasskeyId: String?

    var body: some View {
        ZStack {
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FloatingTextHeader(NSLocalizedString("account_access", comment: ""), icon: "person.circle", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                if viewModel.isLoading {
                    Spacer()
                    ProgressView(NSLocalizedString("settings.account.loading", comment: ""))
                    Spacer()
                } else {
                    List {
                        // Profile Section
                        profileSection

                        // Email Verification Section
                        if !viewModel.isEmailVerified || viewModel.hasPendingEmailChange || viewModel.hasPendingVerification {
                            emailVerificationSection
                        }

                        // Account Info Section
                        accountInfoSection

                        // Passkeys Section
                        passkeysSection

                        // Data Section
                        dataSection

                        // Danger Zone
                        dangerZoneSection
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .photosPicker(isPresented: $showImagePicker, selection: Binding(
            get: { nil },
            set: { newValue in
                if let newValue {
                    loadImage(from: newValue)
                }
            }
        ), matching: .images)
        .sheet(isPresented: $showExportSheet) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert(NSLocalizedString("messages.error", comment: ""), isPresented: $viewModel.showError) {
            Button(NSLocalizedString("actions.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(NSLocalizedString("messages.success", comment: ""), isPresented: $viewModel.showSuccess) {
            Button(NSLocalizedString("actions.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(viewModel.successMessage)
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            // Profile Photo
            HStack {
                profileImageView
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName)
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    Text(viewModel.email)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }

                Spacer()

                Button {
                    showImagePicker = true
                } label: {
                    if viewModel.isUploadingImage {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "camera.fill")
                            .foregroundColor(Theme.accent)
                    }
                }
                .disabled(viewModel.isUploadingImage)
            }
            .padding(.vertical, 8)

            // Display Name
            HStack {
                Label(NSLocalizedString("settings.account.display_name", comment: ""), systemImage: "person")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                TextField(NSLocalizedString("settings.account.name_placeholder", comment: ""), text: $viewModel.editedName)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            // Email Address
            HStack {
                Label(NSLocalizedString("auth.email", comment: ""), systemImage: "envelope")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                TextField(NSLocalizedString("settings.account.email_placeholder", comment: ""), text: $viewModel.editedEmail)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }

            // Save Button (only show when there are changes)
            if viewModel.hasChanges {
                Button {
                    _Concurrency.Task {
                        if viewModel.hasImageChanges && viewModel.selectedImage != nil {
                            await viewModel.uploadImage()
                        }
                        await viewModel.saveChanges()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving || viewModel.isUploadingImage {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("messages.saving", comment: ""))
                        } else {
                            Text(NSLocalizedString("settings.account.save_changes", comment: ""))
                        }
                        Spacer()
                    }
                }
                .foregroundColor(Theme.accent)
                .disabled(viewModel.isSaving || viewModel.isUploadingImage)
            }
        } header: {
            Text(NSLocalizedString("profile.title", comment: ""))
        } footer: {
            if viewModel.isOAuthUser {
                Text(NSLocalizedString("settings.account.oauth_footer", comment: ""))
            }
        }
    }

    private var profileImageView: some View {
        Group {
            if let selectedImage = viewModel.selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
            } else if let imageUrl = viewModel.profileImageUrl, let url = URL(string: imageUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.2))
            Text(viewModel.initials)
                .font(Theme.Typography.headline())
                .foregroundColor(Theme.accent)
        }
    }

    // MARK: - Email Verification Section

    private var emailVerificationSection: some View {
        Section {
            if viewModel.hasPendingEmailChange, let pendingEmail = viewModel.pendingEmail {
                // Pending email change
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(NSLocalizedString("settings.account.pending_email", comment: ""), systemImage: "envelope.badge.shield.half.filled")
                            .foregroundColor(.orange)
                        Text(pendingEmail)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                    Spacer()
                }

                Button {
                    _Concurrency.Task {
                        await viewModel.resendVerificationEmail()
                    }
                } label: {
                    Label(NSLocalizedString("settings.account.resend_verification", comment: ""), systemImage: "arrow.clockwise")
                        .foregroundColor(Theme.accent)
                }
                .disabled(viewModel.isSaving)

                Button(role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.cancelEmailChange()
                    }
                } label: {
                    Label(NSLocalizedString("settings.account.cancel_change", comment: ""), systemImage: "xmark.circle")
                }
                .disabled(viewModel.isSaving)

            } else if !viewModel.isEmailVerified {
                // Email not verified
                HStack {
                    Label(NSLocalizedString("settings.account.email_not_verified", comment: ""), systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Spacer()
                }

                Button {
                    _Concurrency.Task {
                        await viewModel.sendVerificationEmail()
                    }
                } label: {
                    HStack {
                        Label(NSLocalizedString("settings.account.send_verification", comment: ""), systemImage: "envelope")
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .foregroundColor(Theme.accent)
                .disabled(viewModel.isSaving)
            }
        } header: {
            Text(NSLocalizedString("settings.account.email_verification", comment: ""))
        } footer: {
            if viewModel.hasPendingEmailChange {
                Text(NSLocalizedString("settings.account.pending_email_footer", comment: ""))
            } else if !viewModel.isEmailVerified {
                Text(NSLocalizedString("settings.account.verify_email_footer", comment: ""))
            }
        }
    }

    // MARK: - Account Info Section

    private var accountInfoSection: some View {
        Section(NSLocalizedString("settings.account.info", comment: "")) {
            HStack {
                Label(NSLocalizedString("settings.account.id", comment: ""), systemImage: "number")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                Text(String(viewModel.accountId.prefix(8)) + "...")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            HStack {
                Label(NSLocalizedString("settings.account.created", comment: ""), systemImage: "calendar")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                Text(viewModel.accountCreatedDate)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            HStack {
                Label(NSLocalizedString("settings.account.auth_method", comment: ""), systemImage: "key")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                Text(viewModel.isOAuthUser ? NSLocalizedString("settings.account.google", comment: "") : NSLocalizedString("settings.account.passkey", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }
        }
    }

    // MARK: - Passkeys Section

    private var passkeysSection: some View {
        Section {
            if isLoadingPasskeys {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("settings.account.loading_passkeys", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Spacer()
                }
            } else if passkeys.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 32))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text(NSLocalizedString("settings.account.no_passkeys_registered", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Text(NSLocalizedString("settings.account.add_passkey_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(passkeys) { passkey in
                    passkeyRow(passkey)
                }
            }

            // Add Passkey Button
            Button {
                _Concurrency.Task { await addPasskey() }
            } label: {
                HStack {
                    if isAddingPasskey {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("settings.account.adding_passkey", comment: ""))
                    } else {
                        Image(systemName: "plus.circle.fill")
                        Text(NSLocalizedString("settings.account.add_passkey_button", comment: ""))
                    }
                }
                .foregroundColor(Color(red: 0.35, green: 0.34, blue: 0.84))
            }
            .disabled(isAddingPasskey)

            if let error = passkeyError {
                Text(error)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(.red)
            }
        } header: {
            Text(NSLocalizedString("settings.account.passkeys", comment: ""))
        } footer: {
            Text(NSLocalizedString("settings.account.passkeys_footer", comment: ""))
        }
        .onAppear {
            _Concurrency.Task { await loadPasskeys() }
        }
    }

    private func passkeyRow(_ passkey: PasskeyManager.PasskeyInfo) -> some View {
        HStack {
            Image(systemName: "person.badge.key.fill")
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                if editingPasskeyId == passkey.id {
                    TextField(NSLocalizedString("settings.account.passkey_name_placeholder", comment: ""), text: $editingPasskeyName)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .onSubmit {
                            _Concurrency.Task { await renamePasskey(passkey.id) }
                        }
                } else {
                    Text(passkey.name ?? NSLocalizedString("settings.account.passkey", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }

                Text(formatPasskeyDate(passkey.createdAt) + (passkey.credentialBackedUp ? " • " + NSLocalizedString("settings.account.synced", comment: "") : ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
            }

            Spacer()

            if editingPasskeyId == passkey.id {
                HStack(spacing: 4) {
                    Button {
                        _Concurrency.Task { await renamePasskey(passkey.id) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Button {
                        editingPasskeyId = nil
                        editingPasskeyName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        editingPasskeyId = passkey.id
                        editingPasskeyName = passkey.name ?? NSLocalizedString("settings.account.passkey", comment: "")
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }

                    Button {
                        _Concurrency.Task { await deletePasskey(passkey.id) }
                    } label: {
                        if deletingPasskeyId == passkey.id {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(deletingPasskeyId == passkey.id)
                }
            }
        }
    }

    private func formatPasskeyDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return String(format: NSLocalizedString("settings.account.added_on", comment: ""), displayFormatter.string(from: date))
        }
        return NSLocalizedString("settings.account.added_recently", comment: "")
    }

    private func loadPasskeys() async {
        isLoadingPasskeys = true
        do {
            passkeys = try await PasskeyManager.shared.getPasskeys()
        } catch {
            AppLog.debug("Failed to load passkeys: \(error)")
        }
        isLoadingPasskeys = false
    }

    private func addPasskey() async {
        isAddingPasskey = true
        passkeyError = nil
        do {
            let success = try await PasskeyManager.shared.registerForExistingUser(name: "My Passkey")
            if success {
                await loadPasskeys()
            }
        } catch let error as PasskeyError {
            if case .userCancelled = error {
                // User cancelled, don't show error
            } else {
                passkeyError = error.localizedDescription
            }
        } catch {
            passkeyError = error.localizedDescription
        }
        isAddingPasskey = false
    }

    private func renamePasskey(_ id: String) async {
        guard !editingPasskeyName.isEmpty else { return }
        do {
            try await PasskeyManager.shared.renamePasskey(id: id, name: editingPasskeyName)
            editingPasskeyId = nil
            editingPasskeyName = ""
            await loadPasskeys()
        } catch {
            passkeyError = NSLocalizedString("settings.account.rename_failed", comment: "")
        }
    }

    private func deletePasskey(_ id: String) async {
        deletingPasskeyId = id
        do {
            try await PasskeyManager.shared.deletePasskey(id: id)
            await loadPasskeys()
        } catch {
            passkeyError = NSLocalizedString("settings.account.delete_failed", comment: "")
        }
        deletingPasskeyId = nil
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section {
            Button {
                _Concurrency.Task {
                    if let url = await viewModel.exportData(format: "json") {
                        exportFileURL = url
                        showExportSheet = true
                    }
                }
            } label: {
                HStack {
                    Label(NSLocalizedString("settings.account.export_json", comment: ""), systemImage: "square.and.arrow.up")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                    if viewModel.isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
            }
            .disabled(viewModel.isExporting)

            Button {
                _Concurrency.Task {
                    if let url = await viewModel.exportData(format: "csv") {
                        exportFileURL = url
                        showExportSheet = true
                    }
                }
            } label: {
                HStack {
                    Label(NSLocalizedString("settings.account.export_csv", comment: ""), systemImage: "tablecells")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                    if viewModel.isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
            }
            .disabled(viewModel.isExporting)
        } header: {
            Text(NSLocalizedString("settings.account.your_data", comment: ""))
        } footer: {
            Text(NSLocalizedString("settings.account.your_data_footer", comment: ""))
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            NavigationLink(destination: DeleteAccountView(viewModel: viewModel)) {
                Label(NSLocalizedString("settings.account.delete_account", comment: ""), systemImage: "trash")
                    .foregroundColor(.red)
            }
        } header: {
            Text(NSLocalizedString("settings.account.danger_zone", comment: ""))
        } footer: {
            Text(NSLocalizedString("settings.account.delete_account_footer", comment: ""))
        }
    }

    // MARK: - Helper Methods

    private func loadImage(from item: PhotosPickerItem) {
        _Concurrency.Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                viewModel.selectedImage = image
            }
        }
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView()
            .environmentObject(AuthManager.shared)
    }
}
