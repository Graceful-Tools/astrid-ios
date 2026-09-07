//  UIServiceBoundaryGuardTests.swift
//  ASTRID.md §0 rule 1: backend calls go through the service layer, never straight from a view.
//
//  Task 698717b9 (AITD-319) widened this to the Mac target. It used to walk `Astrid App/` only,
//  which is why `MacRootView.loadPublicLists` could call `AstridAPIClient.shared` directly and
//  survive review — the guard that exists to catch exactly that could not see the file.

import XCTest

final class UIServiceBoundaryGuardTests: XCTestCase {

    /// Every directory holding UI or utility code, on either platform.
    ///
    /// Adding a target here is the whole point: a rule enforced on one target and not the other is
    /// a rule that gets broken on the other one.
    private static let protectedDirectories = [
        "Astrid App/Views",
        "Astrid App/ViewModels",
        "Astrid App/Utilities",
        "Astrid Mac/App",
        "Astrid Mac/Views",
    ]

    private static let forbidden = ["APIClient.shared", "AstridAPIClient.shared"]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testViewsAndViewModelsDoNotAccessNetworkClientsDirectly() throws {
        var violations: [String] = []

        for directory in Self.protectedDirectories {
            let directoryURL = repositoryRoot.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else { continue }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for token in Self.forbidden where source.contains(token) {
                    violations.append("\(directory)/\(fileURL.lastPathComponent): \(token)")
                }
            }
        }

        XCTAssertEqual(
            violations,
            [],
            "UI and utility code must call domain services, not network clients:\n\(violations.joined(separator: "\n"))"
        )
    }

    /// The guard is only worth what it covers, and the Mac gap is how AITD-319 happened. If a
    /// directory listed above stops existing — renamed, moved — the walk above silently skips it
    /// and the suite still passes, so assert the paths are real.
    func testEveryProtectedDirectoryActuallyExists() throws {
        for directory in Self.protectedDirectories {
            var isDirectory: ObjCBool = false
            let path = repositoryRoot.appendingPathComponent(directory).path

            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                          "\(directory) is not there — the guard is walking nothing")
            XCTAssertTrue(isDirectory.boolValue, "\(directory) is not a directory")
        }
    }

    /// Both app targets are covered, not just iOS.
    func testTheMacTargetIsCovered() {
        XCTAssertTrue(Self.protectedDirectories.contains { $0.hasPrefix("Astrid Mac/") },
                      "the Mac target must be walked too — a rule enforced on one target only "
                      + "is a rule that gets broken on the other (AITD-319)")
    }
}
