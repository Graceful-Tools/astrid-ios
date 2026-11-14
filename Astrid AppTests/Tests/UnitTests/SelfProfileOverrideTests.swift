//  SelfProfileOverrideTests.swift
//  AITD-669: a new profile photo has to show everywhere you appear — the profile card, the
//  assignee pickers, task rows — as soon as it is saved, not after the next full sync.
//
//  Avatars draw from the copy of the user embedded in each cached list (`owner`,
//  `listMembers[].user`) and task (`assignee`, `creator`, comment authors), and
//  `User.cachedImageURL` prefers that embedded image. Saving the photo updated only
//  `AuthManager.currentUser`, so every one of those copies kept the old picture.

import XCTest
@testable import Astrid_App

@MainActor
final class SelfProfileOverrideTests: XCTestCase {
    private let me = "user-me"
    private let other = "user-other"
    private let newPhoto = "https://example.com/new.jpg"

    override func tearDown() async throws {
        SelfProfileOverride.shared.clear()
    }

    private var profile: SelfProfile { SelfProfile(userId: me, name: "New Name", image: newPhoto) }

    func testAITD669_listsShowTheSavedPhotoOnOwnerAndMemberCopies() {
        let stale = TestHelpers.createTestUser(id: me, name: "Old Name", image: "https://example.com/old.jpg")
        let someoneElse = TestHelpers.createTestUser(id: other, name: "Other", image: "https://example.com/other.jpg")
        var list = TestHelpers.createTestList(id: "l1", ownerId: me, owner: stale)
        list.listMembers = [
            ListMember(id: "m1", listId: "l1", userId: me, role: "owner", user: stale),
            ListMember(id: "m2", listId: "l1", userId: other, role: "member", user: someoneElse),
        ]

        let patched = SelfProfileOverride.apply(profile, to: [list])

        XCTAssertEqual(patched[0].owner?.image, newPhoto)
        XCTAssertEqual(patched[0].owner?.name, "New Name")
        XCTAssertEqual(patched[0].listMembers?[0].user?.image, newPhoto)
        XCTAssertEqual(patched[0].listMembers?[1].user, someoneElse, "another member is left alone")
    }

    func testAITD669_tasksShowTheSavedPhotoOnAssigneeCreatorAndCommentAuthor() {
        let stale = TestHelpers.createTestUser(id: me, image: "https://example.com/old.jpg")
        let someoneElse = TestHelpers.createTestUser(id: other, image: "https://example.com/other.jpg")
        var task = TestHelpers.createTestTask(id: "t1", assigneeId: me, assignee: stale,
                                              creatorId: other, creator: someoneElse)
        task.comments = [TestHelpers.createTestComment(authorId: me, author: stale, taskId: "t1")]

        let patched = SelfProfileOverride.apply(profile, to: [task])

        XCTAssertEqual(patched[0].assignee?.image, newPhoto)
        XCTAssertEqual(patched[0].creator, someoneElse)
        XCTAssertEqual(patched[0].comments?.first?.author?.image, newPhoto)
    }

    func testAITD669_nothingToPatchLeavesTheValuesEqual() {
        let list = TestHelpers.createTestList(id: "l1", owner: TestHelpers.createTestUser(id: other))
        XCTAssertEqual(SelfProfileOverride.apply(profile, to: [list]), [list])
    }

    func testAITD669_savingANewPhotoThroughAuthManagerSetsTheOverride() throws {
        let suite = "SelfProfileOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let auth = AuthManager(apiClient: AstridAPIClient(session: StubURLProtocol.session()),
                               keychainService: KeychainService(service: "cc.astrid.tests.\(UUID().uuidString)"),
                               defaults: defaults,
                               cookieStorage: HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: suite),
                               journalFileURL: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("self-profile-\(UUID().uuidString).json"),
                               isConnected: { false })
        let edited = TestHelpers.createTestUser(id: me, name: "New Name", image: newPhoto)

        auth.updateCurrentUser(edited)
        defer { UserImageCache.shared.setImageURL(nil, for: me) }

        XCTAssertEqual(SelfProfileOverride.shared.profile, profile)
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: me), newPhoto)
    }
}

@MainActor
final class SelfProfileCardTests: XCTestCase {
    func testAITD669_ownProfileCardShowsTheSavedPhoto() {
        let loaded = UserProfileData(id: "me", name: "Old", email: "me@example.com", image: "old.jpg",
                                     createdAt: Date(), isAIAgent: nil, aiAgentType: nil)
        let saved = TestHelpers.createTestUser(id: "me", name: "New", image: "new.jpg")
        let someoneElse = TestHelpers.createTestUser(id: "other", name: "X", image: "x.jpg")

        XCTAssertEqual(loaded.showing(saved).image, "new.jpg")
        XCTAssertEqual(loaded.showing(saved).name, "New")
        XCTAssertEqual(loaded.showing(someoneElse).image, "old.jpg")
        XCTAssertEqual(loaded.showing(nil).image, "old.jpg")
    }
}
