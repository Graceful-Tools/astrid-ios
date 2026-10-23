//  MacAIKeysTests.swift
//  Astrid for Mac — Task f8687dfb: AI provider list + key status text.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAIKeysTests: XCTestCase {

    func testProviders() {
        XCTAssertEqual(MacAIKeys.providers.map(\.id), ["claude", "openai", "gemini"])
    }

    /// Rule 8 (AITD-537): the words come from keys that resolve; only the masked preview is literal.
    func testStatusTextReadsItsKeys_AITD537() {
        for key in ["mac.ai_keys.not_set", "mac.ai_keys.key_set", "mac.ai_keys.invalid"] {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, "\(key) is missing")
        }
        XCTAssertEqual(MacAIKeys.statusText(hasKey: false, preview: nil, isValid: nil),
                       NSLocalizedString("mac.ai_keys.not_set", comment: ""))
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: "aB1", isValid: true), "•••aB1")
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: "aB1", isValid: false),
                       String(format: NSLocalizedString("mac.ai_keys.invalid", comment: ""), "•••aB1"))
        XCTAssertEqual(MacAIKeys.statusText(hasKey: true, preview: nil, isValid: nil),
                       NSLocalizedString("mac.ai_keys.key_set", comment: ""))
    }
}
#endif
