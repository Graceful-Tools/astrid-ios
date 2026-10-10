//  AttachmentPreviewPathTests.swift
//  Regression coverage for task c6468c5c (AITD-312).
//
//  Attachment names come off the wire. `Attachment.name` / `SecureFile.name` are decoded from the
//  API, and the web upload route stores whatever the uploader typed — it validates the
//  extension/MIME pair, not the path. So any member of a shared list can name a file
//  "../../Library/Application Support/store.png" and pass validation.
//
//  Seven places in this app used to join that name straight into a temp path, and one of them
//  (`AttachmentService.getCachedFileURL`) does `removeItem` before `copyItem` — a delete-then-write
//  primitive aimed at an attacker-chosen path inside the app sandbox. Tapping the attachment was
//  enough to fire it.
//
//  These tests pin the sanitiser: whatever the name says, the URL stays inside the directory it
//  was asked for, and it keeps a usable extension so QuickLook can still pick a previewer.

import XCTest
@testable import Astrid_App

final class AttachmentPreviewPathTests: XCTestCase {

    private let tempDir = FileManager.default.temporaryDirectory

    /// Asserts the resolved URL really is inside `directory` — not merely a sibling whose path
    /// happens to share the prefix.
    private func assertContained(_ url: URL, in directory: URL,
                                 _ message: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        var base = directory.standardizedFileURL.path
        if !base.hasSuffix("/") { base += "/" }
        let resolved = url.standardizedFileURL.path
        XCTAssertTrue(resolved.hasPrefix(base),
                      "\(message) — \(resolved) escaped \(base)", file: file, line: line)
    }

    // MARK: - The attack from the task

