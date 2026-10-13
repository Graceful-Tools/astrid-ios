//  ListColorsTests.swift
//  AITD-500 — "Add color picker to list setting for users in no list image test".
//
//  The hide_list_images test (AITD-468) draws a list's colour where its image was, and dropped
//  the image row from list settings — which left the colour as the one thing that identifies a
//  list and nothing on iOS that could change it. Web has had "List Color" in list settings since
//  the day after (astrid-web components/list-admin/ListColorSection.tsx).
//
//  What must not drift from web: the palette (a swatch web cannot tick reads as "custom" there),
//  and the stored form. The server accepts `#rrggbb` only, because the value is painted into
//  inline styles, so anything else has to be stopped here rather than refused there.

import XCTest
@testable import Astrid_App

final class ListColorsTests: XCTestCase {

    // MARK: - The palette (mirrors LIST_COLOR_PALETTE in astrid-web lib/brand/colors.ts)

    func testAITD500_ThePaletteIsWebsInWebsOrder() {
        XCTAssertEqual(ListColors.palette, [
            "#ef4444", // red
            "#f97316", // orange
            "#eab308", // yellow
            "#22c55e", // green
            "#06b6d4", // cyan
            "#3b82f6", // blue
            "#8b5cf6", // violet
            "#ec4899", // pink
        ])
    }

    func testAITD500_EverySwatchIsStorable() {
        for swatch in ListColors.palette {
            XCTAssertTrue(ListColors.isListColor(swatch), "\(swatch) would be refused by the server")
        }
    }

    // MARK: - Only #rrggbb is ever stored (mirrors isListColor)

    func testAITD500_OnlySixDigitHexIsAListColor() {
        XCTAssertTrue(ListColors.isListColor("#3b82f6"))
        XCTAssertTrue(ListColors.isListColor("#3B82F6"))

        XCTAssertFalse(ListColors.isListColor("3b82f6"), "no #")
        XCTAssertFalse(ListColors.isListColor("#3b8"), "shorthand")
        XCTAssertFalse(ListColors.isListColor("#3b82f6ff"), "alpha")
        XCTAssertFalse(ListColors.isListColor("#3b82fg"), "not hex")
        XCTAssertFalse(ListColors.isListColor("blue"))
        XCTAssertFalse(ListColors.isListColor(""))
    }

    // MARK: - What a pick stores

    func testAITD500_PickingADifferentColorStoresIt() {
        XCTAssertEqual(ListColors.change(from: "#3b82f6", to: "#ef4444"), "#ef4444")
    }

    /// The picker hands back whatever case it likes; the palette comparison on both platforms is
    /// against lowercase, so that is what is stored.
    func testAITD500_AStoredColorIsLowercase() {
        XCTAssertEqual(ListColors.change(from: "#3b82f6", to: "#EF4444"), "#ef4444")
    }

    func testAITD500_PickingTheCurrentColorStoresNothing() {
        XCTAssertNil(ListColors.change(from: "#3b82f6", to: "#3b82f6"))
        XCTAssertNil(ListColors.change(from: "#3B82F6", to: "#3b82f6"), "case is not a change")
    }

    func testAITD500_AnUnstorableColorStoresNothing() {
        XCTAssertNil(ListColors.change(from: "#3b82f6", to: "red"))
        XCTAssertNil(ListColors.change(from: "#3b82f6", to: "#ef4444ff"))
    }

    // MARK: - Which swatch is ticked

    func testAITD500_APaletteColorIsNotCustomWhateverItsCase() {
        XCTAssertFalse(ListColors.isCustom("#3b82f6"))
        XCTAssertFalse(ListColors.isCustom("#3B82F6"))
    }

    /// The 16 placeholder pastels are not in the palette, so a list coloured by its old image
    /// shows as custom rather than with no swatch selected at all.
    func testAITD500_AnythingElseIsCustom() {
        XCTAssertTrue(ListColors.isCustom("#e6e6fa"))
    }

    // MARK: - The custom picker's colour as a stored value

    func testAITD500_ComponentsBecomeSixDigitHex() {
        XCTAssertEqual(ListColors.hex(red: 1, green: 0, blue: 0), "#ff0000")
        XCTAssertEqual(ListColors.hex(red: 0, green: 0.5, blue: 1), "#0080ff")
    }

    /// A wide-gamut pick resolves to sRGB components outside 0…1. Unclamped that formats as a
    /// seven-character or negative value, which the server refuses and the swatch reverts.
    func testAITD500_OutOfGamutComponentsAreClamped() {
        let hex = ListColors.hex(red: 1.09, green: -0.23, blue: 0.5)
        XCTAssertEqual(hex, "#ff0080")
        XCTAssertTrue(ListColors.isListColor(hex))
    }

    // MARK: - The change reaches the request

    /// The settings sheet sends the diff `ListSettingsPayload` builds, and it compared every
    /// field except this one: a colour picked in the admin tab would have updated the local list
    /// and then been dropped before the request, as "Recently completed" once was (545812e6).
    func testAITD500_AColorChangeIsSentAndNothingElse() {
        var original = TaskList(id: "list-1", name: "Groceries")
        original.color = "#3b82f6"
        var updated = original
        updated.color = "#ef4444"

        let updates = ListSettingsPayload.updates(original: original, updated: updated)
        XCTAssertEqual(Set(updates.keys), ["color"], "a colour change must not race an unrelated field")
        XCTAssertEqual(updates["color"] as? String, "#ef4444")
    }

    func testAITD500_AnUnchangedColorIsNotSent() {
        var original = TaskList(id: "list-1", name: "Groceries")
        original.color = "#3b82f6"
        var updated = original
        updated.name = "Shopping"

        XCTAssertFalse(ListSettingsPayload.updates(original: original, updated: updated).keys.contains("color"))
    }
}
