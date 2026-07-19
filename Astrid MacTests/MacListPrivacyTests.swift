//  MacListPrivacyTests.swift
//  Astrid for Mac — Task 7d77a054: list privacy + public-type payload.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListPrivacyTests: XCTestCase {

    func testPrivacyOptions() {
        XCTAssertEqual(MacListPrivacy.privacy.map(\.value), ["PRIVATE", "SHARED", "PUBLIC"])
        XCTAssertEqual(MacListPrivacy.publicType.map(\.value), ["collaborative", "copy_only"])
    }

    func testPublicTypeOnlyIncludedWhenPublic() {
        let priv = MacListPrivacy.updates(privacy: "PRIVATE", publicType: "collaborative")
        XCTAssertEqual(priv["privacy"] as? String, "PRIVATE")
        XCTAssertNil(priv["publicListType"], "publicListType only applies to public lists")

        let pub = MacListPrivacy.updates(privacy: "PUBLIC", publicType: "copy_only")
        XCTAssertEqual(pub["privacy"] as? String, "PUBLIC")
        XCTAssertEqual(pub["publicListType"] as? String, "copy_only")
    }
}
#endif
