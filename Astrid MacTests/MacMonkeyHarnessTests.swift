import XCTest

final class MacMonkeyHarnessTests: XCTestCase {
    private var source: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Astrid MacUITests/MacMonkeyUITests.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testAITD_296MonkeyCannotSilentlyContinueWithoutAWindow() throws {
        let source = try source
        XCTAssertTrue(source.contains("isWindowControl(buttonFrame:"),
                      "window controls must be excluded by stable geometry, not localized labels")
        XCTAssertTrue(source.contains("The Mac app has no driveable window after action"),
                      "losing the last window must fail the run immediately")
        XCTAssertFalse(source.contains("[\"close\", \"minimize\", \"zoom\"].contains"),
                       "window-control identifiers are empty on macOS")
    }

    func testAITD_295WeeklyRunSurfacesLastSuccessfulMacRun() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let weekly = try String(contentsOf: root.appendingPathComponent("scripts/monkey-weekly.sh"),
                                encoding: .utf8)
        XCTAssertTrue(weekly.contains("last-success-mac"))
        XCTAssertTrue(weekly.contains("Mac monkey has not run successfully since"))

        let setup = try String(contentsOf: root.appendingPathComponent("docs/XCODE_SETUP.md"),
                               encoding: .utf8)
        XCTAssertTrue(setup.contains("sudo DevToolsSecurity -enable"))
        XCTAssertTrue(setup.contains("Privacy & Security > Accessibility"))
    }
}
