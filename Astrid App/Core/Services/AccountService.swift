import Foundation

/// Canonical service facade for account / profile operations.
///
/// Per the canonical control points in CLAUDE.md, UI (Views / ViewModels /
/// Utilities) must not talk to `AstridAPIClient` / `APIClient` directly. All
/// account reads and writes flow through this service so the boundary stays in
/// one place and can be extended (caching, optimistic updates) without touching
/// every screen.
///
/// This is a thin passthrough today — it deliberately preserves the exact wire
/// behavior of the previous direct client calls (same endpoints, same response
/// types, same error propagation).
final class AccountService {
    static let shared = AccountService()

    private let apiClient = AstridAPIClient.shared
    private let legacyClient = APIClient.shared

    private init() {}

    // MARK: - Account (typed AstridAPIClient path)

    func getAccount() async throws -> AccountData {
        try await apiClient.getAccount()
    }

    func updateAccount(name: String? = nil, email: String? = nil, image: String? = nil) async throws -> UpdateAccountResponse {
        try await apiClient.updateAccount(name: name, email: email, image: image)
    }

    func verifyEmail(action: String) async throws -> VerifyEmailResponse {
        try await apiClient.verifyEmail(action: action)
    }

    func exportAccountData(format: String) async throws -> Data {
        try await apiClient.exportAccountData(format: format)
    }

    func deleteAccount(confirmationText: String) async throws -> DeleteAccountResponse {
        try await apiClient.deleteAccount(confirmationText: confirmationText)
    }

    // MARK: - Profile image upload (legacy endpoint path)

    func uploadProfileImage(_ imageData: Data, fileName: String, mimeType: String = "image/jpeg") async throws -> UploadResponse {
        try await legacyClient.request(.uploadFile(imageData, fileName: fileName, mimeType: mimeType))
    }

    // MARK: - Legacy generic account path (EditProfile / UserProfile screens)

    func fetchAccountResponse() async throws -> AccountResponse {
        try await legacyClient.request(.getAccount)
    }

    func updateAccount(_ request: UpdateAccountRequest) async throws -> UpdateAccountResponse {
        try await legacyClient.request(.updateAccount(request))
    }
}
