//  MacRowKey.swift
//  Astrid for Mac — a cheap identity key for the rendered task list (Task e949df82).
//
//  `.animation(value:)` and `.onChange(of:)` both need "did the set of visible rows change?".
//  Feeding them `rows.map(\.id)` answered that correctly but allocated a fresh [String] of every
//  visible row on EVERY body evaluation — pure churn on the app's hottest path, growing with list
//  size. Hashing the same information answers the same question without materialising anything.
//
//  Deliberately hashes every id rather than the cheaper count + first + last: a middle-of-the-list
//  reorder (a drag) leaves all three unchanged, and the list would animate rows into the wrong
//  places. Hashing is still one pass, just an allocation-free one.

#if os(macOS)
import Foundation

enum MacRowKey {
    static func key(_ rows: [Task]) -> Int {
        var hasher = Hasher()
        hasher.combine(rows.count)
        for row in rows { hasher.combine(row.id) }
        return hasher.finalize()
    }
}
#endif
