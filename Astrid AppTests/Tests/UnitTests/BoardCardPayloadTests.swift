//  BoardCardPayloadTests.swift
//  Regression tests for Task 3ed65a40 — "Dragging tasks between ready, doing, done isn't
//  working."
//
//  History matters here. In May the report was "dragging and dropping tasks to board list
//  isn't reliable", and the fix (a090d51) replaced the bare `String` drag payload with a
//  typed `BoardCardPayload` — declared as `CodableRepresentation(contentType: .data)`.
//  Three months later the same gesture is reported as not working at all.
//
//  `.data` is `public.data`: the ROOT of every binary type in the system. A drag item
//  advertised as public.data has no identity of its own — the drop destination is asked to
//  load *any* public.data item and JSON-decode it as a BoardCardPayload, which fails for
//  anything that isn't one, and the card springs back to where it started. That is the
//  symptom being reported.
//
//  The documented fix is an app-specific exported UTType. These tests pin both halves of
//  it, because the half that rots silently is the Info.plist one: if the declaration and
//  the code drift apart, drag-and-drop breaks with no compiler error and no failing build.

import XCTest
import UniformTypeIdentifiers
@testable import Astrid_App

final class BoardCardPayloadTests: XCTestCase {

    /// THE BUG: a board card must not be advertised as generic system data.
    func testPayloadIsNotAdvertisedAsGenericData() {
        XCTAssertNotEqual(BoardCardPayload.contentType, .data,
                          "public.data is every binary type in the system — a drop destination "
                          + "cannot tell a board card from an arbitrary blob, so drops fail")
        XCTAssertTrue(BoardCardPayload.contentType.conforms(to: .data),
                      "the payload is still data-backed; it just needs its own identity")
    }

    /// The app-specific type, spelled exactly once in code.
    func testPayloadUsesTheAppSpecificDragType() {
        XCTAssertEqual(BoardCardPayload.contentType.identifier, "cc.astrid.board-card")
    }

    /// The half that rots silently: a UTType the app never exported is not registered with
    /// the system, so the drag advertises a type nothing recognises. If this drifts from
    /// the constant above, drag-and-drop breaks with nothing to show for it.
    func testTheDragTypeIsExportedInInfoPlist() throws {
        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]],
            "the app declares no exported UTTypes — the board's drag type is unregistered")

        let identifiers = declarations.compactMap { $0["UTTypeIdentifier"] as? String }
        XCTAssertTrue(identifiers.contains(BoardCardPayload.contentType.identifier),
                      "Info.plist must export \(BoardCardPayload.contentType.identifier); "
                      + "it exports \(identifiers)")

        // A drag type that doesn't conform to public.data can't carry the encoded payload.
        let ours = try XCTUnwrap(declarations.first {
            $0["UTTypeIdentifier"] as? String == BoardCardPayload.contentType.identifier
        })
        let conformsTo = ours["UTTypeConformsTo"] as? [String] ?? []
        XCTAssertTrue(conformsTo.contains("public.data"),
                      "the exported type must conform to public.data to carry the payload")
    }

    /// The payload still has to survive the round trip it exists for.
    func testPayloadRoundTripsThroughItsEncoding() throws {
        let original = BoardCardPayload(taskId: "task-abc-123")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BoardCardPayload.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.taskId, "task-abc-123")
    }
}
