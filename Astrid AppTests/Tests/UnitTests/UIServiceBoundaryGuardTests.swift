import XCTest

final class UIServiceBoundaryGuardTests: XCTestCase {
    func testViewsAndViewModelsDoNotAccessNetworkClientsDirectly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let appRoot = root.appendingPathComponent("Astrid App")
        let protectedDirectories = ["Views", "ViewModels", "Utilities"]
        let forbidden = ["APIClient.shared", "AstridAPIClient.shared"]
        var violations: [String] = []

        for directory in protectedDirectories {
            let directoryURL = appRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for token in forbidden where source.contains(token) {
                    violations.append("\(fileURL.lastPathComponent): \(token)")
                }
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "UI and utility code must call domain services, not network clients:\n\(violations.joined(separator: "\n"))"
        )
    }
}
