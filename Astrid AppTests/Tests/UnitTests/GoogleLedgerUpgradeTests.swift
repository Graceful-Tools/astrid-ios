//  GoogleLedgerUpgradeTests.swift
//  AITD-463: the Google pass moved into astrid-core, and the Swift pass's deletion ledger has to go
//  with it — a deletion queued before the update must still reach Google.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class GoogleLedgerUpgradeTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "GoogleLedgerUpgradeTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = try JSONEncoder().encode(command)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func seedSwiftLedger() {
        defaults.set(["g-pending": "tl1"], forKey: "syncPendingRemoteDeletes.google")
        defaults.set(["g-old", "g-pending"], forKey: "syncDeletedRemoteIds.google")
        defaults.set(["g-web"], forKey: "syncServerTombstones.google")
        defaults.set(["t1": "g-linked|tl2", "t2": "malformed"], forKey: "googleTaskLinkCache")
    }

    func testTheImportCarriesEveryPartOfTheSwiftLedger_AITD463() throws {
        seedSwiftLedger()
        let command = try json(GoogleLedgerUpgrade.command(defaults: defaults))

        XCTAssertEqual(command["kind"] as? String, "importExternalLedger")
        XCTAssertEqual(command["provider"] as? String, "google_tasks")
        let pending = try XCTUnwrap(command["pending"] as? [[String: String]])
        XCTAssertEqual(pending, [["remoteId": "g-pending", "containerId": "tl1"]])
        XCTAssertEqual(command["tombstones"] as? [String], ["g-old", "g-pending"], "oldest first")
        XCTAssertEqual(command["serverTombstones"] as? [String], ["g-web"])
        let links = try XCTUnwrap(command["links"] as? [[String: String]])
        XCTAssertEqual(links, [["taskId": "t1", "remoteId": "g-linked", "containerId": "tl2"]],
                       "a malformed cache entry is dropped, not sent")
    }

    /// Against the real core: it must accept the command, and only then is the upgrade done.
    func testTheCoreAcceptsTheImportAndTheUpgradeRunsOnce_AITD463() async throws {
        seedSwiftLedger()
        await GoogleLedgerUpgrade.runIfNeeded(AppCore.shared.session, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: GoogleLedgerUpgrade.doneKey))
    }

    func testAnEmptySwiftLedgerStillCompletes_AITD463() async throws {
        await GoogleLedgerUpgrade.runIfNeeded(AppCore.shared.session, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: GoogleLedgerUpgrade.doneKey))
    }
}
