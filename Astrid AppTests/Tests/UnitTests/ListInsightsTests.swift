//  ListInsightsTests.swift
//  List Insights on iOS and Mac (AITD-545), the companion to web's AWTD-1329. The server computes
//  the numbers (astrid-web lib/list-insights.ts); these pin the wire shape, the request and the
//  presentation rules web's ListInsightsPanel applies.

import SwiftUI
import XCTest
@testable import Astrid_App

@MainActor
final class ListInsightsTests: XCTestCase {

    /// The route's answer for a board, as astrid-web's route test captures it.
    private let boardAnswer = #"""
    { "insights": {
      "window": { "days": 7, "timeZone": "America/Los_Angeles", "start": "2026-10-16", "end": "2026-10-22" },
      "series": [ { "date": "2026-10-21", "created": 2, "completed": 0 },
                  { "date": "2026-10-22", "created": 1, "completed": 3 } ],
      "totals": { "created": 3, "completed": 3 },
      "createToComplete": { "medianMs": 111600000, "sampleSize": 3 },
      "lanes": [ { "role": "inbox", "name": "Inbox", "medianMs": null, "sampleSize": 0 },
                 { "role": "doing", "name": "Doing", "medianMs": 5400000, "sampleSize": 2 } ],
      "contributors": [ { "userId": "u1", "name": "Ada", "image": null, "isAIAgent": false,
                          "completed": 3, "inspired": 1, "supported": 2,
                          "created": 2, "edited": 4, "commented": 1, "total": 10 },
                        { "userId": "ai-agent-claude", "name": "Claude Agent", "image": "https://x/c.png",
                          "isAIAgent": true, "created": 1, "edited": 0, "commented": 0, "completed": 0, "total": 1 } ]
    } }
    """#

    private func decode(_ json: String) throws -> ListInsights {
        try JSONDecoder().decode(ListInsightsResponse.self, from: Data(json.utf8)).insights
    }

    // MARK: - The wire shape

    func testTheRoutesAnswerDecodes_AITD545() throws {
        let insights = try decode(boardAnswer)
        XCTAssertEqual(insights.window.days, 7)
        XCTAssertEqual(insights.window.timeZone, "America/Los_Angeles")
        XCTAssertEqual(insights.series.map(\.date), ["2026-10-21", "2026-10-22"], "oldest first, as sent")
        XCTAssertEqual(insights.series.last?.completed, 3)
        XCTAssertEqual(insights.totals, .init(created: 3, completed: 3))
        XCTAssertEqual(insights.createToComplete.medianMs, 111_600_000)
        XCTAssertEqual(insights.lanes?.map(\.role), ["inbox", "doing"], "column order, as sent")
        XCTAssertNil(insights.lanes?.first?.medianMs, "null is nothing to take a median of, not zero")
        XCTAssertEqual(insights.contributors.first?.inspired, 1)
        XCTAssertEqual(insights.contributors.last?.isAIAgent, true)
    }

    /// A list that is not a board sends `lanes: null`, and a server from before AWTD-1333 sends no
    /// `inspired` / `supported`. Neither may fail the whole answer.
    func testANonBoardAndAnOlderServerStillDecode_AITD545() throws {
        let insights = try decode(#"""
            { "insights": { "window": { "days": 30, "timeZone": "UTC", "start": "2026-09-23", "end": "2026-10-22" },
              "series": [], "totals": { "created": 0, "completed": 0 },
              "createToComplete": { "medianMs": null, "sampleSize": 0 }, "lanes": null,
              "contributors": [ { "userId": "u1", "name": null, "image": null, "isAIAgent": false,
                                  "created": 1, "edited": 0, "commented": 0, "completed": 0, "total": 1 } ] } }
            """#)
        XCTAssertNil(insights.lanes)
        XCTAssertNil(insights.createToComplete.medianMs)
        XCTAssertEqual(insights.contributors.first?.inspired, 0)
        XCTAssertEqual(insights.contributors.first?.supported, 0)
        XCTAssertNil(insights.contributors.first?.name)
    }

    // MARK: - The request

    func testTheServiceAsksForTheWindowInTheCallersTimeZone_AITD545() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.respond = { _ in .json(self.boardAnswer) }
        let service = ListInsightsService(apiClient: AstridAPIClient(session: StubURLProtocol.session()))

        let insights = try await service.insights(listId: "list-1", days: 7,
                                                  timeZone: TimeZone(identifier: "America/Los_Angeles")!)

        XCTAssertEqual(insights.window.days, 7)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.path, "/api/v1/lists/list-1/insights")
        XCTAssertEqual(sent.query, ["days": "7", "tz": "America/Los_Angeles"])
    }

    func testAListTheCallerCannotSeeIsAnError_AITD545() async {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.respond = { _ in .json(#"{"error":"Not found"}"#, status: 404) }
        let service = ListInsightsService(apiClient: AstridAPIClient(session: StubURLProtocol.session()))
        do {
            _ = try await service.insights(listId: "list-1", days: 30)
            XCTFail("a 404 must surface, so the tab says it couldn't load")
        } catch {}
    }

    // MARK: - Presentation (web's ListInsightsPanel)

    /// Minutes under an hour, hours under two days, then days — at most one decimal, none when whole.
    func testADurationReadsAtTheOneNaturalUnit_AITD545() {
        let minute = 60_000.0, hour = 60 * minute, day = 24 * hour
        XCTAssertEqual(ListInsightsFormat.duration(10_000), "1 min", "never 0 min")
        XCTAssertEqual(ListInsightsFormat.duration(25 * minute), "25 min")
        XCTAssertEqual(ListInsightsFormat.duration(hour - 1), "60 min")
        XCTAssertEqual(ListInsightsFormat.duration(hour), "1 h")
        XCTAssertEqual(ListInsightsFormat.duration(90 * minute), "1.5 h")
        XCTAssertEqual(ListInsightsFormat.duration(31 * hour), "31 h")
        XCTAssertEqual(ListInsightsFormat.duration(2 * day), "2 d")
        XCTAssertEqual(ListInsightsFormat.duration(2.25 * day), "2.3 d", "rounded half up, as JavaScript's Math.round")
    }

    func testAMissingMedianIsADashNeverZero_AITD545() {
        XCTAssertNil(ListInsightsFormat.median(.init(medianMs: nil, sampleSize: 0)))
        XCTAssertEqual(ListInsightsFormat.median(.init(medianMs: 5_400_000, sampleSize: 2)), "1.5 h")
        XCTAssertEqual(ListInsightsFormat.sampleSize(.init(medianMs: 1, sampleSize: 42)), "from 42")
    }

    /// Lane moves are recorded only from the AWTD-1329 deploy, so a board where no lane has a
    /// sample says "not enough history" instead of a column of dashes.
    func testABoardWithNoLaneHistorySaysSo_AITD545() throws {
        let lanes = try XCTUnwrap(try decode(boardAnswer).lanes)
        XCTAssertTrue(ListInsightsFormat.lanesHaveHistory(lanes))
        XCTAssertFalse(ListInsightsFormat.lanesHaveHistory([.init(role: "inbox", name: "Inbox", medianMs: nil, sampleSize: 0)]))
        XCTAssertFalse(ListInsightsFormat.lanesHaveHistory([]))
    }

    func testTheCountsUnderEachContributor_AITD545() throws {
        let ada = try XCTUnwrap(try decode(boardAnswer).contributors.first)
        XCTAssertEqual(ListInsightsFormat.profileCounts(ada), "3 completed · 1 inspired · 2 supported")
        XCTAssertEqual(ListInsightsFormat.activityCounts(ada), "2 created · 4 edits · 1 comments")
        XCTAssertEqual(ada.user.initials, "AD")
        XCTAssertEqual(ListInsightsFormat.totals(.init(created: 60, completed: 45)), "60 new · 45 completed")
    }

    func testTheWindowsAreTheOnesTheRouteAccepts_AITD545() {
        XCTAssertEqual(ListInsightsFormat.windows, [7, 30, 90], "anything else is a 400")
        XCTAssertEqual(ListInsightsFormat.defaultWindow, 30, "the route's own default")
        XCTAssertEqual(ListInsightsFormat.windows.map(ListInsightsFormat.windowLabel), ["7 days", "30 days", "90 days"])
    }

    /// A day plots on its own calendar day, whatever zone the device is in.
    func testADayPlotsOnItsOwnDate_AITD545() throws {
        let date = try XCTUnwrap(ListInsightsFormat.plotDate("2026-10-22"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.dateComponents([.year, .month, .day], from: date), DateComponents(year: 2026, month: 10, day: 22))
        XCTAssertNil(ListInsightsFormat.plotDate("not a day"))
    }

    // MARK: - Where it shows

    func testEveryListButASavedFilterHasInsights_AITD545() {
        XCTAssertTrue(ListInsightsFormat.isAvailable(for: TaskList(id: "l", name: "Groceries")))
        XCTAssertTrue(ListInsightsFormat.isAvailable(for: TaskList(id: "l", name: "Board", isVirtual: false)))
        XCTAssertFalse(ListInsightsFormat.isAvailable(for: TaskList(id: "f", name: "Due today", isVirtual: true)),
                       "a saved filter has no history of its own — web hides the tab too")
    }

    /// Each state the tab can be in renders, through the same content view the tab hosts.
    func testEveryStateOfTheTabRenders_AITD545() throws {
        let board = try decode(boardAnswer)
        let empty = try decode(#"""
            { "insights": { "window": { "days": 30, "timeZone": "UTC", "start": "2026-09-23", "end": "2026-10-22" },
              "series": [], "totals": { "created": 0, "completed": 0 },
              "createToComplete": { "medianMs": null, "sampleSize": 0 }, "lanes": null, "contributors": [] } }
            """#)
        for (insights, failed) in [(board, false), (empty, false), (nil, false), (nil, true)] as [(ListInsights?, Bool)] {
            let view = ListInsightsContent(insights: insights, failed: failed, days: .constant(7))
                .frame(width: 360, height: 900)
            let renderer = ImageRenderer(content: view)
            XCTAssertNotNil(renderer.cgImage, "renders with insights \(insights == nil ? "loading" : "loaded"), failed \(failed)")
        }
    }
}
