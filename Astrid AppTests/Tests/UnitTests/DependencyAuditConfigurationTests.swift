import XCTest

final class DependencyAuditConfigurationTests: XCTestCase {
    /// Regression for Astrid task bd0cfa4e-c005-4549-b4fb-2fbe7ff313ec.
    func testNpmAuditHasLockfileWithoutInstallSideEffects() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("package.json"), encoding: .utf8)
        let lock = root.appendingPathComponent("package-lock.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: lock.path))
        XCTAssertTrue(package.contains("\"audit:dependencies\": \"npm audit --omit=dev\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("node_modules").path))
    }
}
