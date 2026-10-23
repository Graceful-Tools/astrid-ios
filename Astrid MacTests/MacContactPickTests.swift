//  MacContactPickTests.swift
//  Astrid for Mac — Task 3753a521: contact-suggestion display label.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacContactPickTests: XCTestCase {

    func testDisplayWithName() {
        let format = NSLocalizedString("mac.contact_pick.name_email", comment: "")
        XCTAssertNotEqual(format, "mac.contact_pick.name_email")  // AITD-537: read from a key
        XCTAssertEqual(MacContactPick.display(name: "Ada Lovelace", email: "ada@x.com"),
                       String(format: format, "Ada Lovelace", "ada@x.com"))
    }

    func testDisplayWithoutName() {
        XCTAssertEqual(MacContactPick.display(name: nil, email: "ada@x.com"), "ada@x.com")
        XCTAssertEqual(MacContactPick.display(name: "   ", email: "ada@x.com"), "ada@x.com")
    }
}
#endif
