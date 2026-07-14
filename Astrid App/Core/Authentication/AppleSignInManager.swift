import Foundation
import AuthenticationServices
import Combine

@MainActor
class AppleSignInManager: NSObject, ObservableObject {
    static let shared = AppleSignInManager()

    @Published var isProcessing = false
    @Published var error: Error?

    private var currentNonce: String?
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    struct AppleSignInResult {
        let identityToken: String
        let authorizationCode: String
        let user: String
        let email: String?
        let fullName: PersonNameComponents?
    }

    // MARK: - Sign In

    func signIn() async throws -> AppleSignInResult {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // Generate nonce for security
        let nonce = randomNonceString()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        var hashData = Data(count: Int(32)) // SHA256 produces 32 bytes

        _ = hashData.withUnsafeMutableBytes { hashBytes in
            inputData.withUnsafeBytes { inputBytes in
                // Using CommonCrypto
                CC_SHA256(inputBytes.baseAddress, CC_LONG(inputData.count), hashBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }

        return hashData.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.invalidCredential)
            continuation = nil
            return
        }

        guard let identityToken = appleIDCredential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8),
              let authorizationCode = appleIDCredential.authorizationCode,
              let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
            continuation?.resume(throwing: AppleSignInError.missingToken)
            continuation = nil
            return
        }

        let result = AppleSignInResult(
            identityToken: identityTokenString,
            authorizationCode: authorizationCodeString,
            user: appleIDCredential.user,
            email: appleIDCredential.email,
            fullName: appleIDCredential.fullName
        )

        continuation?.resume(returning: result)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.error = error
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the main window
        return PlatformApplication.presentationAnchor()
    }
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential"
        case .missingToken:
            return "Missing identity token or authorization code"
        }
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
