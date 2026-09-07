//  ListOrdering.swift
//  The one comparator that decides sidebar list order: favorites first, then alphabetical.
//
//  Task 63e75630 (AITD-314). This closure was written out four times in `ListService` alone, and a
//  live SSE insert would have made five. A list arriving over the wire has to land where the next
//  fetch would put it, which is only guaranteed if both call the same function.

import Foundation

enum ListOrdering {

    static func isOrderedBefore(_ list1: TaskList, _ list2: TaskList) -> Bool {
        let fav1 = list1.isFavorite ?? false
        let fav2 = list2.isFavorite ?? false
        if fav1 != fav2 {
            return fav1
        }
        return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
    }

    /// The index at which `list` belongs in an array already in this order.
    static func insertionIndex(for list: TaskList, in sorted: [TaskList]) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if isOrderedBefore(sorted[mid], list) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
