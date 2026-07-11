import Foundation
import SwiftUI
import Combine

@MainActor
class AccountViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var accountData: AccountData?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isExporting = false
    @Published var isDeleting = false

    // Edit states
    @Published var editedName: String = ""
    @Published var editedEmail: String = ""
    @Published var selectedImage: UIImage?
    @Published var isUploadingImage = false

    // Alerts and messages
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showSuccess = false
    @Published var successMessage = ""

    // Delete account
    @Published var deleteConfirmationText: String = ""

    private let apiClient = AccountService.shared
    private let authManager = AuthManager.shared
    private let profileCache = ProfileCache.shared
    private var uploadedImageUrl: String?

    // MARK: - Computed Properties

    var hasAccountData: Bool {
        accountData != nil
    }

    var displayName: String {
        accountData?.name ?? NSLocalizedString("settings.account.no_name", comment: "")
    }

    var email: String {
        accountData?.email ?? ""
    }

    var profileImageUrl: String? {
        accountData?.image
    }

    var isEmailVerified: Bool {
        accountData?.verified ?? false
    }

    var hasPendingEmailChange: Bool {
        accountData?.hasPendingChange ?? false
    }

    var pendingEmail: String? {
        accountData?.pendingEmail
    }

    var hasPendingVerification: Bool {
        accountData?.hasPendingVerification ?? false
    }

    var isOAuthUser: Bool {
        accountData?.verifiedViaOAuth ?? false
    }

    var initials: String {
        if let name = accountData?.name, !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }
        return String(email.prefix(2)).uppercased()
    }

    var accountCreatedDate: String {
        guard let date = accountData?.createdAt else { return NSLocalizedString("settings.account.unknown", comment: "") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    var accountId: String {
        accountData?.id ?? NSLocalizedString("settings.account.unknown", comment: "")
    }

    var hasNameChanges: Bool {
        editedName != (accountData?.name ?? "")
    }

    var hasEmailChanges: Bool {
        editedEmail != (accountData?.email ?? "")
    }

    var hasImageChanges: Bool {
        uploadedImageUrl != nil || selectedImage != nil
    }

    var hasChanges: Bool {
        hasNameChanges || hasEmailChanges || hasImageChanges
    }

    var isValidEmail: Bool {
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return emailPredicate.evaluate(with: editedEmail)
    }

    var canDeleteAccount: Bool {
        deleteConfirmationText == NSLocalizedString("settings.account.delete_confirm_phrase", comment: "")
    }

    // MARK: - Initialization

    init() {
        // Load account data on init
        _Concurrency.Task {
            await loadAccount()
        }
    }

    // MARK: - Account Operations

    func loadAccount() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await apiClient.getAccount()
            accountData = data
            editedName = data.name ?? ""
            editedEmail = data.email
            print("✅ [AccountViewModel] Account loaded: \(data.email)")

            // Sync profile changes to AuthManager and clear ProfileCache
            syncProfileToApp(data)
        } catch {
            print("❌ [AccountViewModel] Failed to load account: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_load", comment: ""), error.localizedDescription)
            showError = true
        }
    }

    /// Sync profile data to AuthManager and clear ProfileCache so other views get updated data
    private func syncProfileToApp(_ data: AccountData) {
        // Update AuthManager's currentUser with new profile data
        if var currentUser = authManager.currentUser {
            currentUser.name = data.name
            currentUser.image = data.image
            authManager.updateCurrentUser(currentUser)
            print("✅ [AccountViewModel] Synced profile to AuthManager")
        }

        // Clear ProfileCache for this user so UserProfileView reloads fresh data
        profileCache.clearCache(userId: data.id)
        print("✅ [AccountViewModel] Cleared ProfileCache for user: \(data.id)")
    }

    func saveChanges() async {
        guard hasChanges else { return }

        if hasEmailChanges && !isValidEmail {
            errorMessage = NSLocalizedString("settings.account.invalid_email", comment: "")
            showError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let nameToSend = hasNameChanges ? (editedName.isEmpty ? nil : editedName) : nil
            let emailToSend = hasEmailChanges ? editedEmail : nil
            let imageToSend = uploadedImageUrl

            let response = try await apiClient.updateAccount(
                name: nameToSend,
                email: emailToSend,
                image: imageToSend
            )

            print("✅ [AccountViewModel] Account updated: \(response.message)")

            // Reload account to get updated data
            await loadAccount()

            // Clear uploaded image reference
            uploadedImageUrl = nil
            selectedImage = nil

            if response.emailVerificationRequired == true {
                successMessage = NSLocalizedString("settings.account.profile_updated_verify", comment: "")
            } else {
                successMessage = NSLocalizedString("settings.account.profile_updated_success", comment: "")
            }
            showSuccess = true

        } catch {
            print("❌ [AccountViewModel] Failed to save changes: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_save", comment: ""), error.localizedDescription)
            showError = true
        }
    }

    func uploadImage() async {
        guard let image = selectedImage else { return }

        isUploadingImage = true
        defer { isUploadingImage = false }

        do {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                errorMessage = NSLocalizedString("settings.account.failed_process_image", comment: "")
                showError = true
                return
            }

            let response = try await apiClient.uploadProfileImage(
                imageData,
                fileName: "profile-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg"
            )

            uploadedImageUrl = response.url
            print("✅ [AccountViewModel] Image uploaded: \(response.url)")

        } catch {
            print("❌ [AccountViewModel] Upload failed: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_upload_image", comment: ""), error.localizedDescription)
            showError = true
            selectedImage = nil
        }
    }

    // MARK: - Email Verification

    func resendVerificationEmail() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let response = try await apiClient.verifyEmail(action: "resend")
            print("✅ [AccountViewModel] Verification email sent: \(response.message)")
            successMessage = response.message
            showSuccess = true
        } catch {
            print("❌ [AccountViewModel] Failed to resend verification: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_send_verification", comment: ""), error.localizedDescription)
            showError = true
        }
    }

    func cancelEmailChange() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let response = try await apiClient.verifyEmail(action: "cancel")
            print("✅ [AccountViewModel] Email change cancelled: \(response.message)")
            await loadAccount()
            successMessage = NSLocalizedString("settings.account.email_change_cancelled", comment: "")
            showSuccess = true
        } catch {
            print("❌ [AccountViewModel] Failed to cancel email change: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_cancel_email_change", comment: ""), error.localizedDescription)
            showError = true
        }
    }

    func sendVerificationEmail() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let response = try await apiClient.verifyEmail(action: "send")
            print("✅ [AccountViewModel] Verification email sent: \(response.message)")
            successMessage = response.message
            showSuccess = true
        } catch {
            print("❌ [AccountViewModel] Failed to send verification: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_send_verification", comment: ""), error.localizedDescription)
            showError = true
        }
    }

    // MARK: - Data Export

    func exportData(format: String) async -> URL? {
        isExporting = true
        defer { isExporting = false }

        do {
            let data = try await apiClient.exportAccountData(format: format)

            // Save to temporary file
            let fileName = "astrid-export-\(Date().ISO8601Format()).\(format)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)

            print("✅ [AccountViewModel] Data exported to: \(tempURL)")
            return tempURL

        } catch {
            print("❌ [AccountViewModel] Failed to export data: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_export", comment: ""), error.localizedDescription)
            showError = true
            return nil
        }
    }

    // MARK: - Account Deletion

    func deleteAccount() async -> Bool {
        guard canDeleteAccount else { return false }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let response = try await apiClient.deleteAccount(
                confirmationText: deleteConfirmationText
            )

            print("✅ [AccountViewModel] Account deleted: \(response.message)")
            return true

        } catch {
            print("❌ [AccountViewModel] Failed to delete account: \(error)")
            errorMessage = String(format: NSLocalizedString("settings.account.failed_delete", comment: ""), error.localizedDescription)
            showError = true
            return false
        }
    }

    // MARK: - Reset

    func resetEditedValues() {
        editedName = accountData?.name ?? ""
        editedEmail = accountData?.email ?? ""
        selectedImage = nil
        uploadedImageUrl = nil
    }

    func resetDeleteFields() {
        deleteConfirmationText = ""
    }
}
