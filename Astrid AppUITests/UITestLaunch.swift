//  UITestLaunch.swift
//  How the UI suite launches the app (tasks 44a9cea5, b7fd8f70).
//
//  The launch arguments were wrong for months: every test passed `--uitesting` while the app
//  checked `-uiTesting`, so the six protections that keep a test run off Jon's real account
//  never engaged. The runner and the app now agree, and this is the only place the suite
//  spells it — a second literal is exactly how they drifted apart before.
//
//  It also names the environment variable carrying the session for the dedicated
//  `uitest@astrid.cc` account, which is what lets these tests be signed in at all. Without it
//  every test needing an account skipped itself, and the suite spent ten minutes per device
//  asserting eight things about the sign-in screen.
//
//  The existing `XCTSkip` guards are left alone deliberately: they check whether the sign-in
//  screen is showing, which is a true signal either way. Given a session they simply stop
//  firing, so the suite self-heals rather than needing twenty-five call sites rewritten.

import Foundation

enum UITestLaunch {

    /// The flag the app recognises. Must match `UITestSession.flags`.
    static let flag = "-uiTesting"

    /// Environment variable carrying the test account's session cookie. Mint one with:
    ///
    ///     cd ../astrid-web && npx tsx scripts/uitest-account.ts --cookie
    ///
    /// It expires after 30 days. Re-run the script rather than pasting a token into a file,
    /// where its expiry would look exactly like the skip it replaced.
    static let cookieKey = "ASTRID_UITEST_COOKIE"
}
