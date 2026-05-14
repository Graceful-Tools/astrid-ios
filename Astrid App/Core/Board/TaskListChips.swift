import Foundation

/// Filter helpers for the list-row "list tag" chip set.
///
/// A task in a board-backed list can carry status-list memberships
/// (Ready / Doing / Waiting) alongside its regular (domain) list. Those
/// status lists shouldn't appear as chips in the flat list view — the
/// status concept only makes sense inside the board carousel.
///
/// TaskRowView pipes `task.lists` through `chipListsForTaskRow(_:)`
/// before rendering so the right chip ("My Project List") survives the
/// `prefix(2)` truncation instead of getting pushed out by "Ready".

/// Returns the lists worth surfacing as chips on a flat task row:
/// every regular list, in original order, with status lists removed.
///
/// `hiddenListIds` are list ids the surrounding view already conveys
/// to the user — they'd appear as redundant noise in chip form.
/// Examples:
///   - In the LIST view: the list currently being viewed.
///   - In the BOARD view: the project's domain list (the whole board
///     is already inside that list) AND the current column's status
///     list (the column header already says "Doing").
///
/// Pure / synchronous: just an array filter. No rendering delay.
func chipListsForTaskRow(_ lists: [TaskList]?,
                         hiddenListIds: Set<String> = []) -> [TaskList] {
    guard let lists = lists else { return [] }
    return lists.filter { list in
        list.listType != "status" && !hiddenListIds.contains(list.id)
    }
}
