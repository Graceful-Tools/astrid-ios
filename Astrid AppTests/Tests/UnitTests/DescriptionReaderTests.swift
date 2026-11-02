import XCTest
@testable import Astrid_App

/// AITD-577 — a description gets a full-screen version, so a long one (an agent's plan, a
/// spec) can be read without scrolling a box inside the detail sheet.
///
/// The decisions are pure so they can be pinned without building a view: when the button to
/// open it is offered, which mode the reader opens in, and what closing it saves.
final class DescriptionReaderTests: XCTestCase {

    // MARK: - When the expand button is offered

    func testAITD577_anEditableTaskAlwaysOffersFullScreen_soALongDescriptionCanBeWrittenThere() {
        XCTAssertTrue(DescriptionReader.offersFullScreen(text: "", isReadOnly: false))
        XCTAssertTrue(DescriptionReader.offersFullScreen(text: "## Plan", isReadOnly: false))
    }

    func testAITD577_aReadOnlyTaskOffersItOnlyWhenThereIsSomethingToRead() {
        XCTAssertTrue(DescriptionReader.offersFullScreen(text: "## Plan\n- one", isReadOnly: true))
        XCTAssertFalse(DescriptionReader.offersFullScreen(text: "", isReadOnly: true))
        XCTAssertFalse(DescriptionReader.offersFullScreen(text: "  \n\t ", isReadOnly: true))
    }

    // MARK: - The mode it opens in

    func testAITD577_itOpensForReading_unlessThereIsNothingToReadAndYouCanWrite() {
        XCTAssertEqual(DescriptionReader.initialMode(text: "Some text", isReadOnly: false), .reading)
        XCTAssertEqual(DescriptionReader.initialMode(text: "Some text", isReadOnly: true), .reading)
        XCTAssertEqual(DescriptionReader.initialMode(text: " \n", isReadOnly: false), .editing)
        XCTAssertEqual(DescriptionReader.initialMode(text: "", isReadOnly: true), .reading)
    }

    // MARK: - What closing it saves

    func testAITD577_closingSavesOnlyAChangedDescription() {
        XCTAssertNil(DescriptionReader.textToSave(edited: "same", original: "same"))
        XCTAssertEqual(DescriptionReader.textToSave(edited: "new", original: "old"), "new")
        XCTAssertEqual(DescriptionReader.textToSave(edited: "", original: "old"), "",
                       "clearing the description is a change, and it is saved")
    }
}
