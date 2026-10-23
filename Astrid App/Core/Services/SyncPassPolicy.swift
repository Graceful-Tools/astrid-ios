import Foundation

/// How a sync pass decides to run. Pure and testable on purpose — the rules here and
/// below are the two ways a pass
/// used to stop delivering remote changes WITHOUT saying anything (Task:
/// 3173727d, "recently added tasks never show up; pull to refresh isn't adding
/// them, nor sync").
///
/// 1. **A refresh the user asked for is not the same as a timer tick.** Both
///    used to hit `guard !isSyncing else { return }`, so a pull-to-refresh that
///    landed while the 60-second background pass was running finished its
///    animation having fetched nothing.
/// 2. **Pushing local work is best-effort; fetching is not.** The incremental
///    pass pushed pending comments and list-member ops with a bare `try` before
///    it fetched, so ONE stuck local write meant no remote task ever arrived
///    again until the app was relaunched. The core's journal drains those writes
///    now; the `runPushSteps` helper that once encoded this had no caller (AITD-532).
enum SyncPassPolicy {

    enum Admission: Equatable {
        /// Nothing in flight — take the slot.
        case start
        /// Something is in flight and this pass was asked for by a person:
        /// wait for the slot rather than returning silently.
        case waitForInFlight
        /// Something is in flight and this pass is a timer tick: the in-flight
        /// one is already doing this work.
        case skip
    }

    static func admission(isSyncing: Bool, isUserInitiated: Bool) -> Admission {
        guard isSyncing else { return .start }
        return isUserInitiated ? .waitForInFlight : .skip
    }
}
