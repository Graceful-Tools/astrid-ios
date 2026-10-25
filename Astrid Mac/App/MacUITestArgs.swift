//  MacUITestArgs.swift
//  Astrid for Mac — parsing for the test-only launch flags (Task 69ff12e7).
//
//  `-uiTestSelectRow 0` (two tokens) makes the app launch with NO window at all: XCUITest sees
//  `windows=0` and neither the sign-in screen nor the shell ever appears, which took out every
//  UI test that needs a selected row. `-uiTestSelectRow=0` (one token) launches normally —
//  measured across four variants, and the bare value is what breaks it, not the key or the count:
//
//      -uiTesting                                   → 1 window
//      -uiTesting -uiTestSelectRow=0                → 1 window
//      -uiTesting -uiTestSelectRow 0                → 0 windows
//      -uiTesting -pad 1 -uiTestSelectRow 0         → 0 windows
//
//  So the single-token form is the supported one. The two-token form is still parsed — it simply
//  never gets the chance to matter, and dropping it would silently ignore an old invocation.

#if os(macOS)
import Foundation

enum MacUITestArgs {
    /// Passed by every Mac UI test (`MacUITestLaunch.makeApp`). Skips onboarding, forces the
    /// login screen regardless of the saved session, and leaves the launch selection alone.
    static let uiTestingFlag = "-uiTesting"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingFlag)
    }

    /// How a launch decides whether it is signed in (AITD-529).
    enum LaunchAuth: Equatable {
        /// Not a UI test: the saved session decides.
        case normal
        /// A UI test handed no session: the sign-in screen, whatever the machine has saved.
        case signedOut
        /// A UI test handed the per-run account's session: sign in with it, and nothing else.
        case injectedSession
    }

    /// `-uiTesting` used to force signed-out unconditionally, so the Mac suite could never be
    /// signed in and had no end-to-end coverage at all. The keychain already hands back an
    /// injected cookie under the flag (and only under it); this lets the gate use it.
    static func launchAuth(arguments: [String], environment: [String: String]) -> LaunchAuth {
        guard UITestSession.isUITesting(arguments: arguments) else { return .normal }
        return UITestSession.injectedCookie(arguments: arguments, environment: environment) != nil
            ? .injectedSession : .signedOut
    }

    static var launchAuth: LaunchAuth {
        launchAuth(arguments: ProcessInfo.processInfo.arguments,
                   environment: ProcessInfo.processInfo.environment)
    }

    static let selectRowFlag = "-uiTestSelectRow"

    /// The row index requested by `-uiTestSelectRow=<n>` (preferred) or `-uiTestSelectRow <n>`.
    static func selectedRowIndex(from arguments: [String]) -> Int? {
        for (i, arg) in arguments.enumerated() {
            if arg.hasPrefix(selectRowFlag + "=") {
                return Int(arg.dropFirst(selectRowFlag.count + 1))
            }
            if arg == selectRowFlag, i + 1 < arguments.count {
                return Int(arguments[i + 1])
            }
        }
        return nil
    }

    static let selectTaskFlag = "-uiTestSelectTask"

    /// The task id requested by `-uiTestSelectTask=<id>` (AITD-529) — single-token only, for the
    /// reason at the top of this file. `-uiTestSelectRow` names a position, and the order of a
    /// signed-in account's rows is the server's business; the journeys name the fixture they
    /// mean. XCUITest cannot click a macOS List row, so this is how a journey selects one.
    static func selectedTaskId(from arguments: [String]) -> String? {
        for arg in arguments where arg.hasPrefix(selectTaskFlag + "=") {
            let id = String(arg.dropFirst(selectTaskFlag.count + 1))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// Whether this launch asked for a row to be selected, either way.
    static func selectsRow(arguments: [String]) -> Bool {
        selectedRowIndex(from: arguments) != nil || selectedTaskId(from: arguments) != nil
    }

    /// Which of `rowIds` the launch asked for, if any of them.
    static func requestedRow(in rowIds: [String], arguments: [String]) -> String? {
        if let id = selectedTaskId(from: arguments) { return rowIds.contains(id) ? id : nil }
        if let n = selectedRowIndex(from: arguments), rowIds.indices.contains(n) { return rowIds[n] }
        return nil
    }
}
#endif
