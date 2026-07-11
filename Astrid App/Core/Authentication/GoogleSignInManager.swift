import Foundation
import AuthenticationServices
import Combine

@MainActor
class GoogleSignInManager: NSObject, ObservableObject {
    static let shared = GoogleSignInManager()

    @Published var isProcessing = false
    @Published var error: Error?

    private var continuation: CheckedContinuation<GoogleSignInResult, Error>?
    private var authSession: ASWebAuthenticationSession?

    struct GoogleSignInResult {
        let idToken: String
        let accessToken: String?
    }

    // MARK: - Configuration
    // NOTE: This must be configured with your Google OAuth Client ID for iOS
    // Get this from Google Cloud Console: https://console.cloud.google.com/apis/credentials
    // Instructions in ios/GOOGLE_OAUTH_SETUP.md
    private let clientID = "195880614240-nps6cdlcceliaru5d3b4p6pofjbs7sks.apps.googleusercontent.com"
    private let redirectURI = "com.googleusercontent.apps.195880614240-nps6cdlcceliaru5d3b4p6pofjbs7sks:/oauth2redirect/google"

    // MARK: - Sign In

    func signIn() async throws -> GoogleSignInResult {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // Validate configuration
        guard !clientID.contains("YOUR_GOOGLE") else {
            throw GoogleSignInError.notConfigured
        }

        // Remove the legacy persisted verifier from older builds. The current
        // verifier lives only in the authentication-session callback closure.
        UserDefaults.standard.removeObject(forKey: "GoogleOAuthCodeVerifier")

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // Generate state for CSRF protection
            let state = randomString(length: 32)

            // Generate code verifier for PKCE
            let codeVerifier = randomString(length: 128)
            let codeChallenge = sha256Base64URL(codeVerifier)

            // Build authorization URL
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "openid email profile"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]

            guard let authURL = components.url else {
                self.complete(with: .failure(GoogleSignInError.invalidURL))
                return
            }

            // Create and start authentication session
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectURI.components(separatedBy: ":").first
            ) { [weak self] callbackURL, error in
                _Concurrency.Task { @MainActor in
                    if let error = error {
                        if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            self?.complete(with: .failure(GoogleSignInError.userCancelled))
                        } else {
                            self?.complete(with: .failure(error))
                        }
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        self?.complete(with: .failure(GoogleSignInError.missingCallback))
                        return
                    }

                    do {
                        let result = try await self?.exchangeCodeForTokens(callbackURL: callbackURL, codeVerifier: codeVerifier)
                        if let result = result {
                            self?.complete(with: .success(result))
                        }
                    } catch {
                        self?.complete(with: .failure(error))
                    }
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false // Allow persistent sign-in

            self.authSession = session
            session.start()
        }
    }

    // MARK: - Token Exchange

    private func complete(with result: Result<GoogleSignInResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        authSession = nil
        continuation.resume(with: result)
    }

    private func exchangeCodeForTokens(callbackURL: URL, codeVerifier: String) async throws -> GoogleSignInResult {
        // Parse authorization code from callback URL
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.missingAuthorizationCode
        }

        // Exchange code for tokens
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleSignInError.tokenExchangeFailed
        }

        struct TokenResponse: Codable {
            let id_token: String
            let access_token: String
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return GoogleSignInResult(
            idToken: tokenResponse.id_token,
            accessToken: tokenResponse.access_token
        )
    }

    // MARK: - Helpers

    private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }

    private func sha256Base64URL(_ input: String) -> String {
        let inputData = Data(input.utf8)
        var hashData = Data(count: Int(32)) // SHA256 produces 32 bytes

        _ = hashData.withUnsafeMutableBytes { hashBytes in
            inputData.withUnsafeBytes { inputBytes in
                CC_SHA256(inputBytes.baseAddress, CC_LONG(inputData.count), hashBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }

        // Convert to base64url encoding
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleSignInManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

// MARK: - Errors

enum GoogleSignInError: LocalizedError {
    case notConfigured
    case invalidURL
    case userCancelled
    case missingCallback
    case missingAuthorizationCode
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Sign In is not configured. Please set up your Google OAuth Client ID."
        case .invalidURL:
            return "Invalid authorization URL"
        case .userCancelled:
            return "User cancelled sign in"
        case .missingCallback:
            return "Missing callback URL"
        case .missingAuthorizationCode:
            return "Missing authorization code"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        }
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
