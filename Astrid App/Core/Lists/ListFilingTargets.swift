//  ListFilingTargets.swift
//  Astrid — which lists a task can be filed in from a list picker, for iOS and Mac alike
//  (astrid-core CONTRACTS D28).
//
//  iOS's InlineListsPicker leaves out virtual lists (saved filters), which own no tasks. The Mac's
//  MacListPicker left out board-status lists instead, and so offered saved filters. Jon,
//  2026-10-03: on disagreement follow iOS — so the rule lives here and both pickers call it.

import Foundation

enum ListFilingTargets {
    /// The lists a task can be put in: every list except a virtual one.
    static func lists(_ lists: [TaskList]) -> [TaskList] {
        lists.filter { $0.isVirtual != true }
    }
}
