//  ShareExtensionAppGroupTests.swift
//  Regression guard for the App Group mismatch found by the iOS monkey run on 2026-08-27.
//
//  `ShareDataManager` hands files and tasks between the app and the Share Extension through an
//  App Group container. The app was entitled to `group.gracefultools.astrid` — the registered
//  group — while the Share Extension's entitlements and this manager both named
//  `group.cc.astrid.app`. So the two halves used different containers, and the app was not
//  entitled to the one the extension wrote into. The extension and the constant moved to the
//  app's group; the app's entitlements were already right.
//
//  What that costs: `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil for an
//  unentitled group, so every read and write in ShareDataManager quietly did nothing. Share a
//  link or a file into Astrid and the extension wrote it to a container the app could not open.
//  It failed silently in the UI and loudly only in the system log, as
//  `container_create_or_lookup_app_group_path_by_app_group_identifier: client is not entitled` —
//  which is why it survived from the initial commit until a random-input run went looking at
//  what the app logged rather than at what it displayed.
//
//  These tests run in the unit-test target, which is HOSTED BY THE APP, so the app's real
//  entitlements are in force here. That is what makes this a genuine check rather than a
//  restatement of the constant.

import XCTest
@testable import Astrid_App

final class ShareExtensionAppGroupTests: XCTestCase {

    /// The app must be able to open the container the Share Extension writes into.
    ///
    /// Asserted through `ShareDataManager.appGroupIdentifier` rather than a literal, so the app
    /// and the test cannot drift apart the way the app and the extension did.
    func testAppIsEntitledToTheAppGroupTheShareExtensionUses() {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareDataManager.appGroupIdentifier)

        XCTAssertNotNil(container, """
            The app is not entitled to App Group "\(ShareDataManager.appGroupIdentifier)", so \
            everything the Share Extension writes is unreachable. Add it to \
            "Astrid App/Astrid App.entitlements" under com.apple.security.application-groups.
            """)
    }

    /// The two targets must name the SAME group. Entitlements are what the OS enforces, and they
    /// are edited in two separate files that nothing otherwise keeps in step.
    func testAppAndShareExtensionEntitlementsNameTheSameGroup() throws {
        let appGroups = try groups(inEntitlementsNamed: "Astrid App")
        let extensionGroups = try groups(inEntitlementsNamed: "ShareExtension")

        XCTAssertTrue(appGroups.contains(ShareDataManager.appGroupIdentifier),
                      "The app's entitlements should include \(ShareDataManager.appGroupIdentifier); they list \(appGroups)")
        XCTAssertTrue(extensionGroups.contains(ShareDataManager.appGroupIdentifier),
                      "The extension's entitlements should include \(ShareDataManager.appGroupIdentifier); they list \(extensionGroups)")
    }

    // MARK: - Private

    /// Reads an entitlements file from the SOURCE TREE.
    ///
    /// Deliberately iOS-only: a Mac test host shares the real app container and reaching into the
    /// repo through `#filePath` there has hung a suite before (see the Mac test-host notes). The
    /// runtime check above is the one that matters on both platforms; this one exists to say
    /// WHICH file is wrong when it fails.
    private func groups(inEntitlementsNamed name: String) throws -> [String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
        let url = repoRoot
            .appendingPathComponent(name)
            .appendingPathComponent("\(name).entitlements")

        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = plist as? [String: Any] ?? [:]
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}
