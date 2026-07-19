//  MacAIKeysTests.swift
//  Astrid for Mac — Task f8687dfb: AI provider list + key status text.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAIKeysTests: XCTestCase {

    func testProviders() {
        XCTAssertEqual(MacAIKeys.providers.map(\.id), ["claude", "openai", "gemini"])
    }

    func testStatusText() {
        XCTAssertEqual(MacAIKeys.statusText(hasKey: false, preview: nil, isValid: nil), "Not set")
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: "aB1", isValid: true), "•••aB1")
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: "aB1", isValid: false), "•••aB1 — invalid")
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: nil, isValid: nil), "Key set")
    }
}
#endif
