import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @ThemedPalette private var palette
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: EditProfileViewModel
    @EnvironmentObject var authManager: AuthManager

    init(accountData: AccountData) {
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(accountData: accountData))
    }

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Native iOS header
                FloatingTextHeader("Edit Profile", icon: "person.circle", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                ScrollView {
                    VStack(spacing: Theme.spacing24) {
                        // Profile Photo Section
                        profilePhotoSection

                        // Form Fields
                        formSection

                        // Save Button
                        saveButton
                    }
                    .padding(Theme.spacing16)
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") {
                // Update auth manager with new user data
                if let updatedUser = viewModel.updatedUser {
                    authManager.updateCurrentUser(updatedUser)
                }
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("profile.updated_success", comment: "Your profile has been updated successfully!"))
        }
    }

    // MARK: - Profile Photo Section

    private var profilePhotoSection: some View {
        VStack(spacing: Theme.spacing16) {
            // Avatar with edit overlay
            ZStack(alignment: .bottomTrailing) {
                if let selectedImage = viewModel.selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else if let imageUrl = viewModel.imageUrl, let url = URL(string: imageUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Theme.accent)
                            .overlay {
                                Text(viewModel.initials)
                                    .foregroundColor(.white)
                                    .font(.system(size: 48, weight: .bold))
                            }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 120, height: 120)
                        .overlay {
                            Text(viewModel.initials)
                                .foregroundColor(.white)
                                .font(.system(size: 48, weight: .bold))
                        }
                }

                // Edit button
                Button {
                    viewModel.showImagePicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 36, height: 36)
                        Image(systemName: "camera.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                    }
                }
                .offset(x: -4, y: -4)
            }

            Text(NSLocalizedString("profile.tap_change_photo", comment: "Tap to change photo"))
                .font(Theme.Typography.caption1())
                .foregroundColor(palette.textMuted)

            if viewModel.isUploading {
                HStack(spacing: Theme.spacing8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("profile.uploading_photo", comment: "Uploading photo..."))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(palette.textMuted)
                }
            }
        }
        // The system Photos picker runs out of process and opens at once. A
        // `UIImagePickerController(.photoLibrary)` in a sheet loaded the library in process
        // and showed a blank screen for seconds first (AITD-675).
        .photosPicker(isPresented: $viewModel.showImagePicker, selection: Binding(
            get: { nil },
            set: { item in
                if let item { handleImageSelection(item) }
            }
        ), matching: .images)
    }

    // MARK: - Helper Methods

    private func handleImageSelection(_ item: PhotosPickerItem) {
        _Concurrency.Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            viewModel.selectedImage = image
            await viewModel.uploadImage()
        }
    }

    private func handleSaveButton() {
        _Concurrency.Task {
            await viewModel.saveChanges()
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: Theme.spacing16) {
            // Display Name
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("profile.display_name", comment: "Display Name"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)

                TextField("Enter your name", text: $viewModel.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                    .padding(Theme.spacing12)
                    .background(palette.bgTertiary)
                    .cornerRadius(Theme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(palette.border, lineWidth: 1)
                    )
            }

            // Email
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("profile.email_address", comment: "Email Address"))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)

                TextField("Enter your email", text: $viewModel.email)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .disableAutocorrection(true)
                    .padding(Theme.spacing12)
                    .background(palette.bgTertiary)
                    .cornerRadius(Theme.radiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(palette.border, lineWidth: 1)
                    )
            }

            // Info note
            if viewModel.isOAuthUser {
                HStack(spacing: Theme.spacing8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(Theme.accent)
                    Text("Your profile photo is synced with your \(viewModel.oauthProvider) account. You can override it by uploading a custom photo above.")
                        .font(Theme.Typography.caption2())
                        .foregroundColor(palette.textMuted)
                }
                .padding(Theme.spacing12)
                .background(Theme.accent.opacity(0.1))
                .cornerRadius(Theme.radiusMedium)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(
            action: handleSaveButton,
            label: {
                HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("profile.saving", comment: "Saving..."))
                } else {
                    Text(NSLocalizedString("profile.save_changes", comment: "Save Changes"))
                }
            }
            .frame(maxWidth: .infinity)
            .font(Theme.Typography.body())
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(Theme.spacing16)
            .background(viewModel.hasChanges ? Theme.accent : Theme.accent.opacity(0.5))
            .cornerRadius(Theme.radiusMedium)
            }
        )
        .disabled(!viewModel.hasChanges || viewModel.isSaving || viewModel.isUploading)
    }
}

#Preview {
    NavigationStack {
        EditProfileView(accountData: AccountData(
            id: "test-id",
            name: "John Doe",
            email: "john@example.com",
            emailVerified: Date(),
            image: nil,
            pendingEmail: nil,
            createdAt: Date(),
            updatedAt: Date(),
            verified: true,
            hasPendingChange: false,
            hasPendingVerification: false,
            verifiedViaOAuth: true
        ))
        .environmentObject(AuthManager.shared)
    }
}
