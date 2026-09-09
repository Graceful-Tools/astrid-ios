//  WireDatePrecisionTests.swift
//  AITD-369 — "Which client wrote two iOS completions with an identical second-precision
//  completedAt?"
//
//  The answer was: this one, and it could not have written anything else. `completedAt` was
//  formatted with a bare `ISO8601DateFormatter()`, whose default options carry no fractional
//  seconds, so every completion iOS ever sent was truncated to the whole second. On
//  2026-09-08T14:02:37 four unrelated tasks were completed inside one second and reached the
//  server as four identical `…:37.000Z` stamps — no way to order them, no way to tell them
//  apart, and the investigation into what wrote them stalled there.
//
//  These tests pin the precision at the boundary where it was lost.

import XCTest
@testable import Astrid_App

final class WireDatePrecisionTests: XCTestCase {

    // MARK: - The format

    func testWireDateKeepsMilliseconds() {
        let date = Date(timeIntervalSince1970: 1_789_221_757.869)
        let formatted = WireDate.string(from: date)
        XCTAssertEqual(formatted, "2026-09-12T14:02:37.869Z",
                       "the wire format must carry milliseconds — that is the whole point of AITD-369")
    }

    /// The bug, stated as the thing it broke: two instants that differ must not become one
    /// string. A whole-second format collapses everything inside a second onto one value, which
    /// is how four distinct completions became four identical rows.
    func testInstantsInsideOneSecondStayDistinct() {
        let base = Date(timeIntervalSince1970: 1_789_221_757.100)
        let stamps = (0..<4).map { WireDate.string(from: base.addingTimeInterval(Double($0) * 0.2)) }
        XCTAssertEqual(Set(stamps).count, 4,
                       "four completions inside one second must produce four different stamps, got \(stamps)")
    }

    /// What the OLD code did, kept as the contrast so the regression is legible rather than
    /// implied. This is not the app's behaviour any more; it is the behaviour being excluded.
    func testABareFormatterIsExactlyWhatMustNotBeUsed() {
        let base = Date(timeIntervalSince1970: 1_789_221_757.100)
        let truncated = (0..<4).map { ISO8601DateFormatter().string(from: base.addingTimeInterval(Double($0) * 0.2)) }
        XCTAssertEqual(Set(truncated).count, 1,
                       "a bare ISO8601DateFormatter collapses a whole second onto one value — "
                       + "if this ever stops being true, Foundation changed and the guard below can relax")
    }

    /// Round-trips through the SAME decoder the API client uses, so the server's fractional
    /// stamps and ours are read by one rule.
    func testTheDecoderReadsWhatWeWrite() throws {
        let date = Date(timeIntervalSince1970: 1_789_221_757.869)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = try XCTUnwrap(parser.date(from: WireDate.string(from: date)))
        XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - The call site

    /// The format is only as good as the one place that writes it. `TaskService` builds every
    /// task update in the app, and a bare `ISO8601DateFormatter()` on its `completedAt` line is
    /// precisely the regression — one that would be invisible until someone next tried to order
    /// two completions and found they were the same instant.
    func testTaskServiceStampsCompletedAtThroughWireDate() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Astrid App/Core/Services/TaskService.swift"),
            encoding: .utf8)

        // Matched on the expression rather than the line: the write wraps across two lines, and
        // a line-shaped assertion would go quietly green the next time someone reformatted it.
        XCTAssertTrue(source.contains("WireDate.string(from: completedAt"),
                      "completedAt must be stamped through WireDate")
        XCTAssertFalse(source.contains("ISO8601DateFormatter().string(from: completedAt"),
                       "completedAt must not be stamped with a bare formatter — that truncates to "
                       + "the second, which is AITD-369")
    }
}
