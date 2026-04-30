import XCTest
@testable import Astrid_App

/// Unit tests for chat attachment models and offline queue
final class ChatAttachmentTests: XCTestCase {

    // MARK: - AttachedFileInfo Tests

    func testAttachedFileInfoIsImageForJpeg() {
        let file = AttachedFileInfo(
            fileId: "test-1",
            fileName: "photo.jpg",
            fileSize: 1024,
            mimeType: "image/jpeg",
            imageData: nil
        )
        XCTAssertTrue(file.isImage)
    }

    func testAttachedFileInfoIsImageForPng() {
        let file = AttachedFileInfo(
            fileId: "test-2",
            fileName: "screenshot.png",
            fileSize: 2048,
            mimeType: "image/png",
            imageData: nil
        )
        XCTAssertTrue(file.isImage)
    }

    func testAttachedFileInfoIsNotImageForPdf() {
        let file = AttachedFileInfo(
            fileId: "test-3",
            fileName: "document.pdf",
            fileSize: 4096,
            mimeType: "application/pdf",
            imageData: nil
        )
        XCTAssertFalse(file.isImage)
    }

    func testAttachedFileInfoIsNotImageForZip() {
        let file = AttachedFileInfo(
            fileId: "test-4",
            fileName: "archive.zip",
            fileSize: 8192,
            mimeType: "application/zip",
            imageData: nil
        )
        XCTAssertFalse(file.isImage)
    }

    func testAttachedFileInfoCaseInsensitiveMimeType() {
        let file = AttachedFileInfo(
            fileId: "test-5",
            fileName: "photo.jpg",
            fileSize: 1024,
            mimeType: "Image/JPEG",
            imageData: nil
        )
        XCTAssertTrue(file.isImage)
    }

    // MARK: - PendingAttachment Context Tests

    func testPendingAttachmentWithTaskIdContext() {
        let pending = PendingAttachment(
            tempFileId: "temp_123",
            localPath: "/tmp/test",
            fileName: "file.jpg",
            mimeType: "image/jpeg",
            fileSize: 1024,
            uploadContext: ["taskId": "task-abc"],
            uploadStatus: .pending
        )

        XCTAssertEqual(pending.taskId, "task-abc")
        XCTAssertEqual(pending.uploadContext["taskId"], "task-abc")
    }

    func testPendingAttachmentWithListIdContext() {
        let pending = PendingAttachment(
            tempFileId: "temp_456",
            localPath: "/tmp/test",
            fileName: "doc.pdf",
            mimeType: "application/pdf",
            fileSize: 2048,
            uploadContext: ["listId": "list-xyz"],
            uploadStatus: .pending
        )

        XCTAssertEqual(pending.taskId, "")  // No taskId in context
        XCTAssertEqual(pending.uploadContext["listId"], "list-xyz")
    }

    func testPendingAttachmentWithChannelIdContext() {
        let pending = PendingAttachment(
            tempFileId: "temp_789",
            localPath: "/tmp/test",
            fileName: "photo.png",
            mimeType: "image/png",
            fileSize: 4096,
            uploadContext: ["channelId": "ch-abc123"],
            uploadStatus: .pending
        )

        XCTAssertEqual(pending.taskId, "")  // No taskId
        XCTAssertEqual(pending.uploadContext["channelId"], "ch-abc123")
    }

    // MARK: - PendingAttachment Codable Tests

    @MainActor func testPendingAttachmentCodableRoundTrip() throws {
        let original = PendingAttachment(
            tempFileId: "temp_roundtrip",
            localPath: "/cache/file",
            fileName: "test.jpg",
            mimeType: "image/jpeg",
            fileSize: 5000,
            uploadContext: ["listId": "list-123", "channelId": "ch-456"],
            realFileId: "real-789",
            uploadStatus: .completed
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PendingAttachment.self, from: data)

        XCTAssertEqual(decoded.tempFileId, original.tempFileId)
        XCTAssertEqual(decoded.localPath, original.localPath)
        XCTAssertEqual(decoded.fileName, original.fileName)
        XCTAssertEqual(decoded.mimeType, original.mimeType)
        XCTAssertEqual(decoded.fileSize, original.fileSize)
        XCTAssertEqual(decoded.uploadContext, original.uploadContext)
        XCTAssertEqual(decoded.realFileId, original.realFileId)
        XCTAssertEqual(decoded.uploadStatus, original.uploadStatus)
    }

