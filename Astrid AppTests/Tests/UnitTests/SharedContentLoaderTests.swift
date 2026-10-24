//  SharedContentLoaderTests.swift
//  What the share sheet hands the Share Extension, and the task draft it becomes (AITD-542). Real
//  NSItemProviders, so the type-picking order is the one the extension meets.

import XCTest
import UniformTypeIdentifiers
@testable import Astrid_App

@MainActor
final class SharedContentLoaderTests: XCTestCase {
    private var container: URL!
    private var loader: SharedContentLoader!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedContentLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        loader = SharedContentLoader(manager: ShareDataManager(containerURL: container),
                                     now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    private func item(_ provider: NSItemProvider, title: String? = nil) -> NSExtensionItem {
        let item = NSExtensionItem()
        item.attachments = [provider]
        item.attributedContentText = title.map { NSAttributedString(string: $0) }
        return item
    }

    // MARK: - URLs

    func testASharedWebPageIsTitledByThePageWithTheAddressInTheNotes_AITD542() async throws {
        let url = URL(string: "https://www.example.com/article?id=7")!
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
        let draft = try await loader.draft(from: [item(provider, title: "  A Good Article  ")])
        XCTAssertEqual(draft, SharedTaskDraft(title: "A Good Article", notes: url.absoluteString, file: nil))
    }

    func testAWebPageWithNoTitleIsNamedForItsSite_AITD542() async throws {
        let url = URL(string: "https://www.example.com/x")!
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
        let draft = try await loader.draft(from: [item(provider)])
        XCTAssertEqual(draft?.title, "example.com")
        XCTAssertEqual(draft?.notes, url.absoluteString)
        XCTAssertEqual(SharedTaskDraft.webPage(url, pageTitle: url.absoluteString).title, "example.com",
                       "a 'title' that is only the address is no title")
        XCTAssertEqual(SharedTaskDraft.webPage(URL(string: "mailto:a@b.c")!, pageTitle: nil).title, "mailto:a@b.c")
    }

    // MARK: - Text

    func testSharedTextIsTitledByItsFirstLineWithTheRestAsNotes_AITD542() async throws {
        let provider = NSItemProvider(item: "  Buy milk\nsemi-skimmed\n\ntwo litres \n" as NSString,
                                      typeIdentifier: UTType.plainText.identifier)
        let draft = try await loader.draft(from: [item(provider)])
        XCTAssertEqual(draft, SharedTaskDraft(title: "Buy milk", notes: "semi-skimmed\n\ntwo litres", file: nil))
    }

    func testTextThatIsOnlyALinkIsAWebPage_AITD542() {
        XCTAssertEqual(SharedTaskDraft.text(" https://example.com/a \n"),
                       SharedTaskDraft(title: "example.com", notes: "https://example.com/a", file: nil))
        XCTAssertEqual(SharedTaskDraft.text("see https://example.com").title, "see https://example.com",
                       "a sentence with a link in it is still text")
        XCTAssertEqual(SharedTaskDraft.text("ftp://example.com").notes, "", "only web links become pages")
    }

    // MARK: - Files and images

    func testASharedImageBecomesAPendingAttachmentInTheAppGroup_AITD542() async throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let provider = NSItemProvider(item: bytes as NSData, typeIdentifier: UTType.jpeg.identifier)
        let draft = try await loader.draft(from: [item(provider)])
        let file = try XCTUnwrap(draft?.file)

        XCTAssertEqual(file.fileName, "image_1700000000.jpg")
        XCTAssertEqual(file.mimeType, "image/jpeg")
        XCTAssertEqual(file.fileSize, 4)
        XCTAssertTrue(file.fileURL.path.hasPrefix(container.path), "the copy lives where the app can read it")
        XCTAssertEqual(try Data(contentsOf: file.fileURL), bytes)
        XCTAssertEqual(draft?.title, "image 1700000000")
    }

