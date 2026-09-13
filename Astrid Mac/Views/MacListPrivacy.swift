//  MacListPrivacy.swift
//  Astrid for Mac — pure model for a list's privacy + public type (Task 7d77a054).
//
//  The five labels used to be hardcoded English ("Private", "Shared", "Public", "Collaborative",
//  "Copy only") — untranslated in twelve languages, which ASTRID.md rule 8 forbids — and none of
//  them said what the choice actually DID. Web spells out every consequence next to the control;
//  these descriptions are that text (AITD-388).

#if os(macOS)
import Foundation

enum MacListPrivacy {
    struct Option: Identifiable, Equatable {
        let value: String; let label: String; var id: String { value }
        init(_ value: String, _ label: String) { self.value = value; self.label = label }
    }

    private static func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    static var privacy: [Option] {
        [.init("PRIVATE", L("lists.privacy_private")),
         .init("SHARED", L("lists.privacy_shared")),
         .init("PUBLIC", L("lists.privacy_public"))]
    }

    static var publicType: [Option] {
        [.init("collaborative", L("lists.public_collaborative")),
         .init("copy_only", L("lists.public_copy_only"))]
    }

    /// What this privacy setting means for everyone else.
    static func privacyDescription(_ value: String) -> String {
        switch value {
        case "PUBLIC": return L("lists.privacy_public_description")
        case "SHARED": return L("lists.privacy_shared_description")
        default:       return L("lists.privacy_private_description")
        }
    }

    /// What a public list's type means for people who are not members.
    static func publicTypeDescription(_ value: String) -> String {
        value == "copy_only" ? L("lists.public_copy_only_description")
                             : L("lists.public_collaborative_description")
    }

    /// updateListAdvanced payload — includes publicListType only when the list is public.
    static func updates(privacy: String, publicType: String) -> [String: Any] {
        var u: [String: Any] = ["privacy": privacy]
        if privacy == "PUBLIC" { u["publicListType"] = publicType }
        return u
    }
}
#endif
