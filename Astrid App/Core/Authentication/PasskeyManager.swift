import Foundation
import AuthenticationServices
import Combine

@MainActor
class PasskeyManager: NSObject, ObservableObject {
    static let shared = PasskeyManager()

    @Published var isProcessing = false
    @Published var error: Error?

    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationResult, Error>?
    private var authenticationContinuation: CheckedContinuation<PasskeyAuthenticationResult, Error>?

    // MARK: - Response Types

    struct PasskeyRegistrationResult {
        let credentialId: String
        let rawId: Data
        let attestationObject: Data
        let clientDataJSON: Data
        let transports: [String]?
    }

    struct PasskeyAuthenticationResult {
        let credentialId: String
        let rawId: Data
        let authenticatorData: Data
        let clientDataJSON: Data
        let signature: Data
        let userHandle: Data?
    }

    // MARK: - API Response Types

    struct RegistrationOptionsResponse: Codable {
        let options: PublicKeyCredentialCreationOptions
        let sessionId: String
    }

    struct AuthenticationOptionsResponse: Codable {
        let options: PublicKeyCredentialRequestOptions
        let sessionId: String
    }

    struct PublicKeyCredentialCreationOptions: Codable {
        let challenge: String
        let rp: RelyingParty
        let user: PublicKeyUser
        let pubKeyCredParams: [PubKeyCredParam]
        let timeout: Int?
        let attestation: String?
        let excludeCredentials: [AllowCredential]?
        let authenticatorSelection: AuthenticatorSelection?
    }

    struct PublicKeyCredentialRequestOptions: Codable {
        let challenge: String
        let rpId: String?
        let timeout: Int?
        let allowCredentials: [AllowCredential]?
        let userVerification: String?
    }

    struct RelyingParty: Codable {
        let name: String
        let id: String
    }

    struct PublicKeyUser: Codable {
        let id: String
        let name: String
        let displayName: String
    }

    struct PubKeyCredParam: Codable {
        let type: String
        let alg: Int
    }

    struct AllowCredential: Codable {
        let id: String
        let type: String
        let transports: [String]?
    }

    struct AuthenticatorSelection: Codable {
        let authenticatorAttachment: String?
        let residentKey: String?
        let requireResidentKey: Bool?
        let userVerification: String?
    }

    struct VerifyResponse: Codable {
        let verified: Bool
        let user: UserResponse?
        let isNewUser: Bool?
        let error: String?
    }

    struct UserResponse: Codable {
        let id: String
        let email: String?
        let name: String?
        let image: String?
    }

    // Response when user already exists during registration
    struct ExistingUserResponse: Codable {
        let existingUser: Bool
        let email: String
        let hasPasskey: Bool
    }

    // MARK: - Passkey Info

    struct PasskeyInfo: Codable, Identifiable {
        let id: String
        let name: String?
        let credentialDeviceType: String
        let credentialBackedUp: Bool
        let createdAt: String
    }

    struct PasskeysResponse: Codable {
        let passkeys: [PasskeyInfo]
    }

    // MARK: - Registration

    func register(email: String, name: String = "My Passkey") async throws -> (Bool, UserResponse?) {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // 1. Get registration options from server
        let optionsResponse = try await getRegistrationOptions(email: email)

        // 2. Perform WebAuthn registration ceremony
        let registrationResult = try await performRegistration(options: optionsResponse.options)

        // 3. Verify with server
        let verifyResult = try await verifyRegistration(
            sessionId: optionsResponse.sessionId,
            result: registrationResult,
            name: name
        )

        return (verifyResult.verified, verifyResult.user)
    }

    func registerForExistingUser(name: String = "My Passkey") async throws -> Bool {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // 1. Get registration options from server (authenticated)
        let optionsResponse = try await getRegistrationOptionsAuthenticated()

        // 2. Perform WebAuthn registration ceremony
        let registrationResult = try await performRegistration(options: optionsResponse.options)

        // 3. Verify with server
        let verifyResult = try await verifyRegistration(
            sessionId: optionsResponse.sessionId,
            result: registrationResult,
            name: name
        )

        return verifyResult.verified
    }

    // MARK: - Authentication

    func authenticate(email: String? = nil) async throws -> UserResponse {
        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // 1. Get authentication options from server
        let optionsResponse = try await getAuthenticationOptions(email: email)

        // 2. Perform WebAuthn authentication ceremony
        let authResult = try await performAuthentication(options: optionsResponse.options)

        // 3. Verify with server
        let verifyResult = try await verifyAuthentication(
            sessionId: optionsResponse.sessionId,
            result: authResult
        )

        guard verifyResult.verified, let user = verifyResult.user else {
            throw PasskeyError.authenticationFailed(verifyResult.error ?? "Unknown error")
        }

        return user
    }

