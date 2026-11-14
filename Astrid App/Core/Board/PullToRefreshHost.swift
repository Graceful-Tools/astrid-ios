//  PullToRefreshHost.swift
//  Which scroll view owns pull-to-refresh on the task screen (AITD-670).
//
//  A list refreshes from the page, as it always has. A board must not: a page-level refresh
//  control bounced the column carousel vertically while swiping between columns, so it was
//  switched off in board mode — and the board was left with no pull-to-refresh at all. Each
//  column's own card scroll owns the pull instead, so pulling any column down refreshes the board
//  while the horizontal carousel never sees a refresh control.

enum PullToRefreshHost: Equatable {
    /// The list's page scroll.
    case page
    /// Each board column's vertical card scroll.
    case boardColumns

    static func resolve(showingBoard: Bool) -> PullToRefreshHost {
        showingBoard ? .boardColumns : .page
    }

    var pageIsRefreshable: Bool { self == .page }
    var columnsAreRefreshable: Bool { self == .boardColumns }
}
