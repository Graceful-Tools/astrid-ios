import XCTest

final class BuildConfigurationPrivacyTests: XCTestCase {
    /// Regression for Astrid task a5ce5620-8be6-421e-a6fb-1d7d55ce253c.
    func testLocalNetworkExceptionsAreDebugOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let release = try plist(root.appendingPathComponent("Info.plist"))
        let debug = try plist(root.appendingPathComponent("Info-Debug.plist"))
        let project = try String(contentsOf: root.appendingPathComponent("Astrid App.xcodeproj/project.pbxproj"), encoding: .utf8)

        XCTAssertNil(release["NSAppTransportSecurity"])
        XCTAssertNil(release["NSBonjourServices"])
        XCTAssertNil(release["NSLocalNetworkUsageDescription"])
        XCTAssertNotNil(debug["NSAppTransportSecurity"])
        XCTAssertNotNil(debug["NSBonjourServices"])
        XCTAssertNotNil(debug["NSLocalNetworkUsageDescription"])
        XCTAssertTrue(project.contains("INFOPLIST_FILE = \"Info-Debug.plist\";"))
    }

    private func plist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