    // MARK: - Passkey Management

    // NOTE: WebAuthn endpoints stay on /api/auth/webauthn/* — there is no
    // /api/v1/auth/webauthn/* on the server. The v1 migration intentionally
    // skipped the WebAuthn paths.

    func getPasskeys() async throws -> [PasskeyInfo] {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/passkeys")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PasskeyError.serverError("Failed to fetch passkeys")
        }

        let passkeysResponse = try JSONDecoder().decode(PasskeysResponse.self, from: data)
        return passkeysResponse.passkeys
    }

    func deletePasskey(id: String) async throws {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/passkeys?id=\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PasskeyError.serverError("Failed to delete passkey")
        }
    }

    func renamePasskey(id: String, name: String) async throws {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/passkeys")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["id": id, "name": name])

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PasskeyError.serverError("Failed to rename passkey")
        }
    }

    // MARK: - Private API Methods

    private func getRegistrationOptions(email: String) async throws -> RegistrationOptionsResponse {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/register/options")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email])

        // IMPORTANT: Use ephemeral session to avoid sending existing cookies
        // This ensures new account registration doesn't accidentally use an existing session
        let ephemeralConfig = URLSessionConfiguration.ephemeral
        let ephemeralSession = URLSession(configuration: ephemeralConfig)

        let (data, response) = try await ephemeralSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
            throw PasskeyError.serverError(errorResponse?["error"] ?? "Failed to get registration options")
        }

        // Check if server returned existingUser response (user already has an account)
        if let existingUserResponse = try? JSONDecoder().decode(ExistingUserResponse.self, from: data),
           existingUserResponse.existingUser {
            throw PasskeyError.existingUser(email: existingUserResponse.email, hasPasskey: existingUserResponse.hasPasskey)
        }

        return try JSONDecoder().decode(RegistrationOptionsResponse.self, from: data)
    }

    private func getRegistrationOptionsAuthenticated() async throws -> RegistrationOptionsResponse {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/register/options")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        // Add session cookie for authenticated requests
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
            throw PasskeyError.serverError(errorResponse?["error"] ?? "Failed to get registration options")
        }

        return try JSONDecoder().decode(RegistrationOptionsResponse.self, from: data)
    }

    private func getAuthenticationOptions(email: String?) async throws -> AuthenticationOptionsResponse {
        let urlString = "\(Constants.API.baseURL)/api/auth/webauthn/authenticate/options"
        print("🔑 [Passkey] Fetching auth options from: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw PasskeyError.serverError("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let email = email {
            request.httpBody = try JSONEncoder().encode(["email": email])
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PasskeyError.serverError("Invalid response type")
            }

            print("🔑 [Passkey] Auth options response: HTTP \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ [Passkey] Error response: \(responseString)")
                let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
                throw PasskeyError.serverError(errorResponse?["error"] ?? "HTTP \(httpResponse.statusCode)")
            }

            return try JSONDecoder().decode(AuthenticationOptionsResponse.self, from: data)
        } catch let error as PasskeyError {
            throw error
        } catch {
            print("❌ [Passkey] Network error: \(error.localizedDescription)")
            throw PasskeyError.serverError("Network error: \(error.localizedDescription)")
        }
    }

    private func verifyRegistration(sessionId: String, result: PasskeyRegistrationResult, name: String) async throws -> VerifyResponse {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/register/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add session cookie for authenticated requests (adding passkey to existing account)
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        // Build the response object matching SimpleWebAuthn format
        let responseBody: [String: Any] = [
            "sessionId": sessionId,
            "name": name,
            "response": [
                "id": result.credentialId,
                "rawId": result.rawId.base64URLEncodedString(),
                "type": "public-key",
                "response": [
                    "attestationObject": result.attestationObject.base64URLEncodedString(),
                    "clientDataJSON": result.clientDataJSON.base64URLEncodedString()
                ],
                "clientExtensionResults": [:],
                "authenticatorAttachment": "platform"
            ] as [String: Any]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: responseBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.serverError("Invalid response")
        }

        // Save session cookie if present
        if let url = httpResponse.url {
            saveCookies(from: httpResponse, url: url)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
            throw PasskeyError.serverError(errorResponse?["error"] ?? "Registration verification failed")
        }

        return try JSONDecoder().decode(VerifyResponse.self, from: data)
    }

    private func verifyAuthentication(sessionId: String, result: PasskeyAuthenticationResult) async throws -> VerifyResponse {
        let url = URL(string: "\(Constants.API.baseURL)/api/auth/webauthn/authenticate/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the response object matching SimpleWebAuthn format
        var responseDict: [String: Any] = [
            "id": result.credentialId,
            "rawId": result.rawId.base64URLEncodedString(),
            "type": "public-key",
            "response": [
                "authenticatorData": result.authenticatorData.base64URLEncodedString(),
                "clientDataJSON": result.clientDataJSON.base64URLEncodedString(),
                "signature": result.signature.base64URLEncodedString()
            ],
            "clientExtensionResults": [:],
            "authenticatorAttachment": "platform"
        ]

        if let userHandle = result.userHandle {
            var responseInner = responseDict["response"] as! [String: Any]
            responseInner["userHandle"] = userHandle.base64URLEncodedString()
            responseDict["response"] = responseInner
        }

        let responseBody: [String: Any] = [
            "sessionId": sessionId,
            "response": responseDict
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: responseBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PasskeyError.serverError("Invalid response")
        }

        // Save session cookie if present
        if let url = httpResponse.url {
            saveCookies(from: httpResponse, url: url)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
            throw PasskeyError.serverError(errorResponse?["error"] ?? "Authentication verification failed")
        }

        return try JSONDecoder().decode(VerifyResponse.self, from: data)
    }

    private func saveCookies(from httpResponse: HTTPURLResponse, url: URL) {
        print("🍪 [PasskeyManager] Extracting cookies from response...")

        // Convert allHeaderFields to [String: String] - it's [AnyHashable: Any]
        var stringHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                stringHeaders[keyString] = valueString
            }
        }

        // Log Set-Cookie headers for debugging
        let setCookieHeaders = stringHeaders.filter { $0.key.lowercased() == "set-cookie" }
        print("🍪 [PasskeyManager] Found \(setCookieHeaders.count) Set-Cookie header(s)")

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url)
        print("🍪 [PasskeyManager] Parsed \(cookies.count) cookie(s) from headers")

        var authCookies: [String] = []
        for cookie in cookies {
            let lowercaseName = cookie.name.lowercased()
            print("🍪 [PasskeyManager] Cookie: \(cookie.name) (domain: \(cookie.domain), path: \(cookie.path))")
            if lowercaseName.contains("session") || lowercaseName.contains("auth") || lowercaseName.contains("csrf") {
                authCookies.append("\(cookie.name)=\(cookie.value)")
                print("✅ [PasskeyManager] Keeping auth cookie: \(cookie.name)")
            }
        }

        if !authCookies.isEmpty {
            let allCookiesString = authCookies.joined(separator: "; ")
            do {
                try KeychainService.shared.saveSessionCookie(allCookiesString)
                print("✅ [PasskeyManager] Saved \(authCookies.count) auth cookie(s) to keychain")

                // Verify the save was successful
                if let savedCookie = try? KeychainService.shared.getSessionCookie() {
                    print("✅ [PasskeyManager] Verified cookie saved: \(savedCookie.prefix(50))...")
                } else {
                    print("❌ [PasskeyManager] Cookie save verification failed - could not read back")
                }
            } catch {
                print("❌ [PasskeyManager] Keychain save failed: \(error)")
            }
        } else {
            print("⚠️ [PasskeyManager] No auth cookies found in response!")
            print("⚠️ [PasskeyManager] All cookies: \(cookies.map { $0.name })")
            print("⚠️ [PasskeyManager] Response URL: \(url)")

            // Check if cookies are being stored in HTTPCookieStorage instead
            if let storedCookies = HTTPCookieStorage.shared.cookies(for: url) {
                print("🍪 [PasskeyManager] HTTPCookieStorage has \(storedCookies.count) cookies for this URL")
                for cookie in storedCookies {
                    let lowercaseName = cookie.name.lowercased()
                    if lowercaseName.contains("session") || lowercaseName.contains("auth") {
                        // Found auth cookie in storage - save it to keychain
                        let cookieValue = "\(cookie.name)=\(cookie.value)"
                        print("✅ [PasskeyManager] Found auth cookie in storage: \(cookie.name)")
                        do {
                            try KeychainService.shared.saveSessionCookie(cookieValue)
                            print("✅ [PasskeyManager] Saved cookie from HTTPCookieStorage to keychain")
                        } catch {
                            print("❌ [PasskeyManager] Failed to save from storage: \(error)")
                        }
                        break
                    }
                }
            }
        }
    }

    // MARK: - WebAuthn Ceremony Methods

    private func performRegistration(options: PublicKeyCredentialCreationOptions) async throws -> PasskeyRegistrationResult {
        guard let challengeData = Data(base64URLEncoded: options.challenge) else {
            throw PasskeyError.invalidChallenge
        }

        guard let userIdData = options.user.id.data(using: .utf8) else {
            throw PasskeyError.invalidUserId
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
        let registrationRequest = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: options.user.name,
            userID: userIdData
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.registrationContinuation = continuation

            let authController = ASAuthorizationController(authorizationRequests: [registrationRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
        }
    }

    private func performAuthentication(options: PublicKeyCredentialRequestOptions) async throws -> PasskeyAuthenticationResult {
        guard let challengeData = Data(base64URLEncoded: options.challenge) else {
            throw PasskeyError.invalidChallenge
        }

        let rpId = options.rpId ?? "astrid.cc"
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)

        var allowedCredentials: [ASAuthorizationPlatformPublicKeyCredentialDescriptor] = []
        if let credentials = options.allowCredentials {
            for credential in credentials {
                if let credentialIdData = Data(base64URLEncoded: credential.id) {
                    allowedCredentials.append(
                        ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialIdData)
                    )
                }
            }
        }

        let assertionRequest = provider.createCredentialAssertionRequest(challenge: challengeData)
        if !allowedCredentials.isEmpty {
            assertionRequest.allowedCredentials = allowedCredentials
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.authenticationContinuation = continuation

            let authController = ASAuthorizationController(authorizationRequests: [assertionRequest])
            authController.delegate = self
            authController.presentationContextProvider = self
            authController.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension PasskeyManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let registrationCredential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            // Registration completed
            let result = PasskeyRegistrationResult(
                credentialId: registrationCredential.credentialID.base64URLEncodedString(),
                rawId: registrationCredential.credentialID,
                attestationObject: registrationCredential.rawAttestationObject ?? Data(),
                clientDataJSON: registrationCredential.rawClientDataJSON,
                transports: ["internal"]
            )
            registrationContinuation?.resume(returning: result)
            registrationContinuation = nil

        } else if let assertionCredential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            // Authentication completed
            let result = PasskeyAuthenticationResult(
                credentialId: assertionCredential.credentialID.base64URLEncodedString(),
                rawId: assertionCredential.credentialID,
                authenticatorData: assertionCredential.rawAuthenticatorData,
                clientDataJSON: assertionCredential.rawClientDataJSON,
                signature: assertionCredential.signature,
                userHandle: assertionCredential.userID
            )
            authenticationContinuation?.resume(returning: result)
            authenticationContinuation = nil
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.error = error

        let passkeyError: PasskeyError
        if let authError = error as? ASAuthorizationError {
            // Map ASAuthorizationError codes to PasskeyError
            let code = authError.code
            if code == .canceled {
                passkeyError = .userCancelled
            } else if code == .failed {
                passkeyError = .authenticationFailed(error.localizedDescription)
            } else if code == .invalidResponse {
                passkeyError = .invalidResponse
            } else if code == .notHandled || code == .notInteractive {
                passkeyError = .notSupported
            } else if code == .matchedExcludedCredential {
                passkeyError = .authenticationFailed("This passkey is already registered")
            } else {
                // Handles .unknown and any future cases
                passkeyError = .unknown(error.localizedDescription)
            }
        } else {
            passkeyError = .unknown(error.localizedDescription)
        }

        registrationContinuation?.resume(throwing: passkeyError)
        registrationContinuation = nil

        authenticationContinuation?.resume(throwing: passkeyError)
        authenticationContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension PasskeyManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

// MARK: - Errors

enum PasskeyError: LocalizedError {
    case notSupported
    case userCancelled
    case invalidChallenge
    case invalidUserId
    case invalidResponse
    case authenticationFailed(String)
    case registrationFailed(String)
    case serverError(String)
    case unknown(String)
    case existingUser(email: String, hasPasskey: Bool)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Passkeys are not supported on this device"
        case .userCancelled:
            return "Passkey operation was cancelled"
        case .invalidChallenge:
            return "Invalid challenge from server"
        case .invalidUserId:
            return "Invalid user ID"
        case .invalidResponse:
            return "Invalid response from authenticator"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .serverError(let message):
            return message
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .existingUser(_, let hasPasskey):
            if hasPasskey {
                return "An account with this email already exists. Please sign in with your passkey."
            } else {
                return "An account with this email already exists. Please sign in with another method."
            }
        }
    }
}

// MARK: - Data Extensions

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let paddingLength = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingLength)

        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
