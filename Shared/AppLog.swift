import Foundation

/// Debug-only diagnostics for everyday app logging.
///
/// The message is an `@autoclosure` evaluated inside `#if DEBUG`, so in a Release
/// build the string is never built and the call is not compiled in at all. That is
/// the difference from `print`, which ships: `ImageCache` logs once per avatar per
/// row render and `SSEClient` once per received event, and every one of those
/// interpolations was being paid for in the App Store binary with nobody there to
/// read the result.
///
/// For diagnostics that must survive into Release, do not use this — use
/// `Logger(subsystem: Brand.logSubsystem, category:)` directly and give every
/// interpolated value an explicit privacy level.
///
/// This lives in `Shared/` because that group is synced into all three targets:
/// `Astrid App`, `Astrid Mac`, and the `Astrid` share extension. `Brand` is in the
/// app tree and the extension cannot see it, so `AppLog` deliberately does not
/// depend on it.
nonisolated enum AppLog {
    nonisolated static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        Swift.print(message())
        #endif
    }

    /// An email reduced to a first initial and its domain — `j•••@example.com`.
    /// Enough to tell two members apart while debugging; not the address itself.
    ///
    /// Emails are account identifiers, which `PrivacyLogger`'s contract says never
    /// to log. Compiling the call out of Release is not on its own a reason to
    /// build the address into a string in Debug either.
    nonisolated static func redact(email: String?) -> String {
        guard let email, !email.isEmpty else { return "<none>" }
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return "•••" }
        return "\(email[email.startIndex])•••\(email[at...])"
    }
}
