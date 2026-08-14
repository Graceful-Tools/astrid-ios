import Foundation

/// The stored session credential, and how a renewed token folds into it (Task b8999ea3).
///
/// The Keychain does not hold a bare token. It holds a whole `Cookie` request header —
/// `name=value; name2=value2` — which is set verbatim on every request. The server, meanwhile,
/// returns a bare JWT in the `mobile-session` body when it renews.
///
/// Writing that token straight to the Keychain would produce `Cookie: eyJhbGciOi…` with no cookie
/// name, the server would find no session token, and the user would be signed out on the very
/// launch that was meant to keep them signed in — looking exactly like the bug it was fixing.
enum SessionCookie {

    /// Production uses the `__Secure-` prefix; development does not. The server accepts either, so
    /// the rule is to keep whichever name is already stored rather than to impose one.
    static let sessionCookieNames = ["__Secure-next-auth.session-token", "next-auth.session-token"]

    /// The name used when there is no stored cookie to learn one from.
    static let defaultSessionCookieName = "next-auth.session-token"

    /// Swap the session token's VALUE inside a stored Cookie header, keeping its name and every
    /// other cookie beside it.
    ///
    /// Other cookies matter: the CSRF one travels here too, and dropping it breaks the next write
    /// rather than the next read — a far more confusing failure than an outright sign-out.
    static func replacingToken(in stored: String?, with token: String) -> String {
        let pairs = (stored ?? "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !pairs.isEmpty else { return "\(defaultSessionCookieName)=\(token)" }

        var replaced = false
        var out: [String] = []
        for pair in pairs {
            // Split on the FIRST `=` only: base64url padding can put `=` inside the value, and
            // splitting on every one would silently truncate the token.
            let name = pair.prefix(while: { $0 != "=" })
            if sessionCookieNames.contains(String(name)) {
                out.append("\(name)=\(token)")
                replaced = true
            } else {
                out.append(pair)
            }
        }
        if !replaced { out.append("\(defaultSessionCookieName)=\(token)") }
        return out.joined(separator: "; ")
    }
}
