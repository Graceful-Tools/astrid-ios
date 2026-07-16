//  MacRuntime.swift
//  Astrid for Mac — runtime environment probe (Task 90fa7975).
//
//  Under XCTest the app is the unit-test host: its scene graph still launches. If the root
//  view's .task kicks off the Outbox runner, the SSE socket, the sync schedulers, and the
//  global hotkey, those long-lived loops keep the host process alive and make test teardown
//  non-deterministic (the run hangs instead of exiting). Gate that startup on this flag so the
//  host stays inert during tests and exits cleanly.

import Foundation

enum MacRuntime {
    /// True when running inside an XCTest bundle (unit or UI tests set this env var).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}
