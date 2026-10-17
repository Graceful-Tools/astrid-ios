//  AstridAPIClient+Account.swift
//  The signed-in user's account, other users' profiles, and file upload.
//
//  An extension for the same reason as `+Auth` (SourceFileSizeGuardTests). The account calls moved
//  out of AstridAPIClient.swift when the legacy `APIClient`'s profile, account and upload calls
//  came in (AITD-504) — so the client got smaller rather than larger. APIEndpointInventoryTests
//  scans this file too.

import Foundation

extension AstridAPIClient {
    // MARK: - Account Management

    /// Get current user's account data
    func getAccount() async throws -> AccountData {
        try await fetchAccountResponse().user
    }

    /// Update account (name, email, image)
    func updateAccount(name: String? = nil, email: String? = nil, image: String? = nil) async throws -> UpdateAccountResponse {
        struct UpdateRequest: Codable {
            var name: String?
            var email: String?
            var image: String?
        }

        let body = UpdateRequest(name: name, email: email, image: image)

        return try await request(
            method: "PUT",
            path: "/api/v1/users/me",
            body: body
        )
    }

    /// Send, resend, or cancel email verification
    /// - Parameter action: "send", "resend", or "cancel"
    func verifyEmail(action: String) async throws -> VerifyEmailResponse {
        return try await request(
            method: "POST",
            path: "/api/v1/users/me/verify-email",
            queryItems: [URLQueryItem(name: "action", value: action)]
        )
    }

    /// Delete account permanently
    /// - Parameter confirmationText: Must be "DELETE MY ACCOUNT"
    func deleteAccount(confirmationText: String) async throws -> DeleteAccountResponse {
        struct DeleteAccountBody: Codable {
            let confirmationText: String
        }

        let body = DeleteAccountBody(confirmationText: confirmationText)

        return try await request(
            method: "POST",
            path: "/api/v1/users/me/delete",
            body: body
        )
    }

    /// The whole `GET /api/v1/users/me` response, for the screens that read more than the user.
    func fetchAccountResponse() async throws -> AccountResponse {
        try await request(method: "GET", path: "/api/v1/users/me")
    }

    func updateAccount(_ body: UpdateAccountRequest) async throws -> UpdateAccountResponse {
        try await request(method: "PUT", path: "/api/v1/users/me", body: body)
    }

    // MARK: - Profiles

    func getUserProfile(userId: String) async throws -> UserProfileResponse {
        try await request(method: "GET", path: "/api/v1/users/\(userId)/profile")
    }

    // MARK: - Upload

    /// `POST /api/v1/upload` as multipart/form-data with a single `file` part.
    func uploadFile(_ data: Data, fileName: String, mimeType: String) async throws -> UploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try await request(method: "POST", path: "/api/v1/upload",
                                 rawBody: (body, "multipart/form-data; boundary=\(boundary)"))
    }
}
