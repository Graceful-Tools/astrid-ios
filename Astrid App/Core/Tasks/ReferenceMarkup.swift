//  ReferenceMarkup.swift
//  Astrid — how a picked @person, #list or !task is written into a comment or chat message.
//
//  `@[Name](id)` is what draws the pill and notifies the person; plain `@Name` is only text. iOS
//  writes the reference (AutocompleteSupport's `reconstructReferencesInText`, on send); the Mac
//  wrote plain `@label`, so a mention typed there reached nobody (astrid-core CONTRACTS D23).
//  Jon, 2026-10-03: on disagreement follow iOS — both apps build the reference here.

import Foundation

enum ReferenceMarkup {
    /// `<trigger>[<name>](<id>)`, e.g. `@[Dana](u-123)`, `#[Work](l-9)`, `![Buy milk](t-4)`.
    static func reference(trigger: Character, name: String, id: String) -> String {
        "\(trigger)[\(name)](\(id))"
    }
}
