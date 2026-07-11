import Foundation
import SwiftUI
import Combine

@MainActor
class EditProfileViewModel: ObservableObject {
    @Published var name: String
    @Published var email: String
    @Published var imageUrl: String?
    @Published var selectedImage: UIImage?
    @Published var showImagePicker = false
    @Published var isUploading = false
    @Published var isSaving = false
    @Published var showError = false
    @Published var showSuccess = false
    @Published var errorMessage = ""
    @Published var updatedUser: User?

    private let originalAccountData: AccountData
    private let apiClient = AccountService.shared
    private var uploadedImageUrl: String?

    let isOAuthUser: Bool
    let oauthProvider: String

    init(accountData: AccountData) {
        self.originalAccountData = accountData
        self.name = accountData.name ?? ""
        self.email = accountData.email
        self.imageUrl = accountData.image
        self.isOAuthUser = accountData.verifiedViaOAuth ?? false
        self.oauthProvider = isOAuthUser ? "Google" : "Email"
    }

    var initials: String {
        if !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
            } else {
                return String(name.prefix(2)).uppercased()
            }
        }
        return String(email.prefix(2)).uppercased()
    }

    var hasChanges: Bool {
        let nameChanged = name != (originalAccountData.name ?? "")
        let emailChanged = email != originalAccountData.email
        let imageChanged = uploadedImageUrl != nil || selectedImage != nil
        return nameChanged || emailChanged || imageChanged
    }

    func uploadImage() async {
        guard let image = selectedImage else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            // Compress image to JPEG
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                errorMessage = "Failed to process image"
                showError = true
                return
            }

            // Upload to server
            let response: UploadResponse = try await apiClient.uploadProfileImage(
                imageData,
                fileName: "profile-\(UUID().uuidString).jpg",
                mimeType: "image/jpeg"
            )

            // Store the uploaded URL
            uploadedImageUrl = response.url
            print("✅ [EditProfileViewModel] Image uploaded: \(response.url)")

        } catch {
            print("❌ [EditProfileViewModel] Upload failed: \(error)")
            errorMessage = "Failed to upload image: \(error.localizedDescription)"
            showError = true
            selectedImage = nil
        }
    }

    func saveChanges() async {
        guard hasChanges else { return }

        // Validate email format
        if !isValidEmail(email) {
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            // Prepare update request
            var updateRequest = UpdateAccountRequest()

            // Only send changed fields
            if name != (originalAccountData.name ?? "") {
                updateRequest.name = name.isEmpty ? nil : name
            }

            if email != originalAccountData.email {
                updateRequest.email = email
            }

            if let uploadedUrl = uploadedImageUrl {
                updateRequest.image = uploadedUrl
            }

            // Send update to server
            let response: UpdateAccountResponse = try await apiClient.updateAccount(updateRequest)

            print("✅ [EditProfileViewModel] Profile updated: \(response.message)")

            // Fetch updated account data to get the latest user info
            let accountResponse: AccountResponse = try await apiClient.fetchAccountResponse()

            // Create updated User object for AuthManager
            updatedUser = User(
                id: accountResponse.user.id,
                email: accountResponse.user.email,
                name: accountResponse.user.name,
                image: accountResponse.user.image,
                createdAt: accountResponse.user.createdAt,
                defaultDueTime: nil,
                isPending: nil,
                isAIAgent: nil,
                aiAgentType: nil
            )

            showSuccess = true

        } catch let error as APIError {
            print("❌ [EditProfileViewModel] Save failed: \(error)")
            switch error {
            case .httpError(let statusCode, let message):
                errorMessage = message ?? "Failed to update profile (HTTP \(statusCode))"
            case .unauthorized:
                errorMessage = "Please sign in again to update your profile"
            default:
                errorMessage = error.localizedDescription
            }
            showError = true
        } catch {
            print("❌ [EditProfileViewModel] Save failed: \(error)")
            errorMessage = "Failed to update profile: \(error.localizedDescription)"
            showError = true
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}
