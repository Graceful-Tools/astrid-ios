//  MacSessionStart.swift
//  Makes post-auth startup happen exactly once per signed-in session (Task 0e0bcf69 / AITD-315).
//
//  `MacAuthGateView` reaches `startSession()` down two paths at cold launch, and with a stored
//  session it took BOTH. `AuthManager.isAuthenticated` starts false, so `checkAuthentication()`
//  flips it and fires `.onChange` → `startSession()`; the enclosing `.task` then resumes and calls
//  `startSession()` again on the very next line. That is two `performFullSync(includeUserTasks:)`
//  passes — and because both are user-initiated, `SyncPassPolicy` makes the second WAIT for the
//  first and then run the whole pull again — plus two GitHub status fetches and two sync schedules,
//  before the user can do anything.
//
//  A latch rather than deleting one of the two calls: `.onChange` only fires on a *change*, so on
//  any path where `isAuthenticated` is already true when the gate appears, deleting the inline call
//  would start no session at all. Whichever caller arrives first should own the launch.

import Foundation

@MainActor
enum MacSessionStart {

    private static var started = false

    /// True for the caller that owns this session's startup; false for everyone after it.
    ///
    /// Check-and-set with **no suspension point between them**. Both callers run on the MainActor,
    /// so there is no interleaving here and exactly one of them can win. Putting an `await` between
    /// the read and the write is what would let both through — which is the bug this replaces.
    static func claim() -> Bool {
        guard !started else { return false }
        started = true
        return true
    }

    /// Re-arm after sign-out. Without this, signing out and back in inside one process would leave
    /// the app with no SSE connection and no sync timer until relaunch.
    static func release() {
        started = false
    }

    /// Test seam — the launch state of a fresh process.
    static var hasStarted: Bool { started }
}
