//  MacCommentPasteTests.swift
//  Regression tests for AITD-306 — "[mac] allow paste image from clipboard (i.e. paste when the
//  clipboard has an image/video/file) into the comment on tasks".
//
//  Before this, the paperclip's NSOpenPanel was the only way a file reached a comment on the Mac.
//  ⌘V with a screenshot on the board did nothing at all: the comment field found no string to
//  type and nothing else was reading the pasteboard.

import XCTest
@testable import Astrid_Mac

final class MacCommentPasteTests: XCTestCase {

    private let png = Data([0x89, 0x50, 0x4E, 0x47])
    private let mov = Data(repeating: 0xAB, count: 32)
    private let noon = Date(timeIntervalSince1970: 1_757_203_200)   // fixed, so names are stable

    // MARK: what the clipboard is offering

    /// A screenshot is raw bytes with no file behind it — the case the task names first.
    func testAPastedScreenshotBecomesOneStageableImageAITD306() {
        let snapshot = MacCommentPaste.Snapshot(imageData: png, imageExtension: "png")
        let candidates = MacCommentPaste.candidates(from: snapshot, now: noon)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.mimeType, "image/png")
        XCTAssertEqual(candidates.first?.data, png)
    }

    /// A file copied in Finder pastes as that file — name and original bytes intact.
    func testACopiedFilePastesWithItsOwnNameAndBytesAITD306() {
        let snapshot = MacCommentPaste.Snapshot(
            files: [MacCommentPaste.file(named: "clip.mov", data: mov)])
        let candidates = MacCommentPaste.candidates(from: snapshot, now: noon)
        XCTAssertEqual(candidates.map(\.name), ["clip.mov"])
        XCTAssertEqual(candidates.first?.data, mov)
    }

    /// Video and documents are attachable too — the task says "image/video/file". The mime comes
    /// from the extension, not from a guess, so the server stores what it actually is.
    func testMimeTypeComesFromTheExtensionAITD306() {
        XCTAssertEqual(MacCommentPaste.file(named: "clip.mov", data: mov).mimeType,
                       "video/quicktime")
        XCTAssertEqual(MacCommentPaste.file(named: "shot.png", data: png).mimeType, "image/png")
        XCTAssertEqual(MacCommentPaste.file(named: "report.pdf", data: png).mimeType,
                       "application/pdf")
        XCTAssertEqual(MacCommentPaste.file(named: "mystery.zzzz", data: png).mimeType,
                       "application/octet-stream",
                       "an unknown extension still attaches rather than being dropped")
    }

    /// Copying a PNG in Finder puts BOTH a file URL and an image rendition on the board. Staging
    /// both would attach the same picture twice; the file is the one that keeps the real name and
    /// the original bytes, so it wins.
    func testAFileBeatsItsOwnClipboardRenditionAITD306() {
        let snapshot = MacCommentPaste.Snapshot(
            files: [MacCommentPaste.file(named: "shot.png", data: png)],
            imageData: png, imageExtension: "png")
        let candidates = MacCommentPaste.candidates(from: snapshot, now: noon)
        XCTAssertEqual(candidates.map(\.name), ["shot.png"], "the rendition is a duplicate here")
    }

    /// A screenshot arrives nameless. Two pastes a second apart must not collide in the staged
    /// strip, so the name carries the moment it was pasted.
    func testPastedImagesAreNamedByWhenTheyWerePastedAITD306() {
        let first = MacCommentPaste.candidates(
            from: .init(imageData: png, imageExtension: "png"), now: noon)
        let second = MacCommentPaste.candidates(
            from: .init(imageData: png, imageExtension: "png"), now: noon.addingTimeInterval(61))
        XCTAssertNotEqual(first.first?.name, second.first?.name)
        XCTAssertTrue(first.first?.name.hasSuffix(".png") == true,
                      "got \(first.first?.name ?? "nil")")
    }

    // MARK: ⌘V must still type

    /// Text on the clipboard is the comment field's business. Intercepting it would break the
    /// most common paste in the app to serve the rarest.
    func testATextOnlyClipboardIsNotInterceptedAITD306() {
        XCTAssertTrue(MacCommentPaste.candidates(from: .init(), now: noon).isEmpty)
        XCTAssertFalse(MacCommentPaste.handlesPaste(hasAttachableContent: false,
                                                    commentFieldFocused: true,
                                                    otherEditorFocused: false))
    }

    /// Pasting into the title or the notes stays a text paste — those are other editors.
    func testPasteIntoAnotherFieldIsNotStolenAITD306() {
        XCTAssertFalse(MacCommentPaste.handlesPaste(hasAttachableContent: true,
                                                    commentFieldFocused: false,
                                                    otherEditorFocused: true))
    }

    /// With the comment field focused, or with nothing being typed into at all, an image on the
    /// board attaches — which is the whole request.
    func testAnImagePastesIntoTheCommentAITD306() {
        XCTAssertTrue(MacCommentPaste.handlesPaste(hasAttachableContent: true,
                                                   commentFieldFocused: true,
                                                   otherEditorFocused: true))
        XCTAssertTrue(MacCommentPaste.handlesPaste(hasAttachableContent: true,
                                                   commentFieldFocused: false,
                                                   otherEditorFocused: false))
    }

    // MARK: staging goes through the shared queue

    /// Paste feeds the SAME queue the paperclip does — cap, duplicate rule and all.
    func testPastedFilesLandInTheSharedStagingQueueAITD306() {
        var registered: [String] = []
        let staged = MacCommentPaste.staged(
            [MacCommentPaste.file(named: "a.png", data: png),
             MacCommentPaste.file(named: "b.png", data: png)],
            onto: [],
            register: { candidate in registered.append(candidate.name); return "id-\(candidate.name)" })
        XCTAssertEqual(staged.map(\.fileName), ["a.png", "b.png"])
        XCTAssertEqual(registered, ["a.png", "b.png"])
        XCTAssertEqual(staged.first?.fileSize, png.count)
        XCTAssertNotNil(staged.first?.imageData, "an image carries its bytes for the thumbnail")
    }

    /// A non-image carries no preview bytes — the strip draws it as a document chip.
    func testANonImageStagesWithoutPreviewBytesAITD306() {
        let staged = MacCommentPaste.staged([MacCommentPaste.file(named: "clip.mov", data: mov)],
                                            onto: [], register: { _ in "id" })
        XCTAssertNil(staged.first?.imageData)
    }

    /// The cap is asked BEFORE the upload starts. Registering a file the cap will drop sends
    /// bytes for something that can never post.
    func testACapExceedingPasteStartsNoUploadItWillDropAITD306() {
        let many = (0..<(AttachmentQueue.maxAttachments + 3)).map {
            MacCommentPaste.file(named: "f\($0).png", data: png)
        }
        var registered = 0
        let staged = MacCommentPaste.staged(many, onto: [], register: { _ in
            registered += 1
            return "id-\(registered)"
        })
        XCTAssertEqual(staged.count, AttachmentQueue.maxAttachments)
        XCTAssertEqual(registered, AttachmentQueue.maxAttachments,
                       "an upload was started for a file the cap discarded")
    }

    /// Paste appends to what the paperclip already staged rather than replacing it.
    func testPasteAppendsToAlreadyStagedFilesAITD306() {
        let existing = [AttachedFileInfo(fileId: "picked", fileName: "picked.png", fileSize: 4,
                                         mimeType: "image/png", imageData: png)]
        let staged = MacCommentPaste.staged([MacCommentPaste.file(named: "pasted.png", data: png)],
                                            onto: existing, register: { _ in "pasted" })
        XCTAssertEqual(staged.map(\.fileName), ["picked.png", "pasted.png"])
    }
}
