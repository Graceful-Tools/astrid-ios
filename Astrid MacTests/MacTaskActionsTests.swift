//  MacTaskActionsTests.swift
//  Regression for task ea0527ef — "[mac] enable task share, copy, etc all like what currently
//  works in the iOS app. reuse code if possible."
//
//  The share LINK comes from the same shared service iOS uses (RemoteResourceService.createShortcode)
//  and copying goes through TaskService.copyTask, so there is no Mac-only business logic to test.
//  What is Mac-specific — and worth pinning — is the clipboard payload and when the share sheet
//  can be offered.

import XCTest
@testable import Astrid_Mac

final class MacTaskActionsTests: XCTestCase {

    func testClipboardTextIsJustTheTitleWithoutALink() {
        XCTAssertEqual(MacTaskActions.clipboardText(title: "Buy milk", shareURL: nil), "Buy milk")
    }

    func testClipboardTextIncludesTheShareLinkWhenThereIsOne() {
        let url = URL(string: "https://astrid.cc/s/abc123")!
        XCTAssertEqual(MacTaskActions.clipboardText(title: "Buy milk", shareURL: url),
                       "Buy milk\nhttps://astrid.cc/s/abc123")
    }

    /// A task with an empty title must still copy something rather than a stray newline.
    func testEmptyTitleWithALinkStillCopiesTheLink() {
        let url = URL(string: "https://astrid.cc/s/abc123")!
        XCTAssertTrue(MacTaskActions.clipboardText(title: "", shareURL: url)
            .contains("https://astrid.cc/s/abc123"))
    }

    /// The share sheet needs a link — offering it before one exists would present an empty picker.
    func testShareSheetOnlyOnceALinkExists() {
        XCTAssertFalse(MacTaskActions.canPresentShareSheet(shareURL: nil))
        XCTAssertTrue(MacTaskActions.canPresentShareSheet(shareURL: URL(string: "https://astrid.cc/s/x")!))
    }
}
