import Foundation

/// Which app this build is, stated on every request (task 119cabc3).
///
/// The apps used to send nothing that identified them, so astrid-web's `detectPlatform()` fell
/// back to sniffing the user agent URLSession composes for us. It matches `AstridApp/` or
/// `Astrid/`; the bundle name yields `Astrid App/231 CFNetwork/…`, which contains neither — a
/// space where the slash is expected. Two consequences, and the second was the reported one:
///
///   - iOS traffic very likely landed in UNKNOWN rather than the iOS bucket
///   - the Mac had no bucket at all, since the server's platform list has no Mac entry
///
/// Stating the platform outright removes the guessing. `detectPlatform` checks this header
/// FIRST, before any user-agent matching, so it wins regardless of what Apple puts in the agent
/// string this OS release.
///
/// **Cross-repo contract.** These strings are matched exactly in `astrid-web`'s
/// `lib/analytics-events.ts`. A typo here is indistinguishable from sending nothing — the
/// dashboard simply keeps under-counting — which is why the values are pinned by tests.
enum AnalyticsPlatformHeader {

    static let headerName = "x-platform"

    /// Matches `AnalyticsPlatform.IOS_APP` on the server.
    static let iOS = "ios-app"

    /// Matches `AnalyticsPlatform.MAC_APP` — which does not exist server-side yet. Until it
    /// does, this value is unrecognised and the Mac falls through to UNKNOWN, exactly where it
    /// already was, so sending it early costs nothing.
    static let mac = "mac-app"

    /// What this build claims to be. One switch, so the two targets cannot drift.
    static var current: String {
        #if os(macOS)
        return mac
        #else
        return iOS
        #endif
    }

    /// Stamp the platform on a request bound for the Astrid backend (AITD-301).
    ///
    /// Every call site goes through this rather than restating the header name and value: the two
    /// clients did state them correctly, but `APIEndpoint` hardcoded `"ios-app"` — in a file the
    /// Mac target compiles too — and the SSE stream, the passkey calls, attachments and the OAuth
    /// token identified nothing at all. Mac activity cannot be told apart from iOS, or from
    /// nothing, unless it is stated on the way out.
    ///
    /// `setValue` rather than `addValue`: the server matches the value by equality, so a
    /// duplicated header would read as an unrecognised platform and land in UNKNOWN.
    ///
    /// **Astrid-bound requests only.** Vercel Blob uploads and Google's token endpoint are third
    /// parties; our analytics header is not theirs to receive.
    static func apply(to request: inout URLRequest) {
        request.setValue(current, forHTTPHeaderField: headerName)
    }
}
