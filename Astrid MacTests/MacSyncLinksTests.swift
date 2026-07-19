//  MacSyncLinksTests.swift
//  Astrid for Mac — Task 7043e478: per-list external-sync link lookup + sync-mode labels.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSyncLinksTests: XCTestCase {

    private func link(_ astrid: String, _ container: String) -> ExternalListLinkDTO {
        ExternalListLinkDTO(id: "lnk-\(astrid)", astridListId: astrid,
                            remoteContainerId: container, remoteContainerName: container, cursor: nil)
    }

    func testFindLinkForList() {
        let links = [link("a", "repo-a"), link("b", "repo-b")]
        XCTAssertEqual(MacSyncLinks.link(links, for: "b")?.remoteContainerName, "repo-b")
        XCTAssertNil(MacSyncLinks.link(links, for: "c"))
        XCTAssertNil(MacSyncLinks.link([], for: "a"))
    }

    func testGoogleModeLabels() {
        XCTAssertEqual(MacSyncLinks.googleModeLabel(.manual), "Link lists manually")
        XCTAssertEqual(MacSyncLinks.googleModeLabel(.allGoogleToAstrid), "All Google → Astrid")
        XCTAssertEqual(MacSyncLinks.googleModeLabel(.allAstridToGoogle), "All Astrid → Google")
        XCTAssertEqual(MacSyncLinks.googleModeLabel(.allBidirectional), "Two-way (all lists)")
        // Every mode has a non-empty label.
        for m in GoogleSyncMode.allCases {
            XCTAssertFalse(MacSyncLinks.googleModeLabel(m).isEmpty)
        }
    }
}
#endif
