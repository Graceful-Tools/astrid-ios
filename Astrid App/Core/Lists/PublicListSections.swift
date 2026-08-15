import Foundation

/// How public lists are grouped in a sidebar (Task dfb037c7).
///
/// Two sections, and the split decides what someone is offered:
///
///   - **Public & Shared** — collaborative lists, which you can contribute to.
///   - **Public Lists** — copy-only, which you may read and copy but not write.
///
/// Getting it backwards either offers a write affordance on a list the server will refuse, or
/// buries a collaborative list among the read-only ones. iOS had this inline; a Mac copy would
/// have been the second place deciding what "collaborative" means, so it lives here instead.
enum PublicListSections {

    /// The one type that means "you can contribute". Anything else — including nil, and including
    /// a type from a newer server — is browse-only, because that is the safe direction to guess.
    static let collaborativeType = "collaborative"

    /// How many rows a section shows before deferring to the full browser. A sidebar is about
    /// YOUR lists; without a cap, other people's swamp it.
    static let sidebarLimit = 2

    static func collaborative(_ lists: [TaskList]) -> [TaskList] {
        lists.filter { $0.publicListType == collaborativeType }
    }

    static func browsable(_ lists: [TaskList]) -> [TaskList] {
        lists.filter { $0.publicListType != collaborativeType }
    }

    static func sidebarRows(_ section: [TaskList]) -> [TaskList] {
        Array(section.prefix(sidebarLimit))
    }

    /// Is there anything the cap is hiding? Exactly `sidebarLimit` is not "more".
    static func hasMore(_ section: [TaskList]) -> Bool {
        section.count > sidebarLimit
    }
}
