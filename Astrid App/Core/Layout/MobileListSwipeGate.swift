import CoreGraphics
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

/// Inputs for the board's swipe-to-open-sidebar decision.
struct BoardSidebarSwipeState: Equatable {
    var isMobile: Bool
    /// True when the visible column is the left-most one (the virtual Inbox).
    var isAtLeftmostColumn: Bool
    var translationWidth: CGFloat
    var translationHeight: CGFloat
    var predictedEndTranslationWidth: CGFloat
}

/// On a board the column carousel owns horizontal pans, EXCEPT at the left-most
/// column: there's nothing further left to scroll to, so a left-to-right swipe
/// should open the sidebar — matching a regular list. Thresholds mirror the
/// list's swipe-to-open gesture.
func shouldBoardSwipeOpenSidebar(_ state: BoardSidebarSwipeState) -> Bool {
    guard state.isMobile, state.isAtLeftmostColumn else { return false }
    let isHorizontal = state.translationWidth > abs(state.translationHeight)
    let isRight = state.translationWidth > 0
    let meetsThreshold = state.translationWidth > 80 || state.predictedEndTranslationWidth > 200
    return isHorizontal && isRight && meetsThreshold
}
