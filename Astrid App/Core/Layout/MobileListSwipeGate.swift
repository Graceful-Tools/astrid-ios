import Foundation

/// Swift port of `hooks/use-mobile-list-swipe-gate.ts` from astrid-web.
/// Decides whether the iPhone shell's horizontal swipe gestures (open
/// sidebar on swipe-right, etc.) should fire.
///
/// Returns `false` when the board view is active so the board's column
/// carousel owns the horizontal gesture — without this gate the
/// sidebar pulls in mid-pan and the board jumps.

struct MobileListSwipeGateState: Equatable {
    var isMobile: Bool
    /// Whatever the top-level view considers the "current pane". We only
    /// fire when it equals "list". Strings keep this in sync with web.
    var mobileView: String
    var showMobileSidebar: Bool
    var isBoardMode: Bool
}

func shouldHandleMobileListSwipe(_ state: MobileListSwipeGateState) -> Bool {
    if !state.isMobile { return false }
    if state.mobileView != "list" { return false }
    if state.showMobileSidebar { return false }
    if state.isBoardMode { return false }
    return true
}
