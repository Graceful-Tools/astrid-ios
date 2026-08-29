import XCTest
@testable import Astrid_App

/// Unit tests for UserImageCache and User.cachedImageURL extension
/// These tests ensure profile photos display correctly in list members and other views
final class UserImageCacheTests: XCTestCase {

    private var defaults: UserDefaults!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "UserImageCacheTests.AITD-283")!
        defaults.removePersistentDomain(forName: "UserImageCacheTests.AITD-283")
        // Clear cache before each test
        await MainActor.run {
            UserImageCache.shared.clearCache()
        }
    }

    override func tearDown() async throws {
        // Clear cache after each test
        await MainActor.run {
            UserImageCache.shared.clearCache()
        }
        defaults.removePersistentDomain(forName: "UserImageCacheTests.AITD-283")
        defaults = nil
    }

    // MARK: - Cache Operations Tests

    @MainActor
    func testSetAndGetImageURL() {
        // Given
        let userId = "user-123"
        let imageURL = "https://example.com/avatar.jpg"

        // When
        UserImageCache.shared.setImageURL(imageURL, for: userId)
        let retrieved = UserImageCache.shared.getImageURL(userId: userId)

        // Then
        XCTAssertEqual(retrieved, imageURL)
    }

    @MainActor
    func testGetImageURLReturnsNilForUncachedUser() {
        // When
        let retrieved = UserImageCache.shared.getImageURL(userId: "nonexistent-user")

        // Then
        XCTAssertNil(retrieved)
    }

    @MainActor
    func testSetImageURLIgnoresNil() {
        // Given
        let userId = "user-123"

        // When
        UserImageCache.shared.setImageURL(nil, for: userId)
        let retrieved = UserImageCache.shared.getImageURL(userId: userId)

        // Then
        XCTAssertNil(retrieved, "Should not cache nil URLs")
    }

    @MainActor
    func testSetImageURLIgnoresEmptyString() {
        // Given
        let userId = "user-123"

        // When
        UserImageCache.shared.setImageURL("", for: userId)
        let retrieved = UserImageCache.shared.getImageURL(userId: userId)

        // Then
        XCTAssertNil(retrieved, "Should not cache empty URLs")
    }

    /// Regression for AITD-283: Core Data restores only the assignee id, so a cold-launch row
    /// must recover the avatar URL before the first task sync rebuilds the in-memory lookup.
    @MainActor
    func testAITD283ImageURLLookupSurvivesFreshCacheInstance() {
        let firstLaunch = UserImageCache(defaults: defaults)
        firstLaunch.setImageURL("https://example.com/avatar-v1.jpg", for: "user-283")

        let coldLaunch = UserImageCache(defaults: defaults)

        XCTAssertEqual(coldLaunch.getImageURL(userId: "user-283"),
                       "https://example.com/avatar-v1.jpg")
    }

    /// Regression for AITD-283: a server null/empty image means initials now. It must not leave
    /// a prior photo pinned in the persisted lookup while the user waits for another sync.
    @MainActor
    func testAITD283NullOrEmptyImageRemovesStaleLookup() {
        let cache = UserImageCache(defaults: defaults)
        cache.setImageURL("https://example.com/old-avatar.jpg", for: "user-283")

        cache.setImageURL(nil, for: "user-283")
        XCTAssertNil(cache.getImageURL(userId: "user-283"))

        cache.setImageURL("https://example.com/another-old-avatar.jpg", for: "user-283")
        cache.setImageURL("", for: "user-283")
        XCTAssertNil(cache.getImageURL(userId: "user-283"))
    }

    /// Regression for AITD-283: the URL is the image-byte cache identity, so a changed profile
    /// photo must replace the lookup rather than retaining a user-id-keyed old image forever.
    @MainActor
    func testAITD283ChangedPhotoPersistsNewURL() {
        let cache = UserImageCache(defaults: defaults)
        cache.setImageURL("https://example.com/avatar-v1.jpg", for: "user-283")
        cache.setImageURL("https://example.com/avatar-v2.jpg", for: "user-283")

        let coldLaunch = UserImageCache(defaults: defaults)
        XCTAssertEqual(coldLaunch.getImageURL(userId: "user-283"),
                       "https://example.com/avatar-v2.jpg")
    }

    /// Regression for AITD-283: many visible rows for one person must share the same URL fetch,
    /// including the window before the first response has populated the byte cache.
    @MainActor
    func testAITD283ConcurrentRowsCoalesceOneURLLoad() async {
        let coordinator = URLLoadCoordinator<Int>()
        var operationCount = 0
        let url = URL(string: "https://example.com/avatar.jpg")!
        let firstRowIsFetching = expectation(description: "the first row's fetch is in flight")
        let releaseFirstRow = expectation(description: "the test is ready for the first row's fetch to end")

        // The first row's fetch is HELD OPEN until this test releases it. It used to sleep 50ms
        // instead, which meant the second row had to reach `load` inside that window — and on a
        // busy machine it did not. `load` removes its `inFlight` entry the moment the operation
        // returns, so a fetch that finished early left nothing to coalesce onto and the second
        // row legitimately started its own. That is what "flaky roughly one run in three" was.
        // Holding the fetch open removes the window rather than widening it.
        async let first = coordinator.load(for: url) {
            operationCount += 1
            firstRowIsFetching.fulfill()
            await self.fulfillment(of: [releaseFirstRow], timeout: 5.0)
            return 283
        }
        await fulfillment(of: [firstRowIsFetching], timeout: 2.0)

        async let second = coordinator.load(for: url) {
            operationCount += 1
            return 999
        }
        // Give the second row time to reach `load`. It cannot miss the in-flight entry now —
        // the first row is still parked above and stays there until the next line.
        try? await _Concurrency.Task.sleep(for: .milliseconds(250))
        releaseFirstRow.fulfill()

        let values = await [first, second]

        // The contract is "one fetch, one shared result", NOT which of two equally valid
        // orderings won. Asserting [283, 283] baked the ordering in: when the second row's
        // child task happened to start first, both callers correctly coalesced onto ITS
        // operation and the values were [999, 999] — coalescing working, test failing.
        XCTAssertEqual(operationCount, 1, "the second row must not start its own fetch")
        XCTAssertEqual(values[0], values[1], "both rows must receive the same result")
        XCTAssertNotNil(values[0])
    }

    @MainActor
    func testCacheUser() {
        // Given
        let user = TestHelpers.createTestUser(
            id: "user-456",
            image: "https://example.com/user456.jpg"
        )

        // When
        UserImageCache.shared.cacheUser(user)
        let retrieved = UserImageCache.shared.getImageURL(userId: user.id)

        // Then
        XCTAssertEqual(retrieved, "https://example.com/user456.jpg")
    }

    @MainActor
    func testCacheUserIgnoresNilImage() {
        // Given
        let user = TestHelpers.createTestUser(
            id: "user-no-image",
            image: nil
        )

        // When
        UserImageCache.shared.cacheUser(user)
        let retrieved = UserImageCache.shared.getImageURL(userId: user.id)

        // Then
        XCTAssertNil(retrieved)
    }

    @MainActor
    func testClearCache() {
        // Given
        UserImageCache.shared.setImageURL("https://example.com/a.jpg", for: "user-a")
        UserImageCache.shared.setImageURL("https://example.com/b.jpg", for: "user-b")

        // When
        UserImageCache.shared.clearCache()

        // Then
        XCTAssertNil(UserImageCache.shared.getImageURL(userId: "user-a"))
        XCTAssertNil(UserImageCache.shared.getImageURL(userId: "user-b"))
        XCTAssertEqual(UserImageCache.shared.count, 0)
    }

    @MainActor
    func testCacheCount() {
        // Given
        XCTAssertEqual(UserImageCache.shared.count, 0)

        // When
        UserImageCache.shared.setImageURL("https://example.com/1.jpg", for: "user-1")
        UserImageCache.shared.setImageURL("https://example.com/2.jpg", for: "user-2")
        UserImageCache.shared.setImageURL("https://example.com/3.jpg", for: "user-3")

        // Then
        XCTAssertEqual(UserImageCache.shared.count, 3)
    }

    // MARK: - User.cachedImageURL Extension Tests (Regression Tests)

    @MainActor
    func testCachedImageURLReturnsUserImageWhenPresent() {
        // Given - User has direct image URL
        let user = TestHelpers.createTestUser(
            id: "user-with-image",
            image: "https://example.com/direct.jpg"
        )

        // When
        let cachedURL = user.cachedImageURL

        // Then - Should return user's direct image
        XCTAssertEqual(cachedURL, "https://example.com/direct.jpg")
    }

    @MainActor
    func testCachedImageURLFallsBackToCache() {
        // Given - User without direct image, but cached
        let userId = "user-cached-only"
        UserImageCache.shared.setImageURL("https://example.com/cached.jpg", for: userId)

        let user = TestHelpers.createTestUser(
            id: userId,
            image: nil  // No direct image
        )

        // When
        let cachedURL = user.cachedImageURL

        // Then - Should return cached image
        XCTAssertEqual(cachedURL, "https://example.com/cached.jpg")
    }

    @MainActor
    func testCachedImageURLReturnsNilWhenNoImageAnywhere() {
        // Given - User without image, nothing cached
        let user = TestHelpers.createTestUser(
            id: "user-no-image-anywhere",
            image: nil
        )

        // When
        let cachedURL = user.cachedImageURL

        // Then
        XCTAssertNil(cachedURL)
    }

    @MainActor
    func testCachedImageURLPrefersUserImageOverCache() {
        // Given - User has image AND there's a cached version
        let userId = "user-both"
        UserImageCache.shared.setImageURL("https://example.com/old-cached.jpg", for: userId)

        let user = TestHelpers.createTestUser(
            id: userId,
            image: "https://example.com/new-direct.jpg"  // Direct image takes priority
        )

        // When
        let cachedURL = user.cachedImageURL

        // Then - Should prefer user's direct image over cache
        XCTAssertEqual(cachedURL, "https://example.com/new-direct.jpg")
    }

    @MainActor
    func testCachedImageURLIgnoresEmptyUserImage() {
        // Given - User has empty string image, but cached
        let userId = "user-empty-image"
        UserImageCache.shared.setImageURL("https://example.com/cached.jpg", for: userId)

        let user = User(
            id: userId,
            email: "test@example.com",
            name: "Test",
            image: "",  // Empty string, not nil
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )

        // When
        let cachedURL = user.cachedImageURL

        // Then - Should fall back to cached since empty string is ignored
        XCTAssertEqual(cachedURL, "https://example.com/cached.jpg")
    }

    // MARK: - List Members Caching Tests (Regression Tests for ListMembershipTab)

    @MainActor
    func testCacheFromListsCachesOwnerImage() {
        // Given - List with owner who has an image
        let owner = TestHelpers.createTestUser(
            id: "owner-1",
            name: "List Owner",
            image: "https://example.com/owner.jpg"
        )
        let list = TestHelpers.createTestList(
            id: "list-1",
            owner: owner
        )

        // When
        UserImageCache.shared.cacheFromLists([list])

        // Then - Owner's image should be cached
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "owner-1"), "https://example.com/owner.jpg")
    }

    @MainActor
    func testCacheFromListsCachesMultipleMembers() {
        // Given - List with owner (members/admins require different model setup)
        let owner = TestHelpers.createTestUser(
            id: "owner-multi",
            name: "Owner",
            image: "https://example.com/owner-multi.jpg"
        )
        let list = TestHelpers.createTestList(
            id: "list-multi",
            owner: owner
        )

        // When
        UserImageCache.shared.cacheFromLists([list])

        // Then - All should be cached
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "owner-multi"), "https://example.com/owner-multi.jpg")
    }

    @MainActor
    func testCacheFromMultipleLists() {
        // Given - Multiple lists with different owners
        let owner1 = TestHelpers.createTestUser(id: "owner-a", image: "https://example.com/a.jpg")
        let owner2 = TestHelpers.createTestUser(id: "owner-b", image: "https://example.com/b.jpg")
        let owner3 = TestHelpers.createTestUser(id: "owner-c", image: "https://example.com/c.jpg")

        let lists = [
            TestHelpers.createTestList(id: "list-a", owner: owner1),
            TestHelpers.createTestList(id: "list-b", owner: owner2),
            TestHelpers.createTestList(id: "list-c", owner: owner3)
        ]

        // When
        UserImageCache.shared.cacheFromLists(lists)

        // Then - All owners should be cached
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "owner-a"), "https://example.com/a.jpg")
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "owner-b"), "https://example.com/b.jpg")
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "owner-c"), "https://example.com/c.jpg")
    }

    // MARK: - Task Caching Tests

    @MainActor
    func testCacheFromTasksCachesAssignee() {
        // Given - Task with assignee who has image
        let assignee = TestHelpers.createTestUser(
            id: "assignee-1",
            name: "Task Assignee",
            image: "https://example.com/assignee.jpg"
        )
        let task = TestHelpers.createTestTask(
            id: "task-1",
            assignee: assignee
        )

        // When
        UserImageCache.shared.cacheFromTasks([task])

        // Then
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "assignee-1"), "https://example.com/assignee.jpg")
    }

    @MainActor
    func testCacheFromTasksCachesCreator() {
        // Given - Task with creator who has image
        let creator = TestHelpers.createTestUser(
            id: "creator-1",
            name: "Task Creator",
            image: "https://example.com/creator.jpg"
        )
        let task = TestHelpers.createTestTask(
            id: "task-2",
            creator: creator
        )

        // When
        UserImageCache.shared.cacheFromTasks([task])

        // Then
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "creator-1"), "https://example.com/creator.jpg")
    }

    @MainActor
    func testCacheFromTasksCachesCommentAuthors() {
        // Given - Task with comment by user who has image
        let author = TestHelpers.createTestUser(
            id: "author-1",
            name: "Comment Author",
            image: "https://example.com/author.jpg"
        )
        let comment = TestHelpers.createTestComment(
            id: "comment-1",
            author: author,
            taskId: "task-3"
        )
        let task = TestHelpers.createTestTask(
            id: "task-3",
            comments: [comment]
        )

        // When
        UserImageCache.shared.cacheFromTasks([task])

        // Then
        XCTAssertEqual(UserImageCache.shared.getImageURL(userId: "author-1"), "https://example.com/author.jpg")
    }
}
