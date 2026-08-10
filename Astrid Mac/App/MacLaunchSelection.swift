//  MacLaunchSelection.swift
//  Astrid for Mac — which list the shell opens on.
//
//  The selection is kept in `@SceneStorage`, so the app reopened on whatever
//  list happened to be showing when it was last closed. That is fine as a
//  restore and poor as a landing: the saved id can point at a list that has
//  since been deleted, left, or unshared, which drops you on an empty pane with
//  nothing explaining why.
//
//  My Tasks is the one view that is meaningful for every user on every launch,
//  and it cannot go stale.

#if os(macOS)
import Foundation

enum MacLaunchSelection {

    /// The list the shell lands on when it appears.
    ///
    /// One rule covers both cases the app has: launching with a saved session,
    /// and signing in. The shell is constructed fresh in each, so "when it
    /// appears" is the same moment.
    ///
    /// `restored` is accepted and deliberately IGNORED — the parameter is here
    /// so that the decision to override a saved selection is visible at the call
    /// site and pinned by a test, rather than being an absence someone later
    /// "fixes" by reinstating the restore.
    static func landingListId(restored: String?, myTasksId: String) -> String {
        myTasksId
    }
}
#endif
