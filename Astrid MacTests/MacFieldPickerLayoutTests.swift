//  MacFieldPickerLayoutTests.swift
//  Regression guard for Task d4f663a3 — the date / time / repeat popovers.
//
//  Two complaints, one cause: the popovers were laid out against numbers picked by hand
//  rather than against the controls they actually contain.
//
//  • The date popover was a hard-coded 300pt wide. AppKit draws the graphical DatePicker at
//    139x148; at 1.5x that is 208.5, floating in a 276pt content box with ~34pt of dead space
//    down each side. The popover has to be sized BY the calendar, not guessed at.
//  • The choice rows aligned their titles leading, so a column of short labels ("Today",
//    "Tomorrow") hugged the left edge of a box far wider than any of them.
//
//  `calendarNaturalEstimate` is measured here against the real AppKit control rather than
//  trusted, because it is the size the popover builds itself from on the first layout pass —
//  a wrong estimate is a visible width jump as the real measurement lands.

import XCTest
import SwiftUI
import AppKit
@testable import Astrid_Mac

final class MacFieldPickerLayoutTests: XCTestCase {

    // MARK: - The popover is sized by the calendar

    /// What AppKit actually draws for `.datePickerStyle(.graphical)`, measured, not assumed.
    @MainActor private func measuredCalendarSize() -> CGSize {
        let calendar = DatePicker("", selection: .constant(Date()), displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .labelsHidden()
            .fixedSize()
        return NSHostingView(rootView: AnyView(calendar)).fittingSize
    }

    /// The first-pass estimate must match the real control. It is what the popover sizes
    /// itself from before the measurement arrives, so being 30% off is a visible jump.
    @MainActor
    func testTheCalendarEstimateMatchesWhatAppKitDraws() {
        let real = measuredCalendarSize()
        XCTAssertEqual(MacFieldPicker.calendarNaturalEstimate.width, real.width, accuracy: 1,
                       "calendarNaturalEstimate is the popover's first-pass width; AppKit draws \(real)")
        XCTAssertEqual(MacFieldPicker.calendarNaturalEstimate.height, real.height, accuracy: 1,
                       "calendarNaturalEstimate is the popover's first-pass height; AppKit draws \(real)")
    }

    /// The calendar FILLS the popover: content box == scaled calendar, no dead space beside it.
    @MainActor
    func testThePopoverIsExactlyAsWideAsTheCalendarItWraps() {
        let scaled = measuredCalendarSize().width * MacFieldPicker.calendarScale
        let popover = MacFieldPicker.popoverWidth(forCalendarWidth: scaled)
        XCTAssertEqual(popover - MacFieldPicker.padding * 2, scaled, accuracy: 0.5,
                       "The calendar should span the popover's content box, not float inside it")
    }

    /// A calendar narrower than the choice rows must not squeeze them: the rows set the floor.
    func testAVeryNarrowCalendarDoesNotShrinkThePopoverBelowTheRowWidth() {
        XCTAssertEqual(MacFieldPicker.popoverWidth(forCalendarWidth: 20),
                       MacFieldPicker.narrowPopoverWidth,
                       "The other field popovers' width is the floor — rows still have to be readable")
    }

    /// Sizing to the calendar is the point; a literal width puts the dead space back.
    func testTheDatePopoverDoesNotHardCodeItsWidth() {
        let source = try? String(contentsOf: macSource("Views/MacDueDatePicker.swift"), encoding: .utf8)
        XCTAssertNotNil(source)
        XCTAssertFalse(source?.contains(".frame(width: 300)") ?? true,
                       "MacDueDatePicker must size to its calendar via MacFieldPicker.popoverWidth(forCalendarWidth:)")
    }

    // MARK: - The choice rows are centred

    /// Every popover row is centre-aligned, so a column of short labels reads as a column
    /// rather than as text shoved against the left wall.
    func testPickerRowsCentreTheirTitle() throws {
        let source = try String(contentsOf: macSource("Views/MacFieldPickerChrome.swift"), encoding: .utf8)
        let row = try XCTUnwrap(source.components(separatedBy: "struct MacPickerRow").last)
        XCTAssertFalse(row.contains("alignment: .leading"),
                       "MacPickerRow titles are centred (task d4f663a3)")
        XCTAssertTrue(row.contains("alignment: .center"),
                      "MacPickerRow should say plainly that its title is centred")
    }

    /// The popovers themselves stack their content centred, so the rows are centred *in* them.
    func testTheFieldPopoversStackTheirContentCentred() throws {
        for file in ["Views/MacDueDatePicker.swift", "Views/MacRepeatPicker.swift"] {
            let source = try String(contentsOf: macSource(file), encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                XCTAssertFalse(code.contains("VStack(alignment: .leading"),
                               "\(file):\(index + 1) stacks its popover content leading; it should be centred")
            }
        }
    }

    // MARK: -

    private func macSource(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac")
            .appendingPathComponent(relative)
    }
}
