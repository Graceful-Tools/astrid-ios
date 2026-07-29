//  MacProfileStats.swift
//  Astrid for Mac — the profile's three stat cards and its link rules (Task 0994eabb).
//
//  ProfileCache, UserStats and every string this needs were already shared; the Mac just never had
//  a profile screen. The card order, symbols and wording are pinned here so the Mac cannot drift
//  from iOS `UserProfileView.statsGrid`.

#if os(macOS)
import SwiftUI

enum MacProfileStats {
    struct Card: Equatable {
        let labelKey: String
        let taglineKey: String
        let symbol: String
        let tint: Color
        let value: Int

        var label: String { NSLocalizedString(labelKey, comment: "") }
        var tagline: String { NSLocalizedString(taglineKey, comment: "") }
    }

    static func cards(_ stats: UserStats) -> [Card] {
        [
            Card(labelKey: "stats.completed", taglineKey: "stats.completed_tagline",
                 symbol: "checkmark.circle.fill", tint: .green, value: stats.completed),
            Card(labelKey: "stats.inspired", taglineKey: "stats.inspired_tagline",
                 symbol: "lightbulb.fill", tint: .yellow, value: stats.inspired),
            Card(labelKey: "stats.supported", taglineKey: "stats.supported_tagline",
                 symbol: "heart.fill", tint: .blue, value: stats.supported),
        ]
    }
}

/// Which people open a profile — one rule for every surface that shows a person.
enum MacProfileLink {
    /// A system comment carries no author id; making it a link would give every "marked complete"
    /// line a clickable name that goes nowhere. An AI agent has an id but no profile behind it,
    /// so a link there just 404s. Your own name IS a link, as on iOS.
    static func userId(authorId: String?, isAgent: Bool = false) -> String? {
        guard !isAgent, let authorId, !authorId.isEmpty else { return nil }
        return authorId
    }

    /// Your own profile, reached from the sidebar account row. iOS opens yours from its profile
    /// tab; the Mac has no tab bar, so the bottom-left row is the door. Signed out, there is
    /// nothing to open and the row must not look clickable.
    static func ownUserId(_ currentUser: User?) -> String? {
        userId(authorId: currentUser?.id)
    }
}

extension View {
    /// Makes anything that depicts a person — a name, an avatar, a whole member row — open that
    /// person's profile. A nil id leaves the content exactly as it was: unclickable, no hover
    /// hand. That is the point of routing through `MacProfileLink` instead of testing the id at
    /// each call site — system comments and agents stay plain everywhere at once.
    @ViewBuilder
    func macOpensProfile(_ userId: String?, target: Binding<MacProfileTarget?>) -> some View {
        if let uid = MacProfileLink.userId(authorId: userId) {
            Button { target.wrappedValue = MacProfileTarget(id: uid) } label: { self }
                .buttonStyle(.plain)
                .macPointingHand()
                .help(NSLocalizedString("profile.title", comment: ""))
        } else {
            self
        }
    }
}

/// A user id in a form `sheet(item:)` accepts — String is not Identifiable.
struct MacProfileTarget: Identifiable, Equatable {
    let id: String
}

/// Load failures, worded exactly as iOS words them.
enum MacProfileState {
    static func message(forStatus status: Int) -> String {
        switch status {
        case 404: return NSLocalizedString("profile.error_not_found", comment: "")
        case 401: return NSLocalizedString("profile.error_not_signed_in", comment: "")
        default:  return NSLocalizedString("profile.error_load_failed", comment: "")
        }
    }
}
#endif
