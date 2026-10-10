//  AttachmentPreviewSetTests.swift
//  Regression coverage for task AITD-481 ("iOS cannot preview attachment photo!").
//
//  Tapping a photo in a comment prepared the task-wide gallery and then looked for the tapped
//  photo in it. When the gallery did not hold that photo — it is read from a different cache than
//  the thread on screen — nothing was prepared, nothing was presented, and the tap did nothing.

import XCTest
@testable import Astrid_App

final class AttachmentPreviewSetTests: XCTestCase {

    private func photo(_ id: String) -> SecureFile {
        SecureFile(id: id, name: "photo_1791638387.jpg", size: 177_424, mimeType: "image/jpeg")
    }

    private let noMapping: (String) -> String? = { _ in nil }

    func testAITD481_tappedPhotoIsPreparedWhenTheGalleryDoesNotKnowIt() {
        let tapped = photo("00c6d935")
        let files = AttachmentPreviewSet.files(bubble: [tapped], gallery: [], realId: noMapping)
        XCTAssertEqual(files.map(\.id), ["00c6d935"],
                       "an empty gallery must not turn a tap into nothing")
    }

    func testAITD481_tappedPhotoJoinsAGalleryThatHoldsOtherFiles() {
        let files = AttachmentPreviewSet.files(bubble: [photo("new")],
                                               gallery: [photo("a"), photo("b")],
                                               realId: noMapping)
        XCTAssertEqual(files.map(\.id), ["a", "b", "new"])
    }

    func testAITD481_galleryOrderIsKeptAndNothingIsDoubled() {
        let files = AttachmentPreviewSet.files(bubble: [photo("b")],
                                               gallery: [photo("a"), photo("b"), photo("c")],
                                               realId: noMapping)
        XCTAssertEqual(files.map(\.id), ["a", "b", "c"])
    }

    func testAITD481_aPhotoStillShownUnderItsTempIdIsNotAddedBesideItsUploadedCopy() {
        let files = AttachmentPreviewSet.files(bubble: [photo("temp_1")],
                                               gallery: [photo("real-1")],
                                               realId: { $0 == "temp_1" ? "real-1" : nil })
        XCTAssertEqual(files.map(\.id), ["real-1"])
    }

    func testAITD481_indexFollowsATempIdToItsUploadedCopy() {
        let index = AttachmentPreviewSet.index(of: "temp_1", in: ["a", "real-1"],
                                               realId: { $0 == "temp_1" ? "real-1" : nil })
        XCTAssertEqual(index, 1, "the tapped photo opens, not the first file on the task")
    }

    func testAITD481_indexPrefersTheTappedIdItself() {
        XCTAssertEqual(AttachmentPreviewSet.index(of: "b", in: ["a", "b"], realId: noMapping), 1)
        XCTAssertNil(AttachmentPreviewSet.index(of: "gone", in: ["a", "b"], realId: noMapping))
    }
}
