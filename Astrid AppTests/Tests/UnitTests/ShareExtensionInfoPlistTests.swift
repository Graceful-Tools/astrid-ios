import XCTest

/// The Share Extension's `Info.plist` must name its entry point ONE way.
///
/// Carrying both `NSExtensionMainStoryboard` and `NSExtensionPrincipalClass`
/// builds and signs perfectly and is then rejected by App Store Connect at
/// upload — "Ambiguous Info.plist values … Only one of these should be
/// present" — so nothing catches it until a build is already archived. It cost
/// three failed Xcode Cloud runs on 2026-08-29 (Task: a915a6b2).
final class ShareExtensionInfoPlistTests: XCTestCase {

    func testExtensionNamesItsEntryPointExactlyOneWay_a915a6b2() throws {
        let extensionPlist = try repoRoot().appendingPathComponent("Astrid/Info.plist")
        let data = try Data(contentsOf: extensionPlist)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let nsExtension = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        let storyboard = nsExtension["NSExtensionMainStoryboard"] as? String
        let principalClass = nsExtension["NSExtensionPrincipalClass"] as? String

        XCTAssertFalse(
            storyboard != nil && principalClass != nil,
            "both NSExtensionMainStoryboard and NSExtensionPrincipalClass are set — Apple rejects the upload")
        XCTAssertTrue(
            storyboard != nil || principalClass != nil,
            "the extension must name an entry point")
    }

    /// The storyboard is the entry point, so it has to bind the real
    /// controller — the template's stub is what shipped for months.
    func testMainStoryboardBindsTheRealShareViewController_a915a6b2() throws {
        let storyboard = try repoRoot().appendingPathComponent("Astrid/Base.lproj/MainInterface.storyboard")
        let xml = try String(contentsOf: storyboard, encoding: .utf8)
        XCTAssertTrue(xml.contains("customClass=\"ShareViewController\""))
        XCTAssertTrue(xml.contains("customModuleProvider=\"target\""))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }
}
