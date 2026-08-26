//  MacTextSelectionStyleTests.swift
//  Astrid for Mac — Task 72d93f92: selected text must stay visible in task editors.

import XCTest
import AppKit
@testable import Astrid_Mac

#if os(macOS)
final class MacTextSelectionStyleTests: XCTestCase {
    func testSelectedTextAttributesAreVisible() {
        let attrs = MacTextSelectionStyle.selectedTextAttributes

        XCTAssertNotNil(attrs[.foregroundColor])
        XCTAssertNotNil(attrs[.backgroundColor])
    }
}
#endif
