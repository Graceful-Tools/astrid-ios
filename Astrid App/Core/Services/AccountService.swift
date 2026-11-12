import AstridCore
import Foundation

/// Canonical service facade for account / profile operations.
///
/// Per the canonical control points in CLAUDE.md, UI (Views / ViewModels /
/// Utilities) must not talk to `AstridAPIClient` directly. All
/// account reads and writes flow through this service so the boundary stays in
/// one place and can be extended (caching, optimistic updates) without touching
/// every screen.
///
/// Delete, export, resend-verification and email change go through astrid-core (AITD-620);
/// the rest are still passthroughs to the client.
final class AccountService {
    static let shared = AccountService()

    private let apiClient = AstridAPIClient.shared

    private init() {}

    // MARK: - Account (typed AstridAPIClient path)

    func getAccount() async throws -> AccountData {
        try await apiClient.getAccount()
    }

    func updateAccount(name: String? = nil, email: String? = nil, image: String? = nil) async throws -> UpdateAccountResponse {
        try await updateAccount(UpdateAccountRequest(name: name, email: email, image: image))
    }

    /// The server's "send" / "cancel" verification actions. The core has only a resend
    /// (`resendVerification`), so these two stay on the client until it has the others.
    func verifyEmail(action: String) async throws -> VerifyEmailResponse {
        if action == "resend" {
            let answer = try await core.run(AccountCommands.resendVerification(), as: VerificationResent.self)
            return VerifyEmailResponse(success: true, message: answer.message ?? "")
        }
        return try await apiClient.verifyEmail(action: action)
    }

    /// The export, through the core, which writes it to a file; read back for the callers that
    /// save it where the person chooses.
    func exportAccountData(format: String) async throws -> Data {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-export-\(UUID().uuidString).\(format)")
        defer { try? FileManager.default.removeItem(at: file) }
        try await core.run(AccountCommands.export(format: format, to: file))
        return try Data(contentsOf: file)
    }

    /// Deletes the account for good. The caller has already checked the phrase the person typed
    /// in their own language; what goes to the server is the contract phrase
    /// (`AccountCommands.deletionConfirmation`). The core signs its own session out afterwards.
    func deleteAccount() async throws {
        try await core.run(AccountCommands.delete())
    }

    /// The text to show for a failure here: the core's own sentence when it refused, since a
    /// `CoreFailure` has no localized description of its own.
    static func message(for error: Error) -> String {
        (error as? CoreFailure)?.message ?? error.localizedDescription
    }

    private var core: CoreSession { AppCore.shared.session }

    // MARK: - Profile image upload

    func uploadProfileImage(_ imageData: Data, fileName: String, mimeType: String = "image/jpeg") async throws -> UploadResponse {
        try await apiClient.uploadFile(imageData, fileName: fileName, mimeType: mimeType)
    }

    // MARK: - Whole account response (EditProfile / UserProfile screens)

    func fetchAccountResponse() async throws -> AccountResponse {
        try await apiClient.fetchAccountResponse()
    }

    /// Name and photo go to `PUT /users/me` as before: the core's `updateProfile` takes a photo
    /// *file* and uploads it itself, while these screens upload on pick and hold a URL. A changed
    /// email goes through the core's `changeEmail`, which checks the address and turns a 409 into
    /// a sentence.
    func updateAccount(_ request: UpdateAccountRequest) async throws -> UpdateAccountResponse {
        var profile = request
        profile.email = nil
        var message = ""
        if profile.name != nil || profile.image != nil {
            message = try await apiClient.updateAccount(profile).message
        }
        guard let email = request.email else {
            return UpdateAccountResponse(success: true, message: message, emailVerificationRequired: nil)
        }
        let changed = try await core.run(AccountCommands.changeEmail(email), as: EmailChangeResult.self)
        return UpdateAccountResponse(success: true, message: changed.message ?? message,
                                     emailVerificationRequired: changed.verificationRequired)
    }
}
