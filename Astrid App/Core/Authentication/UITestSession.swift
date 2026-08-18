import Foundation

/// What a UI-test run is, and what credential it may use (tasks 44a9cea5, b7fd8f70).
///
/// **Why this type exists at all.** Six places re-derived
/// `ProcessInfo.processInfo.arguments.contains("-uiTesting")` — the Core Data store, the
/// keychain, cookie isolation, the outbox, connection-mode persistence — while every UI test
/// launched the app with `--uitesting`. One dash and a lowercase T apart, so **none of those
/// guards ever engaged**. The comment on the keychain guard describes what they exist to
/// prevent, in the past tense: a UI test once created lists in the real account. One
/// definition, in one place, is the fix.
///
/// **Why it also owns the credential.** Fixing the spelling alone would have made the second
/// problem permanent. A blanked keychain means the app can never be signed in under test,
/// and the suite skipped every signed-in test for exactly that reason — ten minutes per
/// device to assert eight things about the sign-in screen.
///
/// So the isolation distinguishes two things that used to be one:
///
///   - **the user's real credential**, which stays unreachable under test, and
///   - **a credential this run was explicitly handed**, which is the dedicated
///     `uitest@astrid.cc` account (`astrid-web/scripts/uitest-account.ts`).
///
/// The asymmetry is deliberate. Nothing is inherited; a test is signed in only when someone
/// passed it a session, and only for as long as that session lasts.
enum UITestSession {

    /// Accepted spellings of the flag.
    ///
    /// `--uitesting` is here on purpose. It is what the suite has actually been passing, and
    /// rejecting it would mean the guards keep not engaging until every test file is updated
    /// — which is the status quo, and the status quo is a suite running against a real
    /// account. Accepting both makes the protection work now; the tests pass `-uiTesting`
    /// from this change on.
    static let flags: Set<String> = ["-uiTesting", "--uitesting", "--uiTesting"]

    /// Launch argument carrying the session cookie.
    static let cookieArgument = "-uiTestSessionCookie"

    /// Environment variable carrying the session cookie. Preferred in CI: an argument list is
    /// visible in `ps`, an environment variable is not.
    static let cookieEnvironmentKey = "ASTRID_UITEST_COOKIE"

    static func isUITesting(arguments: [String]) -> Bool {
        arguments.contains { flags.contains($0) }
    }

    /// Whether this run must not open interrupting prompts — the push-notification ask, the
    /// review ask, anything modal that arrives on a timer rather than on a tap.
    ///
    /// **This is what made the UI suite look broken** (task b86c97c5). `AstridApp` fires the
    /// push prompt one second after `isAuthenticated` turns true, and the whole point of the
    /// suite's injected session is to turn it true — so every run was interrupted by
    /// construction. A modal alert makes every element beneath it report `isHittable == false`
    /// and swallows every tap, so a row tap never reached the row and "Task Details" never
    /// appeared. Three investigations blamed the query, the sidebar, and finally XCUITest
    /// itself, because the alert is off to the side of the thing you are looking at.
    ///
    /// Derived from the flag rather than spelled again: six places once re-derived
    /// `-uiTesting` and all six were wrong together, which is why this type exists.
    static func suppressesInterruptingPrompts(arguments: [String]) -> Bool {
        isUITesting(arguments: arguments)
    }

    /// The live answer for this process.
    static var suppressesInterruptingPrompts: Bool { isUITesting }

    /// The live answer for this process.
    static let isUITesting = isUITesting(arguments: ProcessInfo.processInfo.arguments)

    /// The session cookie this test run was handed, or nil.
    ///
    /// **Only under the flag.** A stray `ASTRID_UITEST_COOKIE` in someone's shell must not
    /// quietly point the real app at the test account — that is the same class of accident
    /// as the one this file exists to prevent, pointed the other way.
    static func injectedCookie(arguments: [String], environment: [String: String]) -> String? {
        guard isUITesting(arguments: arguments) else { return nil }

        if let index = arguments.firstIndex(of: cookieArgument),
           // A trailing flag with no value must not read past the end.
           index + 1 < arguments.count {
            if let value = nonEmpty(arguments[index + 1]) { return value }
        }
        return nonEmpty(environment[cookieEnvironmentKey])
    }

    /// The live answer for this process.
    static var injectedCookie: String? {
        injectedCookie(arguments: ProcessInfo.processInfo.arguments,
                       environment: ProcessInfo.processInfo.environment)
    }

    /// Which server a run talks to.
    ///
    /// **Why this lives here.** The injected credential is a session for `uitest@astrid.cc` on
    /// PRODUCTION. A Debug build defaults to `http://localhost:3000`, so the app was sending a
    /// production cookie to a dev server that was not running — the request failed, auth fell
    /// through to "not signed in", and every test that needed an account skipped itself. The
    /// account was real, the cookie arrived, and the app still showed the welcome screen; it
    /// took a simulator console log to see that the host was wrong (task 44a9cea5).
    ///
    /// A credential and a host are one decision, not two. Under the flag, the run goes to
    /// production regardless of the Debug default.
    ///
    /// **The debug preference is ignored too, deliberately.** UI tests share the shipping bundle
    /// id, so `debug_server_url` is the DEVELOPER'S setting sitting in the same container. A run
    /// that inherited it would point at whatever host they last used and fail somewhere else
    /// entirely — the same class of leak the keychain guard exists to prevent.
    static func resolvedBaseURL(isUITesting: Bool,
                                debugPreference: String?,
                                defaultURL: String,
                                productionURL: String) -> String {
        if isUITesting { return productionURL }
        if let preference = nonEmpty(debugPreference) { return preference }
        return defaultURL
    }

    /// An unset shell variable expands to the empty string, and a blank credential produces a
    /// puzzling 401 rather than an obviously signed-out app.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