    func testTraversalNameCannotEscapeTheTemporaryDirectory() {
        let hostile = "../../Library/Application Support/AstridStore.png"
        let url = AttachmentFileName.temporaryURL(in: tempDir, for: hostile)

        assertContained(url, in: tempDir, "traversal name")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       tempDir.standardizedFileURL.path,
                       "the file must land directly in the directory it was asked for")
    }

    func testTraversalNameKeepsItsExtensionSoQuickLookStillWorks() {
        let url = AttachmentFileName.temporaryURL(in: tempDir, for: "../../secrets/holiday.png")
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(url.lastPathComponent, "holiday.png")
    }

    func testAbsolutePathNameIsReducedToItsLeaf() {
        let url = AttachmentFileName.temporaryURL(in: tempDir, for: "/etc/passwd")
        assertContained(url, in: tempDir, "absolute name")
        XCTAssertEqual(url.lastPathComponent, "passwd")
    }

    func testDeepTraversalWithTrailingDotsIsContained() {
        for hostile in ["../..", "..", ".", "../../../../../../../../etc/hosts", "..//../x.pdf"] {
            let url = AttachmentFileName.temporaryURL(in: tempDir, for: hostile)
            assertContained(url, in: tempDir, "name \(hostile)")
        }
    }

    // MARK: - Degenerate names still produce a usable file

    func testEmptyAndWhitespaceNamesFallBackToAUsableLeaf() {
        for raw in ["", "   ", "/", "//", "\n"] {
            let url = AttachmentFileName.temporaryURL(in: tempDir, for: raw)
            assertContained(url, in: tempDir, "name \(raw.debugDescription)")
            XCTAssertFalse(url.lastPathComponent.isEmpty)
            XCTAssertNotEqual(url.standardizedFileURL.path, tempDir.standardizedFileURL.path)
        }
    }

    func testDotSegmentsAloneFallBackRatherThanResolvingToTheDirectory() {
        XCTAssertEqual(AttachmentFileName.sanitized("."), AttachmentFileName.fallbackName)
        XCTAssertEqual(AttachmentFileName.sanitized(".."), AttachmentFileName.fallbackName)
        XCTAssertEqual(AttachmentFileName.sanitized("../.."), AttachmentFileName.fallbackName)
    }

    func testNulByteInNameIsNeutralised() {
        let url = AttachmentFileName.temporaryURL(in: tempDir, for: "report\u{0}.pdf")
        assertContained(url, in: tempDir, "NUL name")
        XCTAssertFalse(url.lastPathComponent.unicodeScalars.contains("\u{0}"))
    }

    func testOverlongNameIsCappedButKeepsItsExtension() {
        let raw = String(repeating: "a", count: 400) + ".jpeg"
        let leaf = AttachmentFileName.sanitized(raw)

        XCTAssertLessThanOrEqual(leaf.utf8.count, 255, "must fit a filesystem name")
        XCTAssertTrue(leaf.hasSuffix(".jpeg"), "QuickLook picks its previewer from the extension")
    }

    // MARK: - Ordinary names are left alone

    func testOrdinaryNamesArePreservedVerbatim() {
        for raw in ["photo.png", "Q3 report (final).pdf", "Ünicode – café 日本.txt", ".hidden.txt"] {
            XCTAssertEqual(AttachmentFileName.sanitized(raw), raw)
        }
    }

    // MARK: - AITD-481: a device's temp directory sits under /private

    /// On a device `temporaryDirectory` is `/private/var/mobile/…`. `standardizedFileURL` drops
    /// that `/private` only from a path that EXISTS, so the directory lost it and the not yet
    /// written file kept it, the containment check failed, and every preview was written as
    /// "attachment" — no extension, so Quick Look drew a blank document instead of the photo.
    /// The simulator's and the Mac's temp directories carry no such prefix, which hid it.
    func testAITD481_ordinaryNameSurvivesInADirectoryUnderPrivate() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/aitd481-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw XCTSkip("cannot create a directory under /private/tmp here: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = AttachmentFileName.temporaryURL(in: directory, for: "photo_1791638387.jpg")
        XCTAssertEqual(url.lastPathComponent, "photo_1791638387.jpg",
                       "the name, and with it the extension Quick Look needs, must survive")
    }

    func testAITD481_previewURLKeepsThePhotoNameUnderPrivate() throws {
        let root = URL(fileURLWithPath: "/private/tmp/aitd481-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw XCTSkip("cannot create a directory under /private/tmp here: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = DownloadedAttachmentCache(directory: root.appendingPathComponent("cache"),
                                              previewRoot: root.appendingPathComponent("preview"))
        let url = cache.previewURL(fileId: "00c6d935", fileName: "photo_1791638387.jpg")
        XCTAssertEqual(url.pathExtension, "jpg")
    }

    func testAITD481_traversalIsStillContainedUnderPrivate() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/aitd481-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw XCTSkip("cannot create a directory under /private/tmp here: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        for hostile in ["../../etc/hosts", "..", ".", ""] {
            let url = AttachmentFileName.temporaryURL(in: directory, for: hostile)
            XCTAssertEqual(url.deletingLastPathComponent().standardized.path, directory.standardized.path,
                           "name \(hostile.debugDescription) must land directly in the directory")
        }
    }

    // MARK: - The guard: no call site may join a raw name onto a temp directory again

    func testNoAttachmentPathJoinsARawNameOntoATemporaryDirectory() throws {
        let root = RepositoryLocator.root

        let audited = [
            "Astrid App/Core/Services/AttachmentService.swift",
            "Astrid App/Views/Components/AttachmentThumbnail.swift",
            "Astrid Mac/Views/MacTaskDetailView.swift",
            "Astrid Mac/Views/MacCommentThread.swift",
        ]

        for relative in audited {
            let path = root.appendingPathComponent(relative)
            let source = try String(contentsOf: path, encoding: .utf8)

            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                guard line.contains("appendingPathComponent(") else { continue }
                // A literal or a UUID is fine; a name that came off the wire is not.
                let joinsAName = line.contains("appendingPathComponent(fileName)")
                    || line.contains("appendingPathComponent(file.name)")
                    || line.contains("appendingPathComponent(name)")
                    || line.contains("appendingPathComponent(a.name)")
                    || line.contains("+ fileName)")
                XCTAssertFalse(joinsAName,
                               "\(relative):\(index + 1) joins an unsanitised attachment name onto a path — "
                               + "route it through AttachmentFileName.temporaryURL(in:for:)")
            }
        }
    }
}
