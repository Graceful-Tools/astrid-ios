//  MacDetailTitleTests.swift
//  Regression guard for Task 4ce4baf9 — "[mac] Task details the task title font should be the
//  same size/weight as in the task rows and should Wrap!!!".
//
//  Two faults in one control, and they were the same fault twice.
//
//  SIZE. The ramp gave the detail its own heading size — 17pt semibold against the row's 14pt
//  medium — on the reasoning that a detail header should sit "clearly above the row title".
//  That reasoning holds for a page whose header names a SECTION. It does not hold here: the
//  detail's title is the same string as the row you clicked to get here, so the jump reads as
//  the text changing rather than as hierarchy, and there is nothing below it in the panel for
//  the heading to be a heading OF.
//
//  WRAP. A plain `TextField` on macOS is one line forever. A long title scrolled sideways
//  inside a 380pt panel, so the detail — the one screen whose whole job is to show everything
//  about a task — was the one place you could not read the task's own name.
//
//  Both are pinned against the shared token rather than against 14, so the two follow each
//  other if the ramp ever moves again.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacDetailTitleTests: XCTestCase {

    private func fieldsSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacTaskFieldsView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - "the same size/weight as in the task rows"

    func testDetailTitleIsTheSameSizeAsARowTitle() {
        XCTAssertEqual(MacTypography.detailTitleSize, MacTypography.rowTitleSize,
                       "The detail's title is the same string as the row it came from")
    }

    /// Same WEIGHT too, which the ask names separately — matching the size while staying
    /// semibold would still read as a different piece of text.
    func testDetailTitleIsTheSameFontAsARowTitle() {
        XCTAssertEqual(MacTypography.detailTitle, MacTypography.rowTitle)
    }

    /// The rest of the ramp is unchanged: the title still stands above body text and the
    /// field labels. Only the gap to the ROW closed.
    func testTheRestOfTheRampStillDescends() {
        XCTAssertGreaterThan(MacTypography.detailTitleSize, MacTypography.detailBodySize)
        XCTAssertGreaterThan(MacTypography.detailBodySize, MacTypography.labelSize)
        XCTAssertGreaterThan(MacTypography.rowTitleSize, MacTypography.rowMetaSize)
    }

    // MARK: - "and should Wrap!!!"

    /// `axis: .vertical` is the whole of it: without it the field is one line forever and a
    /// long title scrolls sideways out of view.
    func testTheTitleFieldWraps() throws {
        let source = try fieldsSource()
        XCTAssertTrue(
            source.contains("""
            TextField(NSLocalizedString("mac.title", comment: ""), text: $title, axis: .vertical)
            """),
            "The detail's title field must wrap — a plain TextField is one line forever")
    }

    /// Wrapping is undone by capping the field at one line, which is an easy thing to add back
    /// while chasing a layout wobble. The lower bound may be 1; the upper may not.
    func testTheTitleFieldIsNotCappedToASingleLine() throws {
        let source = try fieldsSource()
        XCTAssertFalse(source.contains(".lineLimit(1)"),
                       "A one-line cap puts the sideways scroll back")
    }
}
#endif
