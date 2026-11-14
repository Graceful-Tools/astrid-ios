//  FuzzyMatch.swift
//  Astrid for Mac — fuzzy ranking for the ⌘K command palette / quick-open (M2).
//
//  The matcher and its ranking are astrid-core's `paletteRank` (AITD-667), which `palette.rs`
//  ported from this file: every character of the query in order, with bonuses for a run of
//  consecutive characters, a word start and the start of the title; a tie to the shorter title,
//  then to the order given. Windows and Android rank their palettes with the same rule, so the
//  same three letters find the same first row everywhere.

import AstridCore
import Foundation

enum FuzzyMatch {
    /// The items whose title matches `query`, best first. The caller trims the query and
    /// decides what an empty one shows.
    static func ranked<Item>(_ query: String, _ items: [Item], title: (Item) -> String) -> [Item] {
        CoreRules.paletteRank(query: query, titles: items.map(title)).compactMap { index in
            items.indices.contains(index) ? items[index] : nil
        }
    }
}
