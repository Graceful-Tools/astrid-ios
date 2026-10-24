//  MacFollowsIOSTests.swift
//  AITD-follow-ios — where the Mac and iOS copies of a behaviour disagreed, the Mac now does what
//  iOS does. Jon, 2026-10-03: "on disagreement follow iOS."
//
//  Each divergence was found by mapping both apps onto astrid-core (CONTRACTS D23, D25, D28) or
//  by reading the two copies side by side (search). Each fix moves the rule into ONE shared helper
//  that both apps call, so the two cannot drift apart again.

#if os(macOS)
import XCTest
import SwiftUI
import Combine
@testable import Astrid_Mac

@MainActor
final class MacFollowsIOSTests: XCTestCase {

    private func user(_ id: String, _ name: String) -> User {
        User(id: id, email: "\(id)@astrid.cc", name: name, image: nil)
    }

    // MARK: - D23: a mention is a reference, not plain text

    /// iOS sends `@[Name](id)`, which is what draws the pill and notifies the person. The Mac
    /// inserted `@Name`, so a mention typed on the Mac reached nobody.
    func testD23_aMentionPickedOnTheMacIsAReference() throws {
        let draft = MacCommentDraft()
        draft.text = "thanks @da"
        let dana = ListMember(id: "lm-dana", listId: "l1", userId: "u-dana", role: "MEMBER",
                              user: user("u-dana", "Dana"))
        draft.updateSuggestions(members: [dana])
        let pick = try XCTUnwrap(draft.suggestions.first)

        draft.applySuggestion(pick)

        XCTAssertEqual(draft.text, "thanks @[Dana](u-dana) ")
    }

    // MARK: - Search runs iOS's search — answered by astrid-core since AITD-459

}
#endif
