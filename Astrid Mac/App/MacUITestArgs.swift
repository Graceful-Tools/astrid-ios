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
}
#endif
