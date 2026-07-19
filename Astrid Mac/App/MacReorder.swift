//  MacReorder.swift
//  Astrid for Mac — pure within-list reorder computation (Task 7b7a17d3). Kept pure so the new
//  manual order is unit-testable without a running List.

#if os(macOS)
import SwiftUI   // move(fromOffsets:toOffset:) is a SwiftUI extension on RangeReplaceableCollection

enum MacReorder {
    /// The task-id order after moving the rows at `source` to `destination` (SwiftUI onMove semantics).
    static func reordered(_ ids: [String], from source: IndexSet, to destination: Int) -> [String] {
        var out = ids
        out.move(fromOffsets: source, toOffset: destination)
        return out
    }
}
#endif
