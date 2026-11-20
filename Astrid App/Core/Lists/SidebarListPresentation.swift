//  SidebarListPresentation.swift
//  What a sidebar list row shows beyond its name, shared by iPhone, iPad and Mac (ADEV-60).
//
//  The design review found the Mac sorting Favorites by name where iOS sorts by the order the
//  person set, and drawing no privacy mark at all. One copy here, so the two cannot drift again.

import SwiftUI

enum SidebarFavorites {
    /// The favorite lists, in the order the person arranged them; unordered ones last.
    static func ordered(_ lists: [TaskList]) -> [TaskList] {
        lists
            .filter { $0.isDomainList && $0.isFavorite == true }
            .sorted { ($0.favoriteOrder ?? 999) < ($1.favoriteOrder ?? 999) }
    }
}

/// The list row's privacy mark: a globe for a public list, two people for a shared one, nothing
/// for a private list.
struct ListPrivacyGlyph: View {
    let privacy: TaskList.Privacy?

    var body: some View {
        switch privacy {
        case .PUBLIC:
            Image(systemName: "globe")
                .font(.caption)
                .foregroundColor(Theme.accent)
        case .SHARED:
            Image(systemName: "person.2.fill")
                .font(.caption)
                .foregroundColor(Theme.success)
        case .PRIVATE, .none:
            EmptyView()
        }
    }
}
