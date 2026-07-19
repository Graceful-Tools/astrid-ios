//  MacListPrivacy.swift
//  Astrid for Mac — pure model for a list's privacy + public type (Task 7d77a054).

#if os(macOS)
import Foundation

enum MacListPrivacy {
    struct Option: Identifiable, Equatable {
        let value: String; let label: String; var id: String { value }
        init(_ value: String, _ label: String) { self.value = value; self.label = label }
    }

    static let privacy: [Option] = [
        .init("PRIVATE", "Private"), .init("SHARED", "Shared"), .init("PUBLIC", "Public"),
    ]
    static let publicType: [Option] = [
        .init("collaborative", "Collaborative"), .init("copy_only", "Copy only"),
    ]

    /// updateListAdvanced payload — includes publicListType only when the list is public.
    static func updates(privacy: String, publicType: String) -> [String: Any] {
        var u: [String: Any] = ["privacy": privacy]
        if privacy == "PUBLIC" { u["publicListType"] = publicType }
        return u
    }
}
#endif
