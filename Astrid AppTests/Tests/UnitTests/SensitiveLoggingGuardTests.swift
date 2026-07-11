import XCTest

final class SensitiveLoggingGuardTests: XCTestCase {
    /// Regression for Astrid task 12d5372d-b5e7-4568-9222-c20aeccd62f8.
    /// Security-sensitive networking and authentication paths must never log
    /// secrets, raw payloads, complete URLs, headers, or account identifiers.
    func testSensitivePathsDoNotPrintPrivateRequestData() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Astrid App/Core/Networking/APIClient.swift",
            "Astrid App/Core/Networking/AstridAPIClient.swift",
            "Astrid App/Core/Services/AttachmentService.swift",
            "Astrid App/Core/Authentication/AuthManager.swift",
            "Astrid App/Core/Authentication/PasskeyManager.swift",
        ]
        let forbiddenFragments = [
            "sessionCookie.prefix",
            "savedCookie.prefix",
            "allHTTPHeaderFields",
            "Request body:",
            "Request body (with nulls):",
            "Response body:",
            "Response body preview:",
            "Error response: \\(responseString)",
            "Response: \\(responseString)",
            "url.absoluteString",
            "response.user.email",
            "user.email",
        ]

        var violations: [String] = []
        for relativePath in relativePaths {
            let source = try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
            for (lineNumber, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("print(") {
                for fragment in forbiddenFragments where line.contains(fragment) {
                    violations.append("\(relativePath):\(lineNumber + 1): \(fragment)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Sensitive log expressions remain:\n\(violations.joined(separator: "\n"))"
        )
    }
}
