//  MacLayout.swift
//  Astrid for Mac — responsive 2/3-column rule (Task 23c98550), mirroring the web's
//  lib/layout-detection.ts: a ≥1100px window is 3-column with chat always visible as the right
//  column. The Mac content area sits next to a ~240pt sidebar, so the equivalent CONTENT width
//  threshold is 1100 − 240 = 860pt. Below that, chat stays a content mode (2-column).

#if os(macOS)
import Foundation

enum MacLayout {
    /// Web's 3-column window threshold (1100) minus the Mac sidebar's ideal width (240).
    static let chatColumnContentThreshold: CGFloat = 860
    static let chatColumnWidth: CGFloat = 320

    // Detail pop-out geometry. The panel FLOATS over the content, so unless the task list
    // reserves this width the rows slide underneath it: the visible list looked clipped/narrow and
    // the arrow overlapped rows instead of meeting their trailing edge (task f993dbe0).
    static let detailPanelWidth: CGFloat = 380
    static let detailArrowWidth: CGFloat = 12
    static let detailPanelTrailingInset: CGFloat = 14
    /// Total width the pop-out occupies — what the task list must give up while it is open.
    static var detailPopoutWidth: CGFloat { detailPanelWidth + detailArrowWidth + detailPanelTrailingInset }

    /// Width left for the task list when the pop-out is open. The list should stay WIDER than the
    /// panel; below that the window is too narrow to show both, so the pop-out is not reserved
    /// space (it floats, as before) rather than squeezing the list to a sliver.
    static func taskListWidth(contentWidth: CGFloat, popoutVisible: Bool) -> CGFloat {
        guard popoutVisible else { return contentWidth }
        let remaining = contentWidth - detailPopoutWidth
        return remaining >= detailPopoutWidth ? remaining : contentWidth
    }

    /// Should the list reserve space for the pop-out (rather than let it overlay the rows)?
    static func reservesDetailSpace(contentWidth: CGFloat, popoutVisible: Bool) -> Bool {
        popoutVisible && contentWidth - detailPopoutWidth >= detailPopoutWidth
    }

    /// Show the persistent chat column? Wide content + a real (non-virtual) list selected.
    static func showsChatColumn(contentWidth: CGFloat, isRealList: Bool) -> Bool {
        isRealList && contentWidth >= chatColumnContentThreshold
    }
}
#endif
