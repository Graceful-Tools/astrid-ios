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
            contentsOf: RepositoryLocator.root
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

    // MARK: - AITD-404: reading, and the due-date half

    /// THE BUG ON THE WAY IN. A bare `ISO8601DateFormatter` does not truncate a fractional
    /// string — it returns nil. Since AITD-369 the app deliberately WRITES `.869Z` stamps, so
    /// every hand-rolled parse was silently dropping dates rather than rounding them.
    func testAITD404_AFractionalStampParsesInsteadOfVanishing() {
        XCTAssertNil(ISO8601DateFormatter().date(from: "2026-09-08T14:02:37.869Z"),
                     "precondition: this is exactly what the bare formatter does")
        let parsed = WireDate.date(from: "2026-09-08T14:02:37.869Z")
        XCTAssertNotNil(parsed, "AITD-404: a stamp we ourselves wrote must be readable")
        XCTAssertEqual(parsed?.timeIntervalSince1970 ?? 0, 1788876157.869, accuracy: 0.002)
    }

    /// And the mirror image, which `AccountSettingsView` had: a parser configured for fractional
    /// seconds ONLY rejects a plain stamp. Both shapes arrive from the server.
    func testAITD404_APlainStampParsesToo() {
        let fractionalOnly = ISO8601DateFormatter()
        fractionalOnly.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertNil(fractionalOnly.date(from: "2026-09-08T14:02:37Z"),
                     "precondition: fractional-only rejects the plain shape")
        XCTAssertNotNil(WireDate.date(from: "2026-09-08T14:02:37Z"))
    }

    func testAITD404_GarbageIsStillNil() {
        XCTAssertNil(WireDate.date(from: "not a date"))
        XCTAssertNil(WireDate.date(from: ""))
    }

    /// A DUE DATE DELIBERATELY CARRIES NO MILLISECONDS. Nothing orders two due dates by
    /// sub-second precision, so `dueDateString` exists to fix the per-call formatter allocation
    /// WITHOUT changing a byte on the wire. This pins that, so "route everything through
    /// WireDate" never quietly becomes "put .000 on every due date".
    func testAITD404_ADueDateIsWrittenWithoutMilliseconds() {
        let stamp = WireDate.dueDateString(from: Date(timeIntervalSince1970: 1788876157.869))
        XCTAssertEqual(stamp, "2026-09-08T14:02:37Z")
        XCTAssertFalse(stamp.contains("."), "AITD-404: due dates stay whole-second on the wire")
        // …while the ordered-timestamp formatter still keeps them.
        XCTAssertTrue(WireDate.string(from: Date(timeIntervalSince1970: 1788876157.869)).contains("."))
    }

    /// Round-trip: what we write for a due date must be readable by what we read with.
    func testAITD404_ADueDateRoundTrips() throws {
        let original = Date(timeIntervalSince1970: 1788876157)
        let parsed = try XCTUnwrap(WireDate.date(from: WireDate.dueDateString(from: original)))
        XCTAssertEqual(parsed.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.001)
    }

    /// The sites that were parsing by hand must ask WireDate now. Listed explicitly rather than
    /// swept: several OTHER bare formatters in the tree are correct (SyncSuppression's are stored,
    /// UTC-pinned and already carry both shapes) and a blanket ban would be wrong about them.
    func testAITD404_TheHandRolledParsesNowAskWireDate() throws {
        let root = RepositoryLocator.root
        for path in ["Astrid App/Core/Tasks/NewTaskDefaults.swift",
                     "Astrid App/Views/Tasks/QuickAddTaskView.swift",
                     "Astrid App/Views/Settings/CustomAgentsSettingsView.swift",
                     "Astrid App/Views/Settings/AccountSettingsView.swift"] {
            let src = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(src.contains("WireDate.date(from:"),
                          "AITD-404: \(path) should parse through WireDate")
            XCTAssertFalse(src.contains("ISO8601DateFormatter()"),
                           "AITD-404: \(path) should not build its own parser")
        }
    }
}
