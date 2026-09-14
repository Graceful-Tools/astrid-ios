import Foundation

/// The LEGACY client's endpoints (ASTRID.md §2a). Closed to additions: every new endpoint goes
/// in `AstridAPIClient`. Only the cases a caller still constructs remain here — the 2026-09-13
/// dedupe pass deleted 28 that duplicated `AstridAPIClient` methods and were never built.
enum APIEndpoint {
    // MARK: - Authentication
    case signUpPasswordless(email: String, name: String?)  // Create account without password
    case signInWithApple(identityToken: String, authorizationCode: String, user: String, email: String?, fullName: String?)
    case signInWithGoogle(idToken: String)
    case signOut
    case session

    // MARK: - Users
    case userProfile(userId: String)

    // MARK: - Account
    case getAccount
    case updateAccount(UpdateAccountRequest)
    case uploadFile(Data, fileName: String, mimeType: String)

    var path: String {
        switch self {
        // signUpPasswordless has no backend route at any path (legacy or v1).
        // Pre-existing iOS bug; leaving the namespaced /api/v1/* path so that
        // any future backend implementation can land without an iOS bump.
        case .signUpPasswordless:
            return "/api/v1/auth/mobile-signup"
        case .signInWithApple:
            return "/api/v1/auth/apple"
        case .signInWithGoogle:
            return "/api/v1/auth/google"
        case .signOut:
            return "/api/v1/auth/signout"
        case .session:
            return "/api/v1/auth/mobile-session"
        case .userProfile(let userId):
            return "/api/v1/users/\(userId)/profile"
        case .getAccount, .updateAccount:
            return "/api/v1/users/me"
        case .uploadFile:
            return "/api/v1/upload"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .signUpPasswordless, .signInWithApple, .signInWithGoogle, .uploadFile:
            return .post
        case .updateAccount:
            return .put
        case .signOut:
            return .delete
        case .session, .userProfile, .getAccount:
            return .get
        }
    }

    func makeRequest(baseURL: URL, encoder: JSONEncoder) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Was a hardcoded "ios-app" — in a file the Mac target compiles too, so any caller that
        // did not go through APIClient.request (which overwrote it) reported the Mac as iOS.
        AnalyticsPlatformHeader.apply(to: &request)

        switch self {
        case .signUpPasswordless(let email, let name):
            request.httpBody = try encoder.encode(SignUpPasswordlessRequest(email: email, name: name))

        case .signInWithApple(let identityToken, let authorizationCode, let user, let email, let fullName):
            request.httpBody = try encoder.encode(AppleSignInRequest(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                user: user,
                email: email,
                fullName: fullName
            ))

        case .signInWithGoogle(let idToken):
            request.httpBody = try encoder.encode(GoogleSignInRequest(idToken: idToken))

        case .updateAccount(let accountRequest):
            request.httpBody = try encoder.encode(accountRequest)

        case .uploadFile(let data, let fileName, let mimeType):
            // Use multipart/form-data for file uploads
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

        case .signOut, .session, .userProfile, .getAccount:
            break
        }

        return request
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
