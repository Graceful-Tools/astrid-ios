import XCTest
@testable import Astrid_App

/// Tests for `OfflinePhotoPolicy`, the single source of truth for what happens
/// when a picked photo can't be loaded.
///
/// Background: iOS "Optimize iPhone Storage" keeps full-resolution photos in
/// iCloud only. SwiftUI's PhotosPicker downloads the data on demand via
/// `loadTransferable`, which fails when the device is offline and the asset is
/// cloud-only. The comment composer and the task-detail composer each had their
/// own copy of the offline/online message; this policy unifies them so the
/// behavior and copy can't drift.
final class OfflinePhotoPolicyTests: XCTestCase {

    func testOfflineMessageGuidesUserToDownloadOrReconnect() {
        let message = OfflinePhotoPolicy.unavailableMessage(isConnected: false)
        XCTAssertTrue(message.lowercased().contains("download")
                      || message.lowercased().contains("internet"),
                      "offline message must tell the user the photo isn't downloaded / needs a connection")
    }

    func testOnlineMessageIsAGenericRetry() {
        let message = OfflinePhotoPolicy.unavailableMessage(isConnected: true)
        XCTAssertTrue(message.lowercased().contains("try again"),
                      "online failure should be a generic retry, not the offline hint")
        XCTAssertFalse(message.lowercased().contains("isn't downloaded"),
                       "online failure must not claim the photo isn't downloaded")
    }

    func testOnlineAndOfflineMessagesDiffer() {
        XCTAssertNotEqual(OfflinePhotoPolicy.unavailableMessage(isConnected: true),
                          OfflinePhotoPolicy.unavailableMessage(isConnected: false))
    }
}
