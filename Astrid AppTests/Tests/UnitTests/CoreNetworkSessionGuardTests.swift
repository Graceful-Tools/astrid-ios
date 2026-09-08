//  CoreNetworkSessionGuardTests.swift
//  Task AITD-338 — every request `Core` sends must go through the hardened session.
//
//  `URLSession.shared` is the shared, persistent cookie jar. Three separate protections were
//  silently skipped by anything that used it directly:
//    * `APIPathSafety.isSafeRequestPath`, the July audit's backstop, only ran at the two
//      URL-construction sites inside `AstridAPIClient`.
//    * `Constants.API.timeout` — `URLSession.shared` ignores it and stalls for the system
//      default (60 s request / 7 days resource).
//    * `UITestNetworkIsolation.harden` — `URLSession.shared` IS the jar that let a UI test act
//      as the real user, which is the whole reason that type exists.
//
//  `AstridHTTP` applies all three once. This guard is what keeps a new call site from opting out.

import XCTest
@testable import Astrid_App

final class CoreNetworkSessionGuardTests: XCTestCase {

    /// Walked for violations. `Core/Networking` is where the hardened session is BUILT, so it is
    /// the one place allowed to name `URLSession.shared` (it does not, but a future adapter might).
    ///
    /// AITD-353 widened this past `Core`. The original scope was the three files AITD-338 was
    /// about, but the rule was never meant to stop at that boundary: UI code that fetched its own
    /// attachments skipped the same timeout, the same path-safety backstop and the same UI-test
    /// cookie isolation, and did it in a view, which is an ASTRID.md §0 rule 1 problem on top.
    private static let guardedDirectories = [
        "Astrid App/Core",
        "Astrid App/Views",
        "Astrid App/Utilities",
        "Astrid App/ViewModels",
        "Astrid Mac",
    ]
    private static let exemptDirectory = "Astrid App/Core/Networking"

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testNoAppCodeUsesTheSharedURLSession() throws {
        let exemptURL = repositoryRoot.appendingPathComponent(Self.exemptDirectory)
        var violations: [String] = []

        for directory in Self.guardedDirectories {
            let directoryURL = repositoryRoot.appendingPathComponent(directory)
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil),
                "\(directory) is not there — the guard is walking nothing"
            )

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                guard !fileURL.path.hasPrefix(exemptURL.path) else { continue }
                // Comment lines stripped: a file explaining why `URLSession.shared` is wrong must
                // be allowed to name it. A guard a comment can trip is not guarding the code.
                let code = try String(contentsOf: fileURL, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                guard code.contains("URLSession.shared") else { continue }
                violations.append("\(directory)/\(fileURL.lastPathComponent)")
            }
        }

        XCTAssertEqual(
            violations.sorted(), [],
            "App code must send through AstridHTTP.session, not URLSession.shared — the shared "
            + "session has no timeout, no path-safety backstop, and IS the cookie jar "
            + "UITestNetworkIsolation exists to keep out of UI tests (AITD-338, AITD-353). "
            + "In a view, prefer a service method over a session:\n"
            + violations.sorted().joined(separator: "\n")
        )
    }

    /// A guard pointed at a directory that has been renamed passes forever while covering nothing.
    func testTheGuardedDirectoriesExist() {
        for directory in Self.guardedDirectories + [Self.exemptDirectory] {
            var isDirectory: ObjCBool = false
            let path = repositoryRoot.appendingPathComponent(directory).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                          "\(directory) is not there — the guard is walking nothing")
            XCTAssertTrue(isDirectory.boolValue, "\(directory) is not a directory")
        }
    }
}
