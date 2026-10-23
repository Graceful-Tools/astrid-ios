import XCTest
@testable import Astrid_App

/// Unit tests for QuickLook attachment editing functionality
/// Tests ensure attachment markup editing and thumbnail refresh work correctly
final class QuickLookPresenterTests: XCTestCase {

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        await MainActor.run {
            // Clear thumbnail cache before each test
            clearThumbnailCache()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            clearThumbnailCache()
        }
    }

    @MainActor
    private func clearThumbnailCache() {
        // ThumbnailCache doesn't have a clear method, but we can verify it works
    }

    // MARK: - ThumbnailCache Tests

    @MainActor
    func testThumbnailCacheSetAndGet() {
        // Given
        let fileId = "test-file-123"
        let testImage = UIImage(systemName: "photo")!

        // When
        ThumbnailCache.shared.set(testImage, for: fileId)
        let retrieved = ThumbnailCache.shared.get(fileId)

        // Then
        XCTAssertNotNil(retrieved, "Should retrieve cached thumbnail")
    }

    @MainActor
    func testThumbnailCacheReturnsNilForUncachedFile() {
        // When
        let retrieved = ThumbnailCache.shared.get("nonexistent-file-id")

        // Then
        XCTAssertNil(retrieved, "Should return nil for uncached file")
    }

    @MainActor
    func testThumbnailCacheHasMethod() {
        // Given
        let fileId = "test-file-456"
        let testImage = UIImage(systemName: "doc")!

        // When - before caching
        let hasBefore = ThumbnailCache.shared.has(fileId)

        // Then
        XCTAssertFalse(hasBefore, "Should not have file before caching")

        // When - after caching
        ThumbnailCache.shared.set(testImage, for: fileId)
        let hasAfter = ThumbnailCache.shared.has(fileId)

        // Then
        XCTAssertTrue(hasAfter, "Should have file after caching")
    }

    @MainActor
    func testThumbnailCacheAlias() {
        // Given
        let tempId = "temp_12345"
        let realId = "real-file-id"
        let testImage = UIImage(systemName: "photo.fill")!

        ThumbnailCache.shared.set(testImage, for: tempId)

        // When
        ThumbnailCache.shared.alias(from: tempId, to: realId)

        // Then
        XCTAssertTrue(ThumbnailCache.shared.has(realId), "Should have aliased file")
        XCTAssertNotNil(ThumbnailCache.shared.get(realId), "Should retrieve aliased thumbnail")
    }

    // MARK: - AstridPreviewItem Tests

    func testAstridPreviewItemProperties() {
        // Given
        let fileId = "file-789"
        let url = URL(fileURLWithPath: "/tmp/test-image.jpg")

        // When
        let item = AstridPreviewItem(fileId: fileId, url: url)

        // Then
        XCTAssertEqual(item.fileId, fileId)
        XCTAssertEqual(item.fileURL, url)
        XCTAssertEqual(item.previewItemURL, url)
        XCTAssertEqual(item.previewItemTitle, "test-image.jpg")
    }

    func testAstridPreviewItemPreviewItemTitle() {
        // Given
        let url = URL(fileURLWithPath: "/path/to/document.pdf")

        // When
        let item = AstridPreviewItem(fileId: "any", url: url)

        // Then
        XCTAssertEqual(item.previewItemTitle, "document.pdf")
    }

    // MARK: - Editable Extensions Tests (AITD-538: these call QuickLookEditing, not a copy of it)

    func testEditableImageExtensions() {
        for ext in ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "pdf", "JPG", "Pdf"] {
            XCTAssertTrue(QuickLookEditing.isEditable(fileId: "abc123", fileExtension: ext), "\(ext) should be editable")
        }
    }

    func testNonEditableExtensions() {
        for ext in ["txt", "doc", "docx", "xls", "mp4", "mov", "zip", "html", ""] {
            XCTAssertFalse(QuickLookEditing.isEditable(fileId: "abc123", fileExtension: ext), "\(ext) should not be editable")
        }
    }

    // MARK: - File ID Validation Tests

    func testTempFileIdsShouldNotBeEditable() {
        for fileId in ["temp_12345", "temp_abc", "temp_"] {
            XCTAssertFalse(QuickLookEditing.canEdit(fileId: fileId), "temp file \(fileId) should not be editable")
            XCTAssertFalse(QuickLookEditing.isEditable(fileId: fileId, fileExtension: "png"))
        }
    }

    func testUnknownFileIdsShouldNotBeEditable() {
        for fileId in ["unknown-12345", "unknown-abc", "unknown-"] {
            XCTAssertFalse(QuickLookEditing.canEdit(fileId: fileId), "unknown file \(fileId) should not be editable")
            XCTAssertFalse(QuickLookEditing.isEditable(fileId: fileId, fileExtension: "png"))
        }
    }

    func testRealFileIdsShouldBeEditable() {
        for fileId in ["abc123", "file-uuid-here", "9c22b653-5eda-4a2a-8c75-a089dcfb5f04"] {
            XCTAssertTrue(QuickLookEditing.canEdit(fileId: fileId), "real file \(fileId) should be editable")
        }
    }

    // MARK: - MIME Type Tests

    func testMimeTypeForImageExtensions() {
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "jpg"), "image/jpeg")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "JPEG"), "image/jpeg")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "png"), "image/png")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "gif"), "image/gif")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "heic"), "image/heic")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "heif"), "image/heic")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "webp"), "image/webp")
    }

    func testMimeTypeForPDF() {
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "pdf"), "application/pdf")
    }

    func testMimeTypeForUnknownExtension() {
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: "xyz"), "application/octet-stream")
        XCTAssertEqual(QuickLookEditing.mimeType(forExtension: ""), "application/octet-stream")
    }

    /// AITD-538: TIFF and BMP were editable but an edited copy uploaded as octet-stream.
    func testEveryEditableExtensionHasItsOwnMimeType() {
        for ext in QuickLookEditing.editableExtensions {
            XCTAssertNotEqual(QuickLookEditing.mimeType(forExtension: ext), "application/octet-stream",
                              "an edited .\(ext) must not upload as octet-stream")
        }
    }

    // MARK: - Notification Tests

    @MainActor
    func testAttachmentUpdatedNotificationContainsFileId() {
        // Given
        let expectation = XCTestExpectation(description: "Notification received")
        let expectedFileId = "test-file-id"
        var receivedFileId: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .attachmentUpdated,
            object: nil,
            queue: .main
        ) { notification in
            receivedFileId = notification.userInfo?["fileId"] as? String
            expectation.fulfill()
        }

        // When
        NotificationCenter.default.post(
            name: .attachmentUpdated,
            object: nil,
            userInfo: ["fileId": expectedFileId]
        )

        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedFileId, expectedFileId)

        NotificationCenter.default.removeObserver(observer)
    }
}