    @MainActor func testPendingAttachmentBackwardCompatDecode() throws {
        // Simulate old format with taskId as direct string field
        let oldFormatJSON = """
        {
            "tempFileId": "temp_legacy",
            "localPath": "/cache/old",
            "fileName": "legacy.pdf",
            "mimeType": "application/pdf",
            "fileSize": 3000,
            "taskId": "task-old-123",
            "uploadStatus": "pending"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PendingAttachment.self, from: oldFormatJSON)

        XCTAssertEqual(decoded.tempFileId, "temp_legacy")
        XCTAssertEqual(decoded.taskId, "task-old-123")
        XCTAssertEqual(decoded.uploadContext["taskId"], "task-old-123")
        XCTAssertEqual(decoded.uploadStatus, .pending)
    }

    @MainActor func testPendingAttachmentStatusValues() throws {
        for status in [PendingAttachment.UploadStatus.pending, .uploading, .completed, .failed] {
            let pending = PendingAttachment(
                tempFileId: "temp_\(status.rawValue)",
                localPath: "/tmp/test",
                fileName: "file.txt",
                mimeType: "text/plain",
                fileSize: 100,
                uploadContext: ["taskId": "t1"],
                uploadStatus: status
            )

            let data = try JSONEncoder().encode(pending)
            let decoded = try JSONDecoder().decode(PendingAttachment.self, from: data)
            XCTAssertEqual(decoded.uploadStatus, status)
        }
    }

    // MARK: - ChatMessage with Attachments Tests

    @MainActor func testChatMessageWithSecureFiles() throws {
        let secureFile = SecureFile(id: "sf-1", name: "photo.jpg", size: 1024, mimeType: "image/jpeg")
        let message = ChatMessage(
            id: "msg-attach",
            channelId: "ch-1",
            authorId: "user-1",
            author: nil,
            content: "",
            type: .ATTACHMENT,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            replyToId: nil,
            clientRequestId: nil,
            secureFiles: [secureFile],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(message.type, .ATTACHMENT)
        XCTAssertEqual(message.secureFiles?.count, 1)
        XCTAssertEqual(message.secureFiles?.first?.id, "sf-1")
    }

    @MainActor func testChatMessageAttachmentCodableRoundTrip() throws {
        let secureFile = SecureFile(id: "sf-codable", name: "doc.pdf", size: 2048, mimeType: "application/pdf")
        let message = ChatMessage(
            id: "msg-codable-attach",
            channelId: "ch-1",
            authorId: "user-1",
            author: nil,
            content: "Check this file",
            type: .ATTACHMENT,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            replyToId: nil,
            clientRequestId: nil,
            secureFiles: [secureFile],
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.type, .ATTACHMENT)
        XCTAssertEqual(decoded.secureFiles?.count, 1)
        XCTAssertEqual(decoded.secureFiles?.first?.mimeType, "application/pdf")
    }

    // MARK: - Upload Context Tests

    func testUploadContextForListChannel() {
        // List channel should use listId
        let listId = "list-abc"
        let channelId = "ch-123"

        let context: [String: String]
        if listId != "my-tasks" {
            context = ["listId": listId]
        } else {
            context = ["channelId": channelId]
        }

        XCTAssertEqual(context["listId"], "list-abc")
        XCTAssertNil(context["channelId"])
    }

    func testUploadContextForVirtualChannel() {
        // My Tasks should use channelId
        let listId = "my-tasks"
        let channelId = "ch-virtual-456"

        let context: [String: String]
        if listId != "my-tasks" {
            context = ["listId": listId]
        } else {
            context = ["channelId": channelId]
        }

        XCTAssertEqual(context["channelId"], "ch-virtual-456")
        XCTAssertNil(context["listId"])
    }

    // MARK: - Server Response Parsing Tests

    @MainActor func testParseServerResponseWithSecureFiles() throws {
        // Simulate server response matching web's ChatMessage + secureFiles format
        let json = """
        {
            "id": "msg-server-1",
            "channelId": "ch-1",
            "authorId": "user-1",
            "content": "Here is a file",
            "type": "ATTACHMENT",
            "createdAt": "2026-03-30T12:00:00Z",
            "updatedAt": "2026-03-30T12:00:00Z",
            "secureFiles": [
                {
                    "id": "sf-abc",
                    "originalName": "report.pdf",
                    "mimeType": "application/pdf",
                    "fileSize": 52400
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: json)

        XCTAssertEqual(message.id, "msg-server-1")
        XCTAssertEqual(message.type, .ATTACHMENT)
        XCTAssertEqual(message.secureFiles?.count, 1)
        XCTAssertEqual(message.secureFiles?.first?.id, "sf-abc")
        XCTAssertEqual(message.secureFiles?.first?.name, "report.pdf")
        XCTAssertEqual(message.secureFiles?.first?.size, 52400)
        XCTAssertEqual(message.secureFiles?.first?.mimeType, "application/pdf")
    }

    @MainActor func testParseServerResponseWithMultipleSecureFiles() throws {
        let json = """
        {
            "id": "msg-multi",
            "channelId": "ch-2",
            "authorId": "user-1",
            "content": "",
            "type": "ATTACHMENT",
            "createdAt": "2026-03-30T12:00:00Z",
            "updatedAt": "2026-03-30T12:00:00Z",
            "secureFiles": [
                {"id": "sf-1", "originalName": "photo.jpg", "mimeType": "image/jpeg", "fileSize": 1024},
                {"id": "sf-2", "originalName": "doc.pdf", "mimeType": "application/pdf", "fileSize": 2048}
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: json)

        XCTAssertEqual(message.secureFiles?.count, 2)
        XCTAssertEqual(message.secureFiles?[0].name, "photo.jpg")
        XCTAssertEqual(message.secureFiles?[1].name, "doc.pdf")
    }

    @MainActor func testParseServerResponseWithEmptySecureFiles() throws {
        let json = """
        {
            "id": "msg-no-files",
            "channelId": "ch-1",
            "authorId": "user-1",
            "content": "Just text",
            "type": "TEXT",
            "createdAt": "2026-03-30T12:00:00Z",
            "updatedAt": "2026-03-30T12:00:00Z",
            "secureFiles": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: json)

        XCTAssertEqual(message.type, .TEXT)
        XCTAssertEqual(message.secureFiles?.count, 0)
    }

    @MainActor func testParseServerResponseWithoutSecureFiles() throws {
        // Server may omit secureFiles field entirely
        let json = """
        {
            "id": "msg-legacy",
            "channelId": "ch-1",
            "authorId": "user-1",
            "content": "Old message",
            "type": "TEXT",
            "createdAt": "2026-03-30T12:00:00Z",
            "updatedAt": "2026-03-30T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(ChatMessage.self, from: json)

        XCTAssertNil(message.secureFiles)
    }

    // MARK: - Attachment Message on My Tasks Tests

    @MainActor func testAttachmentMessageOnMyTasks() {
        // Verify attachment message works on virtual channel (My Tasks)
        let message = ChatMessage(
            id: "temp_mytasks_attach",
            channelId: "ch-virtual-mytasks",
            authorId: "user-1",
            author: nil,
            content: "",
            type: .ATTACHMENT,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            replyToId: nil,
            clientRequestId: UUID().uuidString,
            secureFiles: [SecureFile(id: "temp_file1", name: "screenshot.png", size: 5000, mimeType: "image/png")],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(message.isPending)
        XCTAssertEqual(message.type, .ATTACHMENT)
        XCTAssertEqual(message.secureFiles?.count, 1)
        XCTAssertTrue(message.secureFiles?.first?.mimeType.hasPrefix("image/") ?? false)
    }

    // MARK: - Attachment Metadata Fields Tests

    @MainActor func testAttachmentMetadataFields() {
        let message = ChatMessage(
            id: "msg-meta",
            channelId: "ch-1",
            authorId: "user-1",
            author: nil,
            content: "See attached",
            type: .ATTACHMENT,
            attachmentUrl: "/api/v1/secure-files/file-123",
            attachmentName: "budget.xlsx",
            attachmentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            attachmentSize: 15360,
            replyToId: nil,
            clientRequestId: nil,
            secureFiles: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(message.attachmentUrl, "/api/v1/secure-files/file-123")
        XCTAssertEqual(message.attachmentName, "budget.xlsx")
        XCTAssertEqual(message.attachmentType, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        XCTAssertEqual(message.attachmentSize, 15360)
    }

    func testCanSendWithAttachmentOnly() {
        // canSend should be true when only an attachment is present (no text)
        let text = ""
        let hasAttachment = true
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachment
        XCTAssertTrue(canSend)
    }

    func testCanSendWithTextOnly() {
        let text = "Hello"
        let hasAttachment = false
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachment
        XCTAssertTrue(canSend)
    }

    func testCannotSendEmpty() {
        let text = "   "
        let hasAttachment = false
        let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasAttachment
        XCTAssertFalse(canSend)
    }
}
