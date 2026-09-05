import XCTest

/// The local release script must verify a build BEFORE it ships it (Task:
/// 3f964556).
///
/// It used to export with `destination = upload`, which uploads straight from
/// the archive and leaves no `.ipa` on disk — so the entitlements check that
/// ran afterwards found nothing, failed its own guard, and printed
/// `RESULT: FAILED` after a *successful* upload. The App Group check that task
/// a915a6b2 exists for therefore never ran on a single shipping build.
///
/// Asserted by reading the script because there is nothing else to assert on:
/// the failure is an ORDER, and reproducing it costs a ten-minute archive.
final class ReleaseScriptOrderingTests: XCTestCase {

    private var script: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/appstore-release.sh")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testEntitlementsAreVerifiedBeforeAnythingIsUploaded_3f964556() throws {
        let text = try script
        let verify = try XCTUnwrap(
            text.range(of: "step \"Verifying signed entitlements\""),
            "the entitlements check disappeared")
        let upload = try XCTUnwrap(
            text.range(of: "step \"Uploading to App Store Connect\""),
            "the upload step disappeared")
        XCTAssertLessThan(
            verify.lowerBound, upload.lowerBound,
            "an unverified build must never be uploaded — verify first")
    }

    func testTheVerifiedArtifactIsAlwaysWrittenToDisk_3f964556() throws {
        let text = try script
        // The check opens an .ipa from the export directory, so the export that
        // precedes it must be a real export — never `destination = upload`,
        // which leaves nothing behind.
        let verify = try XCTUnwrap(text.range(of: "step \"Verifying signed entitlements\""))
        let beforeVerify = String(text[text.startIndex..<verify.lowerBound])
        XCTAssertFalse(
            beforeVerify.contains("<key>destination</key><string>upload</string>"),
            "the export feeding the entitlements check must write an .ipa, so it cannot be an upload export")
    }
}
