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

    /// Show the persistent chat column? Wide content + a real (non-virtual) list selected.
    static func showsChatColumn(contentWidth: CGFloat, isRealList: Bool) -> Bool {
        isRealList && contentWidth >= chatColumnContentThreshold
    }
}
#endif
