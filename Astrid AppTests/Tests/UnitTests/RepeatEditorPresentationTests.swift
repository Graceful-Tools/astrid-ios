//  RepeatEditorPresentationTests.swift
//  Regression tests for Task 42013da7 — "Custom repeat picker should open full screen. Still
//  opening in right column only."
//
//  The PRESET list was moved into a sheet when the trigger became a compact chip, but the CUSTOM
//  pattern editor was left rendering inline — and the sheet's condition explicitly excluded it
//  (`compact && isEditing && !showingCustomEditor`). So the custom editor kept laying itself out
//  inside a chip-width column: "Repeat from comple-tion date" wrapping mid-word.
//
//  Both editors are full-screen work; neither belongs in a chip.

import XCTest
@testable import Astrid_App

final class RepeatEditorPresentationTests: XCTestCase {

    /// THE BUG: a compact trigger showing the CUSTOM editor must present it as a sheet.
    func testCustomEditorIsASheetWhenCompact() {
        XCTAssertEqual(RepeatEditorPresentation.of(compact: true, isEditing: false, showingCustom: true),
                       .sheet)
    }

    /// The presets already worked this way; it stays that way.
    func testPresetEditorIsASheetWhenCompact() {
        XCTAssertEqual(RepeatEditorPresentation.of(compact: true, isEditing: true, showingCustom: false),
                       .sheet)
    }

    /// Full-width callers (the board card editor, anywhere showing the label) keep the inline
    /// editor they have always had — the compact chip is what makes a sheet necessary.
    func testFullWidthCallersStayInline() {
        XCTAssertEqual(RepeatEditorPresentation.of(compact: false, isEditing: true, showingCustom: false),
                       .inline)
        XCTAssertEqual(RepeatEditorPresentation.of(compact: false, isEditing: false, showingCustom: true),
                       .inline)
    }

    /// Editing nothing shows the trigger, compact or not.
    func testNotEditingShowsTheTrigger() {
        XCTAssertEqual(RepeatEditorPresentation.of(compact: true, isEditing: false, showingCustom: false),
                       .trigger)
        XCTAssertEqual(RepeatEditorPresentation.of(compact: false, isEditing: false, showingCustom: false),
                       .trigger)
    }

    /// The custom editor outranks the preset list — opening custom FROM the presets sets both
    /// flags for a moment, and showing the preset list over the custom editor would be wrong.
    func testCustomWinsWhenBothAreSet() {
        XCTAssertEqual(RepeatEditorPresentation.of(compact: true, isEditing: true, showingCustom: true),
                       .sheet)
        XCTAssertTrue(RepeatEditorPresentation.showsCustomEditor(isEditing: true, showingCustom: true))
        XCTAssertFalse(RepeatEditorPresentation.showsCustomEditor(isEditing: true, showingCustom: false))
    }
}
