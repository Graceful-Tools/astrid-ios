import CryptoKit
import Foundation

/// GitHub and SSO sign-in through the browser (AITD-465, spec §6.5).
///
/// No GitHub or SAML SDK ships in the app. It opens `/auth/desktop` in an
/// ASWebAuthenticationSession; the user signs in there with whatever the deployment offers; the
/// page hands a one-time code back on `astrid://auth/callback`; the app trades that code, plus
/// the PKCE verifier it kept to itself, for a session token at `/api/v1/auth/desktop/exchange`.
/// It is the same flow the Windows app uses, so the server's guards (single use, five-minute
/// expiry, S256 only, fixed redirect) apply unchanged.
///
/// Everything here is pure; `AuthManager.signInWithBrowser` does the I/O.
enum DesktopHandoff {

    /// Who the server is handing the session to. It shows on the hand-off page
    /// ("Astrid for iOS") and must be a client the server has registered.
    static var clientId: String {
        #if os(macOS)
        return "mac"
        #else
        return "ios"
        #endif
    }

    /// The callback the server is fixed to deliver to: `<scheme>://auth/callback`.
    static let callbackScheme = "astrid"

    enum HandoffError: LocalizedError, Equatable {
        case unexpectedCallback
        case stateMismatch
        case missingCode

        var errorDescription: String? {
            NSLocalizedString("auth.browser_sign_in_failed", comment: "Browser sign-in did not complete")
        }
    }

    /// One sign-in attempt's secrets. A new one per tap: the state ties the callback to this
    /// attempt, the verifier proves to the server that this app started it.
    struct Attempt: Equatable {
        let verifier: String
        let challenge: String
        let state: String

        static func start() -> Attempt {
            let verifier = randomURLSafe(byteCount: 32)
            return Attempt(verifier: verifier, challenge: DesktopHandoff.challenge(for: verifier),
                           state: randomURLSafe(byteCount: 16))
        }
    }

    /// RFC 7636 S256: base64url(SHA-256(verifier)), no padding.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func startURL(baseURL: URL, provider: SignInProvider, attempt: Attempt,
                         client: String = clientId) -> URL? {
        var parts = URLComponents(url: baseURL.appendingPathComponent("auth/desktop"), resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "client", value: client),
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "code_challenge", value: attempt.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return parts?.url
    }

    /// The one-time code from the callback, if it belongs to this attempt.
    static func code(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == callbackScheme, callback.host == "auth", callback.path == "/callback",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw HandoffError.unexpectedCallback
        }
        let items = parts.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw HandoffError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw HandoffError.missingCode
        }
        return code
    }

    /// The Cookie header to store. The exchange states the name; anything that is not one of the
    /// two names the app sends as a session falls back to the default.
    static func cookieHeader(token: String, cookieName: String?) -> String {
        let name = cookieName.flatMap { SessionCookie.sessionCookieNames.contains($0) ? $0 : nil }
            ?? SessionCookie.defaultSessionCookieName
        return "\(name)=\(token)"
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// `POST /api/v1/auth/desktop/exchange`.
struct DesktopExchangeRequest: Codable {
    let code: String
    let codeVerifier: String
    let client: String
}

struct DesktopExchangeResponse: Codable {
    let sessionToken: String
    let expiresAt: String?
    let sessionCookieName: String?
    let user: User
}
