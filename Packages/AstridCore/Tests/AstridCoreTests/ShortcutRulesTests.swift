import AstridCore
import XCTest

/// AITD-655 (AITD-621): what a bare key press does, through the rule door (core
/// `keyboard::action_for`), replacing the Mac's own guard in `KeyboardShortcutHandler`.
final class ShortcutRulesTests: XCTestCase {

    func testAITD655_aBoundKeyNamesItsAction_andAliasesAnswerTheSame() throws {
        XCTAssertEqual(try CoreRules.shortcut(key: "n")?.action, "newTask")
        XCTAssertEqual(try CoreRules.shortcut(key: "j")?.action, "selectNext")
        XCTAssertEqual(try CoreRules.shortcut(key: "↓")?.action, "selectNext")
        XCTAssertEqual(try CoreRules.shortcut(key: "Backspace", hasSelection: true)?.action, "deleteTask")
        XCTAssertNil(try CoreRules.shortcut(key: "z"), "an unbound key does nothing")
    }

    func testAITD655_theGuardsArePartOfTheAnswer() throws {
        XCTAssertNil(try CoreRules.shortcut(key: "x"), "x needs a selected task")
        XCTAssertEqual(try CoreRules.shortcut(key: "x", hasSelection: true)?.action, "completeTask")
        XCTAssertNil(try CoreRules.shortcut(key: "n", isTextFieldFocused: true), "typing is text")
        XCTAssertNil(try CoreRules.shortcut(key: "n", isModalPresented: true), "a modal swallows keys")
    }
}
