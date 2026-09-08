//  DevServerConfigurationTests.swift
//  Task AITD-351 — one developer's home LAN IP was the on-device Debug server.
//
//  `Constants.Environment.development.baseURL` (non-simulator) and `ServerOption.localNetwork`
//  both carried `192.168.50.254:3000`, and `Info-Debug.plist`'s ATS exception carried
//  `192.168.50.161` — a DIFFERENT address, so the exception had not covered the one in use for
//  some time. A Debug build on anyone else's device, or on another network, pointed silently at
//  an unreachable host.
//
//  Release was never affected, so this is hygiene. The guard is what keeps it from returning.

import XCTest
@testable import Astrid_App

final class DevServerConfigurationTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Private address ranges, per RFC 1918. A literal from any of them in tracked source is one
    /// machine on one network, which is never right for everybody who clones the repository.
    private static let privateAddress = try! NSRegularExpression(
        pattern: #"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"#)

    private static let scannedRoots = ["Astrid App", "Astrid Mac", "Astrid", "Astrid AppTests"]
    private static let scannedFiles = ["Info.plist", "Info-Debug.plist"]

    func testNoTrackedFileHardcodesAPrivateNetworkAddress() throws {
        var offenders: [String] = []

        // This file is exempt, and has to be: it names the original addresses in its own
        // fixtures to prove the pattern matches them. Everything else is fair game.
        let selfName = URL(fileURLWithPath: #filePath).lastPathComponent

        func scan(_ url: URL, label: String) throws {
            guard url.lastPathComponent != selfName,
                  let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
            // Comment lines are stripped for Swift: an address mentioned while EXPLAINING a fix
            // is documentation, not configuration, and banning it would ban the explanation.
            let text = url.pathExtension == "swift"
                ? raw.split(separator: "\n", omittingEmptySubsequences: false)
                     .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                     .joined(separator: "\n")
                : raw
            let range = NSRange(text.startIndex..., in: text)
            for match in Self.privateAddress.matches(in: text, range: range) {
                guard let found = Range(match.range, in: text) else { continue }
                offenders.append("\(label): \(text[found])")
            }
        }

        for name in Self.scannedFiles {
            try scan(repositoryRoot.appendingPathComponent(name), label: name)
        }
        for root in Self.scannedRoots {
            let rootURL = repositoryRoot.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil)
            else { continue }
            for case let fileURL as URL in walker
            where ["swift", "plist"].contains(fileURL.pathExtension) {
                try scan(fileURL, label: "\(root)/\(fileURL.lastPathComponent)")
            }
        }

        XCTAssertEqual(
            offenders.sorted(), [],
            "A private-network address in tracked source names one machine on one network "
            + "(AITD-351). Use the ASTRID_DEV_SERVER_URL build setting for a dev host, or "
            + "192.0.2.x (TEST-NET-1, reserved for documentation) in a fixture:\n"
            + offenders.sorted().joined(separator: "\n")
        )
    }

    /// The guard is worth nothing if the pattern does not match the thing it was written for.
    func testTheGuardWouldHaveCaughtTheOriginal() {
        for address in ["http://192.168.50.254:3000", "192.168.50.161", "10.1.2.3", "172.20.0.5"] {
            let range = NSRange(address.startIndex..., in: address)
            XCTAssertNotNil(Self.privateAddress.firstMatch(in: address, range: range), address)
        }
    }

    /// TEST-NET-1 and real hosts must NOT trip it, or fixtures become impossible to write.
    func testTheGuardIgnoresDocumentationAndPublicAddresses() {
        for address in ["http://192.0.2.10:3000", "https://astrid.cc", "http://localhost:3000", "8.8.8.8"] {
            let range = NSRange(address.startIndex..., in: address)
            XCTAssertNil(Self.privateAddress.firstMatch(in: address, range: range), address)
        }
    }

    // MARK: - The fallback

    func testAnUnsetDevServerReadsAsAbsent() {
        // Nothing sets ASTRID_DEV_SERVER_URL in CI or on a fresh clone, so this is the default
        // state: no dev server, and the device Debug build falls back to production.
        XCTAssertNil(Constants.API.devServerURL,
                     "an undefined build setting expands to an empty string, which must read as "
                     + "'no dev server' rather than as a URL")
    }

    #if DEBUG
    func testTheDevServerRowIsHiddenWhenNoneIsConfigured() {
        XCTAssertFalse(Constants.API.ServerOption.available.contains(.devServer),
                       "an option that silently means 'production' is worse than no option")
        XCTAssertTrue(Constants.API.ServerOption.available.contains(.production))
        XCTAssertTrue(Constants.API.ServerOption.available.contains(.localhost))
    }
    #endif
}
