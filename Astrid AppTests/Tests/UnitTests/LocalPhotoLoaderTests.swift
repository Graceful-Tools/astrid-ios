import XCTest
@testable import Astrid_App

/// Tests for `LocalPhotoLoader`'s pure decision logic — the part that turns a
/// no-network PhotoKit read into an outcome. The PhotoKit I/O itself needs a
/// real device (iCloud-optimized photos don't exist in the simulator), so only
/// the decision is unit-tested; the wiring is verified on-device.
///
/// Goal of the feature (task: "real offline photo support"): a photo that is
/// on-disk attaches instantly even offline (and queues its upload), while a
/// cloud-only photo offline fails fast with a clear message instead of hanging
/// on a doomed iCloud download.
final class LocalPhotoLoaderTests: XCTestCase {

    func testLocalBytesAlwaysSucceed() {
        let bytes = Data([0x1, 0x2, 0x3])
        XCTAssertEqual(LocalPhotoLoader.outcome(imageData: bytes, isInCloud: false, isConnected: false),
                       .data(bytes), "on-disk photo must attach even when offline")
        XCTAssertEqual(LocalPhotoLoader.outcome(imageData: bytes, isInCloud: true, isConnected: true),
                       .data(bytes), "if bytes came back, use them regardless of cloud flag")
    }

    func testCloudOnlyOfflineIsNotLocallyAvailable() {
        XCTAssertEqual(LocalPhotoLoader.outcome(imageData: nil, isInCloud: true, isConnected: false),
                       .notLocallyAvailable,
                       "cloud-only photo offline must fail fast as not-locally-available")
    }

    func testEmptyDataTreatedAsNoBytes() {
        XCTAssertEqual(LocalPhotoLoader.outcome(imageData: Data(), isInCloud: true, isConnected: false),
                       .notLocallyAvailable,
                       "empty data is not a usable image")
    }

    func testOnlineWithoutLocalBytesFallsThroughToFailed() {
        // Online: the caller will retry allowing network, so a no-local-bytes
        // result is .failed (not the offline message).
        XCTAssertEqual(LocalPhotoLoader.outcome(imageData: nil, isInCloud: true, isConnected: true),
                       .failed)
    }
}