    func testASharedFileKeepsItsNameAndIsTitledFromIt_AITD542() async throws {
        let source = container.appendingPathComponent("quarterly_report-final.pdf")
        try Data(repeating: 1, count: 10).write(to: source)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))
        let draft = try await loader.draft(from: [item(provider)])
        let file = try XCTUnwrap(draft?.file)

        XCTAssertEqual(file.fileName, "quarterly_report-final.pdf")
        XCTAssertEqual(file.mimeType, "application/pdf")
        XCTAssertEqual(file.fileSize, 10)
        XCTAssertNotEqual(file.fileURL, source, "copied into the App Group, not referenced in place")
        XCTAssertEqual(draft?.title, "quarterly report final")
        XCTAssertEqual(draft?.notes, "")
    }

    func testRawDataOfNoKnownKindIsStillKeptAsAFile_AITD542() async throws {
        let provider = NSItemProvider(item: Data([1, 2]) as NSData, typeIdentifier: UTType.data.identifier)
        let draft = try await loader.draft(from: [item(provider)])
        XCTAssertEqual(draft?.file?.fileName, "file")
        XCTAssertEqual(draft?.file?.mimeType, "application/octet-stream")
    }

    /// A file URL is also a URL, and text is also data: the most specific kind wins.
    func testTheMostSpecificRepresentationIsTheOneLoaded_AITD542() {
        let file = NSItemProvider(item: URL(fileURLWithPath: "/tmp/a.pdf") as NSURL, typeIdentifier: UTType.fileURL.identifier)
        XCTAssertEqual(SharedContentLoader.Kind.of(file), .fileURL)
        let web = NSItemProvider(item: URL(string: "https://a.b")! as NSURL, typeIdentifier: UTType.url.identifier)
        XCTAssertEqual(SharedContentLoader.Kind.of(web), .webURL)
        let text = NSItemProvider(item: "hi" as NSString, typeIdentifier: UTType.plainText.identifier)
        XCTAssertEqual(SharedContentLoader.Kind.of(text), .text)
        let png = NSItemProvider(item: Data() as NSData, typeIdentifier: UTType.png.identifier)
        XCTAssertEqual(SharedContentLoader.Kind.of(png), .image)
        XCTAssertNil(SharedContentLoader.Kind.of(NSItemProvider()))
    }

    func testNothingToShareIsNoDraft_AITD542() async throws {
        let nothing = try await loader.draft(from: [])
        XCTAssertNil(nothing)
        let empty = try await loader.draft(from: [NSExtensionItem()])
        XCTAssertNil(empty)
    }

    /// The App Group the extension cannot open fails the share where the person can see it.
    func testAFileWithNoAppGroupFailsInsteadOfVanishing_AITD542() async {
        let lost = SharedContentLoader(manager: ShareDataManager(containerURL: nil))
        let provider = NSItemProvider(item: Data([1]) as NSData, typeIdentifier: UTType.jpeg.identifier)
        do {
            _ = try await lost.draft(from: [item(provider)])
            XCTFail("a share with nowhere to go must throw")
        } catch {
            XCTAssertEqual(error as? ShareDataError, .appGroupNotConfigured)
        }
    }

    // MARK: - Confirming the draft

    func testTheConfirmedDraftIsTheQueuedShare_AITD542() {
        let file = SharedFileData(fileURL: URL(fileURLWithPath: "/tmp/x.png"), fileName: "x.png",
                                  mimeType: "image/png", fileSize: 3)
        let data = SharedTaskDraft.taskData(title: "  Title \n", notes: "  ", priority: 2, file: file)
        XCTAssertEqual(data?.title, "Title")
        XCTAssertNil(data?.description, "blank notes are no notes")
        XCTAssertEqual(data?.priority, 2)
        XCTAssertNil(data?.listId, "the app files it in the default list")
        XCTAssertEqual(data?.fileName, "x.png")
        XCTAssertEqual(data?.mimeType, "image/png")
        XCTAssertEqual(data?.fileSize, 3)

        XCTAssertNil(SharedTaskDraft.taskData(title: " \n", notes: "x", priority: 0, file: nil), "no title, no save")
        XCTAssertNil(SharedTaskDraft.taskData(title: "T", notes: "", priority: 0, file: nil)?.priority,
                     "priority none is sent as no priority")
    }

    func testTheAttachmentRowDescribesTheFile_AITD542() {
        func file(_ mime: String, size: Int64 = 2_500_000) -> SharedFileData {
            SharedFileData(fileURL: URL(fileURLWithPath: "/tmp/f"), fileName: "f", mimeType: mime, fileSize: size)
        }
        XCTAssertEqual(file("image/jpeg").iconName, "photo")
        XCTAssertEqual(file("video/mp4").iconName, "video")
        XCTAssertEqual(file("application/pdf").iconName, "doc.fill")
        XCTAssertEqual(file("text/plain").iconName, "doc.text")
        XCTAssertEqual(file("application/zip").iconName, "archivebox")
        XCTAssertEqual(file("application/octet-stream").iconName, "doc")
        XCTAssertFalse(file("image/jpeg").formattedSize.isEmpty)
    }
}
