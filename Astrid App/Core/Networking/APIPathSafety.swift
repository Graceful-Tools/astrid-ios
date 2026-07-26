//  APIPathSafety.swift
//  Security: keep attacker-influenced identifiers from steering API requests.
//
//  Task/list ids reach the networking layer from places a user does not fully control —
//  most importantly deep links (`astrid://tasks/<id>`, `https://astrid.cc/tasks/<id>`), which
//  any web page or message can hand us. Those ids are interpolated straight into request paths
//  (`/api/v1/tasks/\(id)`), and Foundation does NOT normalize or escape the result: a
//  percent-encoded slash survives `URL.lastPathComponent` as a real separator, so
//  `astrid://tasks/abc%2F..%2Fadmin` produced `https://astrid.cc/api/v1/tasks/abc/../admin` —
//  which servers and CDNs typically resolve to `/api/v1/admin`, issued with the user's session.
//
//  Two independent guards, so neither one is load-bearing alone:
//    1. `isValidIdentifier` — deep links accept only id-shaped strings, before anything is opened.
//    2. `escapedPathComponent` — anything interpolated into a path is percent-encoded, so a
//       stray separator cannot change the request's shape even if guard 1 is bypassed.
import Foundation

enum APIPathSafety {

    /// Characters legal in an Astrid identifier (UUIDs, short codes, prefixed local ids).
    /// Deliberately excludes `/`, `.`, `%`, and whitespace — the ingredients of path traversal.
    private static let allowedIdentifier = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// Whether `id` is safe to route on and to place in a request path.
    /// Length is bounded so a pathological link can't drive an enormous URL.
    static func isValidIdentifier(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy { allowedIdentifier.contains($0) }
    }

    /// Whether a fully built request path is free of traversal segments.
    ///
    /// This is the backstop applied at the single point where every request URL is constructed:
    /// no matter which call site interpolated an id, a path that could be normalized by the
    /// server into a different endpoint never leaves the device.
    static func isSafeRequestPath(_ path: String) -> Bool {
        // Compare on the decoded form too — `%2E%2E%2F` decodes to `../` at the server.
        let decoded = path.removingPercentEncoding ?? path
        for candidate in [path, decoded] {
            let segments = candidate.split(separator: "/", omittingEmptySubsequences: true)
            if segments.contains("..") || segments.contains(".") { return false }
        }
        return true
    }

    /// Percent-encode a value for use as a single path component.
    /// `/` is NOT in the allowed set, so an embedded separator becomes `%2F` and stays inert.
    static func escapedPathComponent(_ value: String) -> String {
        // .urlPathAllowed still permits "/", which is exactly what we must neutralize here.
        let unreserved = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
