import Foundation

/// Is there a newer version of the app, and should we say so? (AITD-383)
///
/// Pure, so the rules below can be tested without a network, a build number or a real install —
/// and shared by iOS and Mac, because "is 1.10 newer than 1.9" must not have two answers.
///
/// WHY NOT JUST COMPARE THE STRINGS. "1.10.0" sorts BEFORE "1.9.2" lexicographically, so a string
/// compare tells the one user on the newest build that they are behind. Versions are lists of
/// numbers, and that is how they get compared here.
enum AppVersionCheck {

    /// Split a version into its numeric components.
    ///
    /// Anything non-numeric in a component reads as 0 rather than throwing: a build calling itself
    /// "1.9.2-beta" is a real thing that happens, and refusing to parse it would turn a cosmetic
    /// suffix into a crash or a permanently silent check. Trailing junk is simply not decisive.
    static func components(_ version: String) -> [Int] {
        version
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    /// Order two versions. Missing components count as 0, so "1.9" == "1.9.0" — a server that
    /// reports two components and an app that reports three must not read as an upgrade forever.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = components(lhs), b = components(rhs)
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Is `latest` actually newer than `current`?
    static func isNewer(_ latest: String, than current: String) -> Bool {
        compare(latest, current) == .orderedDescending
    }

    /// Should the update card be shown?
    ///
    /// STRICTLY NEWER, never "different" (AITD-383). Internal TestFlight builds routinely carry a
    /// HIGHER version than anything published, so "latest != current" would nag every internal
    /// build to downgrade to the App Store release — which is both wrong and unfixable by the
    /// person seeing it.
    ///
    /// DISMISSAL IS PER VERSION. `dismissedVersion` silences only the version it names: dismissing
    /// 1.9.2 must not also swallow 1.9.3, or one tap turns the feature off for good. A dismissal
    /// that is itself stale — the user dismissed 1.9.2, the server now offers 1.9.3 — stops
    /// applying, because it was an answer to a different question.
    ///
    /// A MISSING OR UNREADABLE `latest` IS NOT AN UPDATE. The endpoint does not exist yet
    /// (astrid-web deploys by hand), so "we could not find out" has to be indistinguishable from
    /// "you are up to date" — silence, not a banner.
    static func shouldPrompt(current: String?,
                             latest: String?,
                             dismissedVersion: String?) -> Bool {
        guard let current, !current.isEmpty,
              let latest, !latest.isEmpty else { return false }
        guard isNewer(latest, than: current) else { return false }
        // Only a dismissal of THIS version counts.
        if let dismissedVersion, compare(dismissedVersion, latest) != .orderedAscending {
            return false
        }
        return true
    }
}
