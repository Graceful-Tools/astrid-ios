//  FuzzyMatch.swift
//  Astrid for Mac — fuzzy subsequence matching for the ⌘K command palette / quick-open (M2).

import Foundation

enum FuzzyMatch {
    /// Returns a score (higher = better) if every char of `query` appears in `text` in order,
    /// else nil. Bonuses for consecutive matches, word-start matches, and a prefix match.
    static func score(_ query: String, _ text: String) -> Int? {
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        if q.isEmpty { return 0 }
        if q.count > t.count { return nil }

        var qi = 0, score = 0, streak = 0
        var prevMatchedIndex = -2
        for (ti, ch) in t.enumerated() {
            guard qi < q.count, ch == q[qi] else { continue }
            score += 1
            if ti == prevMatchedIndex + 1 { streak += 1; score += streak * 2 } else { streak = 0 }
            if ti == 0 { score += 8 }                                   // prefix
            else if !t[ti - 1].isLetter && !t[ti - 1].isNumber { score += 4 }  // word start
            prevMatchedIndex = ti
            qi += 1
        }
        return qi == q.count ? score : nil
    }
}
