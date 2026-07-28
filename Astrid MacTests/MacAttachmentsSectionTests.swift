//  MacAttachmentsSectionTests.swift
//  Regression tests for Task cb2702a9 — "[mac] hide the attachment section unless attachments
//  have been added". Attachments arrive through comments, so an unconditional section meant an
//  empty header and an Add-file button on nearly every task.

import XCTest
@testable import Astrid_Mac

final class MacAttachmentsSectionTests: XCTestCase {

    func testHiddenWhenThereIsNothingAttached() {
        XCTAssertFalse(MacAttachmentsSection.isVisible(attachments: 0, secureFiles: 0))
    }

    func testVisibleForAUrlBackedAttachment() {
        XCTAssertTrue(MacAttachmentsSection.isVisible(attachments: 1, secureFiles: 0))
    }

    /// Secure files come in through comments and have no direct URL — counting only the first list
    /// would hide a section that has content in it.
    func testVisibleForASecureFileAlone() {
        XCTAssertTrue(MacAttachmentsSection.isVisible(attachments: 0, secureFiles: 1))
    }

    /// Attaching must stay possible on a task with nothing attached yet, or hiding the section
    /// removes the feature — so the menu offers it exactly when the section is hidden.
    func testAddFileIsOfferedInTheMenuWhenTheSectionIsHidden() {
        XCTAssertTrue(MacAttachmentsSection.offersAddInMenu(attachments: 0, secureFiles: 0))
        XCTAssertFalse(MacAttachmentsSection.offersAddInMenu(attachments: 2, secureFiles: 0),
                       "The visible section already has its own Add button")
    }
}
