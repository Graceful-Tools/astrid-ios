//  PrivacyManifestGuardTests.swift
//  Task AITD-350 — the Mac target shipped with no PrivacyInfo.xcprivacy.
//
//  `Astrid App/PrivacyInfo.xcprivacy` declares the required-reason APIs the shared `Core/` tree
//  uses. The Mac target compiles that same tree — it makes the same UserDefaults reads and the
//  same file-attribute calls — but the manifest was named in the Mac target's membership
//  EXCEPTIONS, so the file was explicitly excluded from the Mac bundle. The Mac app therefore
//  described none of it.
//
//  The fix is one shared file rather than a second copy, so the two bundles cannot describe
//  different things. These tests defend that: the exclusion must stay gone, and the declarations
//  must still cover what `Core/` actually does.

import XCTest

final class PrivacyManifestGuardTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func manifest() throws -> [String: Any] {
        let url = repositoryRoot.appendingPathComponent("Astrid App/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "PrivacyInfo.xcprivacy is not a plist dict")
    }

    /// The declared API categories, whatever order they appear in.
    private func declaredCategories() throws -> Set<String> {
        let types = try XCTUnwrap(
            manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "no NSPrivacyAccessedAPITypes array"
        )
        return Set(types.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
    }

    // MARK: - The regression (AITD-350)

    func testTheMacTargetIsNotExcludedFromThePrivacyManifest() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Astrid App.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        // The Mac target consumes the "Astrid App" folder as a synchronized group — that is how it
        // gets `Core/`. Anything listed in its membershipExceptions is deliberately kept OUT.
        let marker = #"Exceptions for "Astrid App" folder in "Astrid Mac" target"#
        let start = try XCTUnwrap(project.range(of: marker),
                                  "the Mac exception set is gone — this guard is reading nothing")
        let rest = project[start.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "};"), "malformed exception set")
        let exceptions = String(rest[..<end.lowerBound])

        XCTAssertFalse(exceptions.contains("PrivacyInfo.xcprivacy"),
                       "the Mac target must SHIP the privacy manifest, not exclude it. It links "
                       + "the same Core/ tree and makes the same UserDefaults and file-timestamp "
                       + "calls, so a bundle without the manifest describes none of them "
                       + "(AITD-350).")
    }

    // MARK: - The declarations still match what Core/ does

    func testTheManifestDeclaresUserDefaultsAndFileTimestampAccess() throws {
        XCTAssertEqual(
            try declaredCategories(),
            ["NSPrivacyAccessedAPICategoryUserDefaults",
             "NSPrivacyAccessedAPICategoryFileTimestamp"],
            "Core/ reads UserDefaults and file attributes on both platforms; both need a reason"
        )
    }

    func testEveryDeclaredCategoryCarriesAtLeastOneReason() throws {
        let types = try XCTUnwrap(manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        for type in types {
            let name = type["NSPrivacyAccessedAPIType"] as? String ?? "(unnamed)"
            let reasons = type["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            XCTAssertFalse(reasons.isEmpty,
                           "\(name) is declared with no reason code — Apple rejects that (ITMS-91053)")
        }
    }

    func testTheAppDoesNotClaimToTrackUsers() throws {
        XCTAssertEqual(try manifest()["NSPrivacyTracking"] as? Bool, false)
    }
}
