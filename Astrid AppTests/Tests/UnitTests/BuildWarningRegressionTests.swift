import XCTest

final class BuildWarningRegressionTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testTask_29222244BuildWarningPatternsDoNotReturn() throws {
        let quickAdd = try source("Astrid App/Core/Layout/QuickAddInputHeight.swift")
        XCTAssertFalse(quickAdd.contains("_Concurrency.Task { @MainActor in self?.apply"))

        let platform = try source("Astrid App/Core/Platform/Platform.swift")
        XCTAssertFalse(platform.contains("applicationIconBadgeNumber"))

        let richText = try source("Astrid App/Views/Components/RichTextInput.swift")
        XCTAssertFalse(richText.contains("return ZStack(alignment: .topTrailing)"))

        let reconnect = try source("Astrid App/Core/RealTime/SSEReconnectPolicy.swift")
        XCTAssertTrue(reconnect.contains("nonisolated static let maxAttempts"))

        let isolation = try source("Astrid App/Core/Networking/UITestNetworkIsolation.swift")
        XCTAssertTrue(isolation.contains("nonisolated static func harden"))

        let brand = try source("Astrid App/Utilities/Brand.swift")
        XCTAssertTrue(brand.contains("nonisolated static let agentName"))
    }
}
