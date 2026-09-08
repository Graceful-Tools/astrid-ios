import XCTest

/// Regression for Astrid task c6a0f9ba-2b97-48c4-8d3d-f40955615020.
///
/// `print` is not compiled out of Release. Every surviving call still evaluates
/// its string interpolation in the shipping binary — once per avatar per row
/// render in `ImageCache`, once per received event in `SSEClient` — and 18 of
/// them built a user's email address into that string. `AppLog` takes its
/// message as an `@autoclosure` behind `#if DEBUG`, so in Release the string is
/// never built and the call is not there at all.
final class ReleaseLoggingHygieneTests: XCTestCase {
    /// The shipping source trees. Test targets may print freely.
    private static let sourceTrees = ["Astrid App", "Astrid Mac", "Shared", "Astrid"]

    func testShippingSourceHasNoBarePrintCalls() throws {
        var offenders: [String] = []
        for file in try Self.swiftFiles() {
            for (number, line) in try Self.lines(of: file) where Self.isBarePrint(line) {
                offenders.append("\(Self.relative(file)):\(number): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            \(offenders.count) bare print(…) call(s) would ship in Release, string \
            interpolation and all. Use AppLog.debug(…) — compiled out of Release — or, \
            for diagnostics that must survive into Release, Logger(subsystem: \
            Brand.logSubsystem, category:) with an explicit privacy level on every \
            interpolated value.

            \(offenders.prefix(25).joined(separator: "\n"))
            """
        )
    }

    /// Emails are account identifiers, which `PrivacyLogger`'s own contract says
    /// never to log. `AppLog.redact(email:)` keeps a first initial and the domain,
    /// which is enough to tell two members apart while debugging.
    func testLogsDoNotInterpolateEmailAddresses() throws {
        var offenders: [String] = []
        for file in try Self.swiftFiles() {
            for (number, line) in try Self.lines(of: file) where Self.isLogCall(line) {
                guard Self.interpolatesEmail(line) else { continue }
                offenders.append("\(Self.relative(file)):\(number): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            \(offenders.count) log call(s) interpolate an email address. Wrap it in \
            AppLog.redact(email:).

            \(offenders.prefix(25).joined(separator: "\n"))
            """
        )
    }

    // MARK: - Source scanning

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // UnitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // Astrid AppTests
        .deletingLastPathComponent()   // repository root

    private static func swiftFiles() throws -> [URL] {
        var files: [URL] = []
        for tree in sourceTrees {
            let root = repositoryRoot.appendingPathComponent(tree)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                XCTFail("Could not enumerate \(tree)")
                continue
            }
            for case let url as URL in walker where url.pathExtension == "swift" {
                files.append(url)
            }
        }
        XCTAssertFalse(files.isEmpty, "Found no Swift sources — the path to the repository root is wrong")
        return files
    }

    private static func lines(of file: URL) throws -> [(Int, String)] {
        let contents = try String(contentsOf: file, encoding: .utf8)
        return contents.components(separatedBy: .newlines).enumerated().map { ($0.offset + 1, $0.element) }
    }

    private static func relative(_ file: URL) -> String {
        file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
    }

    /// `print(…)` as a statement. `Swift.print(…)` — how `AppLog` and
    /// `PrivacyLogger` actually emit, inside `#if DEBUG` — is deliberately not a match.
    private static func isBarePrint(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("print(")
    }

    private static func isLogCall(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("print(")
            || trimmed.hasPrefix("Swift.print(")
            || trimmed.hasPrefix("AppLog.")
            || trimmed.hasPrefix("logger.")
            || trimmed.hasPrefix("PrivacyLogger.")
    }

    /// An interpolation whose expression mentions `email`, other than one that
    /// has already been handed to `AppLog.redact`.
    private static func interpolatesEmail(_ line: String) -> Bool {
        var scanning = Substring(line)
        while let open = scanning.range(of: "\\(") {
            var depth = 1
            var index = open.upperBound
            let start = index
            while index < scanning.endIndex, depth > 0 {
                if scanning[index] == "(" { depth += 1 }
                if scanning[index] == ")" { depth -= 1 }
                if depth > 0 { index = scanning.index(after: index) }
            }
            guard depth == 0 else { break }
            let expression = scanning[start..<index]
            if expression.lowercased().contains("email"),
               !expression.contains("AppLog.redact") {
                return true
            }
            scanning = scanning[scanning.index(after: index)...]
        }
        return false
    }
}
