//  AstridHTTP.swift
//  One hardened way for `Core` to send a request it builds itself.
//
//  `AstridAPIClient` is the right route for anything JSON-shaped, but a few paths genuinely need
//  their own `URLRequest`: multipart uploads, WebAuthn challenges, an OAuth token exchange. Those
//  reached for `URLSession.shared`, and in doing so skipped three protections the rest of the app
//  has (task AITD-338):
//
//    1. `APIPathSafety.isSafeRequestPath` — the July 2026 audit's backstop. It lived only at the
//       two URL-construction sites inside `AstridAPIClient`, so an id interpolated into a path
//       anywhere else was unchecked. Worse, those sites force-unwrapped `URL(string:)`: an id
//       carrying a space was a crash rather than a refused request.
//    2. `Constants.API.timeout`. `URLSession.shared` ignores it, so a stalled secure-file lookup
//       or Passkey challenge hung for the system default — 60 s request, 7 days resource.
//    3. `UITestNetworkIsolation.harden`. `URLSession.shared` IS the shared, persistent cookie jar
//       that hardening exists to keep away from UI tests, so under `-uiTesting` these requests
//       still carried any ambient session cookie.
//
//  Everything here is applied once, for every caller. `CoreNetworkSessionGuardTests` keeps new
//  call sites from opting back out.
import Foundation

enum AstridHTTPError: Error, Equatable {
    /// The path contains a traversal segment a server could normalize into a different endpoint.
    case unsafePath
    /// The path could not be made into a URL at all (e.g. it carries a raw space).
    case invalidURL
}

enum AstridHTTP {

    // MARK: - The session

    /// The session every `Core` request goes through. Same configuration as `AstridAPIClient`'s:
    /// the app's timeout, cookie auth enabled, and UI-test hardening applied.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.API.timeout
        configuration.timeoutIntervalForResource = Constants.API.timeout
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: UITestNetworkIsolation.harden(configuration))
    }()

    /// For flows that must not reuse any stored state at all — the Passkey manager builds one for
    /// its unauthenticated challenge exchange. Hardened and timed out the same way.
    static func ephemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.API.timeout
        configuration.timeoutIntervalForResource = Constants.API.timeout
        return URLSession(configuration: UITestNetworkIsolation.harden(configuration))
    }

    // MARK: - URLs

    /// Build a request URL against the configured server, refusing traversal paths.
    ///
    /// Throws where the old call sites force-unwrapped, so a malformed id is a handled error
    /// rather than a crash.
    static func apiURL(_ path: String, query: [URLQueryItem]? = nil) throws -> URL {
        guard APIPathSafety.isSafeRequestPath(path) else { throw AstridHTTPError.unsafePath }

        let separator = path.hasPrefix("/") ? "" : "/"
        guard var components = URLComponents(string: Constants.API.baseURL + separator + path) else {
            throw AstridHTTPError.invalidURL
        }
        if let query, !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let url = components.url else { throw AstridHTTPError.invalidURL }
        return url
    }

    /// A URL the SERVER handed us (a signed blob URL, a download link). It is not ours to
    /// path-check — it is not built from our ids — but it must still be a real URL rather than a
    /// force-unwrap, and it is fetched on the hardened session like everything else.
    static func remoteURL(_ absolute: String) throws -> URL {
        guard let url = URL(string: absolute) else { throw AstridHTTPError.invalidURL }
        return url
    }

    // MARK: - Multipart

    /// Make a user-chosen file name safe to place inside `filename="…"` of a `Content-Disposition`.
    ///
    /// A `"` closes the quoted string early and a CR or LF ends the header outright, letting the
    /// rest of the name be read as further headers. The name arrives from whatever app shared the
    /// file (Share Extension → `uploadSharedFile` → `uploadAttachment`), so it is genuinely
    /// attacker-influenced.
    static func multipartFilename(_ name: String) -> String {
        // Filter SCALARS, not Characters. Swift treats CRLF as one grapheme cluster, so
        // `name.filter { $0 != "\r" && $0 != "\n" }` matches neither half of a `\r\n` pair and
        // leaves the header break intact — which is the exact input that matters here.
        let withoutLineBreaks = String(String.UnicodeScalarView(
            name.unicodeScalars.filter { $0 != "\r" && $0 != "\n" }
        ))
        let escaped = withoutLineBreaks
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // An empty `filename=""` is worse than a generic one: the server has nothing to key on.
        return escaped.isEmpty ? "file" : escaped
    }
}
