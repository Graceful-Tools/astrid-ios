//  MacListMembershipTabTests.swift
//  Guards for AITD-388 — the Mac's list membership catching up with iOS and Web.
//
//  The behaviour itself is covered by ListMembershipRosterTests, which tests the shared rule.
//  What is left is the wiring, and it is exactly the kind that compiles perfectly while being
//  wrong: a pending invitation removed through the MEMBER endpoint, or a second copy of the
//  roster rule that quietly disagrees with iOS.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListMembershipTabTests: XCTestCase {

    // MARK: - One rule, not two

    /// The Mac must ASK the shared rule rather than re-derive "which invitations are pending".
    /// A private copy here is what let the Mac disagree with iOS in the first place.
    func testTheMembershipTabUsesTheSharedRosterRule() throws {
        let source = try Self.source(of: "Astrid Mac/Views/MacListMembershipTab.swift")
        XCTAssertTrue(source.contains("ListMembershipRoster.pendingInvitations"),
                      "AITD-388: pending invitations come from the shared rule")
        XCTAssertTrue(source.contains("ListMembershipRoster.leaveOption"),
                      "AITD-388: who may leave is the shared rule too")
    }

    /// iOS must be asking the same one — the rule was extracted FROM it, and leaving the old
    /// private copy behind would have defeated the point.
    func testIOSAsksTheSameRule() throws {
        let source = try Self.source(of: "Astrid App/Views/Lists/ListMembershipTab.swift")
        XCTAssertTrue(source.contains("ListMembershipRoster.pendingInvitations"),
                      "AITD-388: iOS keeps no private copy of the pending-invitation rule")
    }

    // MARK: - An invitation is not a member

    /// A pending invitation has no userId — there may be no account yet — so it is addressed by
    /// email on its own resource. Cancelling one through `removeMember` is the bug this fixes.
    func testInvitationsAreCancelledThroughTheInvitationPath() throws {
        let source = try Self.source(of: "Astrid Mac/Views/MacListMembershipTab.swift")
        XCTAssertTrue(source.contains("svc.cancelInvitation(listId:"),
                      "AITD-388: cancel goes to the invitation endpoint")
        XCTAssertTrue(source.contains("svc.updateInvitationRole(listId:"),
                      "AITD-388: an invitation's role changes on the invitation, not on a member")
    }

    /// The window must not be a fourth place the permission rule is written out.
    func testTheSettingsWindowAsksListPermissions() throws {
        let source = try Self.source(of: "Astrid Mac/Views/MacListSettingsWindow.swift")
        XCTAssertTrue(source.contains("ListPermissions.canEditSettings"),
                      "AITD-388: the Admin tab is gated by the shared permission rule")
    }

    // MARK: - No hardcoded user-facing copy

    /// Those five privacy labels were hardcoded English, untranslated in twelve languages
    /// (ASTRID.md rule 8). They are string keys now, and must stay that way.
    func testPrivacyLabelsAreLocalized() throws {
        // Comments are stripped first: the file's own history note QUOTES the old hardcoded
        // labels to explain what went wrong, and that sentence is the opposite of the problem.
        let source = try Self.source(of: "Astrid Mac/Views/MacListPrivacy.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for literal in ["\"Private\"", "\"Shared\"", "\"Public\"",
                        "\"Collaborative\"", "\"Copy only\""] {
            XCTAssertFalse(source.contains(literal),
                           "AITD-388: \(literal) is user-facing copy and belongs in Localizable.strings")
        }
        XCTAssertTrue(source.contains("lists.privacy_public_description"),
                      "AITD-388: every privacy option says what it does")
    }

    /// Each option's consequence is spelled out, the way Web does it.
    func testEveryPrivacyOptionHasADescription() {
        for value in ["PRIVATE", "SHARED", "PUBLIC"] {
            XCTAssertFalse(MacListPrivacy.privacyDescription(value).isEmpty)
        }
        XCTAssertNotEqual(MacListPrivacy.publicTypeDescription("collaborative"),
                          MacListPrivacy.publicTypeDescription("copy_only"),
                          "the two public types must not describe themselves identically")
    }

    private static func source(of path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
#endif
