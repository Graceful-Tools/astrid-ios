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
    private static let guardedDirectory = "Astrid App/Core"
    private static let exemptDirectory = "Astrid App/Core/Networking"

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCoreNeverUsesTheSharedURLSession() throws {
        let directoryURL = repositoryRoot.appendingPathComponent(Self.guardedDirectory)
        let exemptURL = repositoryRoot.appendingPathComponent(Self.exemptDirectory)

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: nil),
            "\(Self.guardedDirectory) is not there — the guard is walking nothing"
        )

        var violations: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard !fileURL.path.hasPrefix(exemptURL.path) else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            guard source.contains("URLSession.shared") else { continue }
            violations.append(fileURL.lastPathComponent)
        }

        XCTAssertEqual(
            violations.sorted(), [],
            "Core code must send through AstridHTTP.session, not URLSession.shared — the shared "
            + "session has no timeout, no path-safety backstop, and IS the cookie jar "
            + "UITestNetworkIsolation exists to keep out of UI tests (AITD-338):\n"
            + violations.sorted().joined(separator: "\n")
        )
    }

    /// A guard pointed at a directory that has been renamed passes forever while covering nothing.
    func testTheGuardedDirectoriesExist() {
        for directory in [Self.guardedDirectory, Self.exemptDirectory] {
            var isDirectory: ObjCBool = false
            let path = repositoryRoot.appendingPathComponent(directory).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                          "\(directory) is not there — the guard is walking nothing")
            XCTAssertTrue(isDirectory.boolValue, "\(directory) is not a directory")
        }
    }
}
