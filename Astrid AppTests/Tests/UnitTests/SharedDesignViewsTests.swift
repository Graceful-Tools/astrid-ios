//  SharedDesignViewsTests.swift
//  ADEV-166: one pill, one Done header and one empty state, shared by iOS and the Mac.

import SwiftUI
import XCTest
@testable import Astrid_App

final class SharedDesignViewsTests: XCTestCase {

    func testADEV166_bothPillsDrawThroughAstridPill() throws {
        for path in ["Astrid App/Views/Components/TaskBoardStatusPill.swift",
                     "Astrid App/Views/Components/CompletedOnPill.swift"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertTrue(source.contains("AstridPill("), "\(path) uses the shared pill")
            XCTAssertFalse(source.contains("opacity(0.15)"), "\(path) does not restate the wash")
        }
    }

    func testADEV166_theIOSDoneHeaderIsTheSharedBadge() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Views/Board/BoardColumnView.swift")
        XCTAssertTrue(source.contains("BoardHeaderBadge"))
        _ = BoardHeaderBadge { Text(verbatim: "3") }
        _ = AstridSpeechBubble(message: "Nothing here", density: .regular)
    }
}
