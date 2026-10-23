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

    /// Rule 8 (AITD-537): the Mac picker reads the iOS picker's `sync.mode_*` keys, brand filled in.
    func testGoogleModeLabelsReadTheIOSKeys_AITD537() {
        let expected: [(GoogleSyncMode, String)] = [
            (.manual, "sync.mode_manual"),
            (.allGoogleToAstrid, "sync.mode_google_to_astrid"),
            (.allAstridToGoogle, "sync.mode_astrid_to_google"),
            (.allBidirectional, "sync.mode_bidirectional"),
        ]
        for (mode, key) in expected {
            let format = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(format, key, "\(key) is missing")
            XCTAssertEqual(MacSyncLinks.googleModeLabel(mode), String(format: format, Brand.appName))
        }
        XCTAssertTrue(MacSyncLinks.googleModeLabel(.allGoogleToAstrid).contains(Brand.appName))
        // Every mode has a non-empty label.
        for m in GoogleSyncMode.allCases {
            XCTAssertFalse(MacSyncLinks.googleModeLabel(m).isEmpty)
        }
    }
}
#endif
