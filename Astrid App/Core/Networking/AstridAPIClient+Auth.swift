//  AstridAPIClient+Auth.swift
//  Sign-in, session and sign-out — including POST /api/v1/auth/desktop/exchange, the native half
//  of browser sign-in (AITD-465).
//
//  An extension rather than more lines in AstridAPIClient.swift: the client sits on the source
//  file size ceiling (SourceFileSizeGuardTests), and the precedent from AITD-388 is to move a
//  cohesive group of endpoints out, not to raise the number. APIEndpointInventoryTests scans
//  this file too, so docs/API_ENDPOINTS.md stays honest about the paths it adds.
//
//  The Apple, Google, sign-up and session calls came here from the legacy `APIClient` (AITD-504).
//  They pass `capturesSession: true`: the server answers them with the session as Set-Cookie,
//  and nothing else puts it in the Keychain.

import Foundation

/// Decodes any body, and an empty one — for calls whose answer carries nothing the app reads.
struct EmptyResponse: Codable {}

extension AstridAPIClient {
    /// Trade a desktop hand-off code and its PKCE verifier for a session (spec §6.5).
    /// Unauthenticated: the app has no session yet, which is the point. The token comes back in
    /// the body, never as Set-Cookie, so the caller stores it.
    func exchangeDesktopCode(_ body: DesktopExchangeRequest) async throws -> DesktopExchangeResponse {
        try await request(method: "POST", path: "/api/v1/auth/desktop/exchange", body: body)
    }

    func signInWithApple(_ body: AppleSignInRequest) async throws -> SessionResponse {
        try await request(method: "POST", path: "/api/v1/auth/apple", body: body, capturesSession: true)
    }

    func signInWithGoogle(idToken: String) async throws -> SessionResponse {
        try await request(method: "POST", path: "/api/v1/auth/google",
                          body: GoogleSignInRequest(idToken: idToken), capturesSession: true)
    }

    /// No backend route answers this at any path — a pre-existing gap, kept on its namespaced
    /// `/api/v1` path so a server implementation can land without an app release.
    func signUpPasswordless(email: String, name: String?) async throws -> SessionResponse {
        try await request(method: "POST", path: "/api/v1/auth/mobile-signup",
                          body: SignUpPasswordlessRequest(email: email, name: name), capturesSession: true)
    }

    /// Validates the stored session; a renewed token comes back in the body (Task b8999ea3).
    func getSession() async throws -> SessionResponse {
        try await request(method: "GET", path: "/api/v1/auth/mobile-session", capturesSession: true)
    }

    func signOut() async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: "/api/v1/auth/signout")
    }
}

/// Lifts the auth cookies out of a response into the Keychain, as one `Cookie` request header.
enum SessionCookieCapture {
    static func save(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
            if let key = pair.key as? String, let value = pair.value as? String { acc[key] = value }
        }
        guard let header = cookieHeader(fromResponseHeaders: headers, url: url) else { return }
        do {
            try KeychainService.shared.saveSessionCookie(header)
        } catch {
            PrivacyLogger.error("AstridAPI", code: "session_cookie_save_failed")
        }
    }

    /// `name=value; …` for every session, auth or CSRF cookie set; nil when there are none.
    static func cookieHeader(fromResponseHeaders headers: [String: String], url: URL) -> String? {
        let auth = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter {
            let name = $0.name.lowercased()
            return name.contains("session") || name.contains("auth") || name.contains("csrf")
        }
        return auth.isEmpty ? nil : auth.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

extension AstridAPIError {
    /// The HTTP status, with `.unauthorized` read as the 401 it was.
    var httpStatusCode: Int? {
        switch self {
        case .unauthorized: return 401
        case .httpError(let code, _): return code
        default: return nil
        }
    }

    /// The `error` field of a JSON error body, the message the server meant a person to read.
    var serverMessage: String? {
        guard case .httpError(_, let body) = self,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }
}
