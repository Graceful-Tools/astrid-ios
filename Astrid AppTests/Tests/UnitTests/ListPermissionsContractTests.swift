//  ListPermissionsContractTests.swift
//  The missing test for ASTRID.md §8 row 3 — task da171566 (AITD-316).
//
//  The contract: `listMembers` is the source of truth for who is on a list and what they may do.
//  The legacy `admins[]` / `members[]` arrays are NOT populated by the endpoints iOS consumes, and
//  must not be branched on. Web's `getUserRoleInList` is the canonical rule this mirrors.
//
//  That row was the only one in the §8 table with an empty Test column, which is exactly why the
//  legacy branches kept coming back: while those arrays are empty the branches are dead, so they
//  read as harmless and survive review. They stop being harmless the moment anything populates
//  them — a server change, a cached list from an older build, or an optimistic local edit — and
//  then iOS shows a roster or a mention list that disagrees with web.
//
//  Every test here therefore builds the pathological list the contract is about: legacy arrays
//  FULL, `listMembers` EMPTY. Anything that consults the legacy arrays answers differently.

import XCTest
@testable import Astrid_App

final class ListPermissionsContractTests: XCTestCase {

    private func user(_ id: String) -> User {
        User(id: id, email: "\(id)@example.com", name: id, image: nil)
    }

    /// A list whose legacy arrays are populated and whose `listMembers` is empty.
    private func legacyOnlyList(ownerId: String = "owner-1") -> TaskList {
        var list = TaskList(id: "list-1", name: "Shared")
        list.ownerId = ownerId
        list.owner = user(ownerId)
        list.admins = [user("legacy-admin")]
        list.members = [user("legacy-member")]
        list.listMembers = []
        return list
    }

    // MARK: - role(for:) ignores the legacy arrays

    func testSomeoneOnlyInTheLegacyAdminsArrayHasNoRole() {
        let list = legacyOnlyList()
        XCTAssertNil(list.role(for: "legacy-admin"),
                     "admins[] is not a roster — consulting it would disagree with web")
    }

    func testSomeoneOnlyInTheLegacyMembersArrayHasNoRole() {
        XCTAssertNil(legacyOnlyList().role(for: "legacy-member"))
    }

    func testTheOwnerIsStillTheOwner() {
        // ownerId / owner are legitimate — only admins[] and members[] are the dead arrays.
        XCTAssertEqual(legacyOnlyList().role(for: "owner-1"), .owner)
    }

    func testAListMemberEntryIsWhatGrantsARole() {
        var list = legacyOnlyList()
        list.listMembers = [
            ListMember(id: "lm1", listId: "list-1", userId: "real-admin", role: "admin", user: user("real-admin")),
            ListMember(id: "lm2", listId: "list-1", userId: "real-member", role: "member", user: user("real-member")),
        ]

        XCTAssertEqual(list.role(for: "real-admin"), .admin)
        XCTAssertEqual(list.role(for: "real-member"), .member)
        XCTAssertNil(list.role(for: "legacy-admin"), "the legacy arrays stay ignored either way")
    }

    // MARK: - Everything built on role(for:) inherits the rule

    func testMembershipIgnoresTheLegacyArrays() {
        let list = legacyOnlyList()
        XCTAssertFalse(list.isMember(userId: "legacy-admin"))
        XCTAssertFalse(list.isMember(userId: "legacy-member"))
        XCTAssertTrue(list.isMember(userId: "owner-1"))
    }

    func testSettingsPermissionIgnoresTheLegacyArrays() {
        let list = legacyOnlyList()
        XCTAssertFalse(ListPermissions.canEditSettings(list, userId: "legacy-admin"),
                       "a legacy-admins entry must not unlock list settings")
        XCTAssertTrue(ListPermissions.canEditSettings(list, userId: "owner-1"))
    }

    func testDeletePermissionIgnoresTheLegacyArrays() {
        let list = legacyOnlyList()
        XCTAssertFalse(ListPermissions.canDelete(list, userId: "legacy-admin"))
        XCTAssertTrue(ListPermissions.canDelete(list, userId: "owner-1"))
    }

    func testAPublicListStillGrantsViewerRatherThanTheLegacyRole() {
        var list = legacyOnlyList()
        list.privacy = .PUBLIC
        XCTAssertEqual(list.role(for: "legacy-admin"), .viewer,
                       "a stranger and a legacy-array entry must be treated identically")
    }

    // MARK: - The mention map

    @MainActor
    func testTheMentionMapIgnoresTheLegacyArrays() {
        // `buildMentionableUsers` reads whatever ListService holds, so seed it with the
        // pathological list and check who comes back.
        let restore = ListService.shared.lists
        defer { ListService.shared.lists = restore }
        ListService.shared.lists = [legacyOnlyList()]

        let mentionable = buildMentionableUsers(listId: "list-1").map(\.id)

        XCTAssertFalse(mentionable.contains("legacy-admin"),
                       "mentioning someone from admins[] offers a name web would not")
        XCTAssertFalse(mentionable.contains("legacy-member"))
        XCTAssertTrue(mentionable.contains("owner-1"), "the owner is still mentionable")
    }

    // MARK: - The guard: no view may branch on the legacy arrays again

    func testNoSurfaceBranchesOnTheLegacyArrays() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        let audited = [
            "Astrid App/Views/Tasks/CommentSectionViewEnhanced.swift",
            "Astrid App/Views/Lists/ListMembershipTab.swift",
            "Astrid App/Views/Lists/ListSettingsModal.swift",
            "Astrid Mac/Views/MacListMembersView.swift",
        ]

        for relative in audited {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)

            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = strippingCommentsAndLiterals(line)
                for legacy in [".admins", ".members"] {
                    XCTAssertFalse(readsProperty(legacy, in: code),
                                   "\(relative):\(index + 1) reads the legacy \(legacy) array — "
                                   + "listMembers is the source of truth (ASTRID.md §8 row 3)")
                }
            }
        }
    }

    /// Drop `//` comments and `"…"` literals, so a localization key like `lists.members` and a
    /// comment explaining the contract do not read as a use of the array.
    private func strippingCommentsAndLiterals(_ line: String) -> String {
        var out = ""
        var inString = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            let next = line.index(after: index)

            if !inString, char == "/", next < line.endIndex, line[next] == "/" { break }
            if char == "\"" { inString.toggle(); index = next; continue }
            if !inString { out.append(char) }
            index = next
        }
        return out
    }

    /// True when `property` is actually accessed — `.membersByList` and `.adminsFoo` are other
    /// names that merely start the same way.
    private func readsProperty(_ property: String, in code: String) -> Bool {
        var searchRange = code.startIndex..<code.endIndex

        while let found = code.range(of: property, range: searchRange) {
            if found.upperBound == code.endIndex {
                return true
            }
            let following = code[found.upperBound]
            if !following.isLetter && !following.isNumber && following != "_" {
                return true
            }
            searchRange = found.upperBound..<code.endIndex
        }
        return false
    }
}
