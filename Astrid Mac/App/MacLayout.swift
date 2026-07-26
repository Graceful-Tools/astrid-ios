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

    // MARK: - Detail pop-out geometry
    //
    // The pop-out floats over the CHAT column, never over the task rows, and the task list never
    // gives up width for it — rows must not resize when a task is selected. That is only possible
    // if the chat column is permanently at least as wide as the pop-out plus its margins, which is
    // how chatColumnWidth is derived below rather than being a magic number.
    static let detailPanelWidth: CGFloat = 380
    static let detailArrowWidth: CGFloat = 12
    /// Breathing room on each side of the floating panel: the arrow needs room on the leading
    /// edge, and the panel needs a matching margin on the trailing edge.
    static let detailPanelMargin: CGFloat = 14

    /// Total width the floating pop-out occupies, margins included.
    static var detailPopoutWidth: CGFloat {
        detailPanelWidth + detailArrowWidth + detailPanelMargin * 2
    }

    /// The chat column is sized to CONTAIN the pop-out, so the panel can float over it without the
    /// task list ever shrinking (and the arrow still lands beside the rows).
    static var chatColumnWidth: CGFloat { detailPopoutWidth }

    /// Show the persistent chat column? Wide content + a real (non-virtual) list selected.
    static func showsChatColumn(contentWidth: CGFloat, isRealList: Bool) -> Bool {
        isRealList && contentWidth >= chatColumnContentThreshold
    }
}
#endif
