//  MacUndoButtonTests.swift
//  Astrid for Mac — AITD-374: a visible Undo affordance, not just ⌘Z and the Edit menu.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacUndoButtonTests: XCTestCase {

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The toolbar carries Undo on purpose, and `MacListChrome` is where this app records what
    /// the toolbar does and does not hold — beside the two constants saying sort, filter and "+"
    /// were taken OUT of it.
    ///
    /// The reason those left was that they are ROW controls, and in 3-column mode the toolbar's
    /// trailing edge sits above the chat column. Undo is not a row control: it reverses the last
    /// action wherever it happened, which is the same thing the comment on Refresh says about
    /// Refresh — "the one control that DOES belong to the window rather than to the task list".
    func testTheToolbarDeliberatelyCarriesUndo_AITD374() {
        XCTAssertTrue(MacListChrome.toolbarOffersUndo)
        // Unchanged: this is an exception for a WINDOW control, not the row controls coming back.
        XCTAssertFalse(MacListChrome.toolbarOffersSortOrFilter)
        XCTAssertFalse(MacListChrome.toolbarOffersNewTask)
    }

    /// The button is live exactly when the task stack has something in it.
    func testTheButtonIsEnabledOnlyWithSomethingToUndo_AITD374() {
        XCTAssertTrue(MacUndoMenu.toolbarButtonIsEnabled(stackCanUndo: true))
        XCTAssertFalse(MacUndoMenu.toolbarButtonIsEnabled(stackCanUndo: false))
    }

    /// It names the action, from the SAME helper the Edit menu titles itself with — so the button
    /// and the menu item cannot come to call one action two things.
    func testTheButtonNamesTheActionLikeTheMenuDoes_AITD374() throws {
        let source = try String(contentsOf: repositoryRoot
            .appendingPathComponent("Astrid Mac/Views/MacUndoToolbarButton.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("undo.undoTitle"),
                      "the toolbar button must take its title from the shared undo title")
        XCTAssertTrue(source.contains("MacUndoCoordinator.shared.performUndo()"),
                      "…and perform undo through the coordinator, not its own path")

        // And MacRootView actually places it, gated on the recorded exception.
        let root = try String(contentsOf: repositoryRoot
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains("MacUndoToolbarButton()"),
                      "the window toolbar must carry the button")
    }

    /// The Edit menu's Undo must stay ENABLED even with an empty task stack, and this is the
    /// test that says so on purpose rather than by omission.
    ///
    /// `performUndo` hands ⌘Z to a focused text field whenever the task stack is empty. Gating
    /// the menu item on `canUndo` would therefore kill ⌘Z while typing — and the honest gate,
    /// asking whether the field editor can undo, is not available where the menu is assembled:
    /// `MacUndoCoordinator` records that reading `NSApp.keyWindow` there wedges the app at
    /// launch. So "greying out Undo when there is nothing to undo" is a plausible polish that
    /// would be a bug, and it should fail here rather than in someone's text field.
    func testTheEditMenuUndoIsNotDisabledOnAnEmptyStack_AITD374() throws {
        let source = try String(contentsOf: repositoryRoot
            .appendingPathComponent("Astrid Mac/App/AstridCommands.swift"), encoding: .utf8)
        for banned in [".disabled(!undo.canUndo)", ".disabled(!undo.canRedo)",
                       ".disabled(!MacUndoCoordinator.shared.canUndo)"] {
            XCTAssertFalse(source.contains(banned),
                           "Edit ▸ Undo must stay enabled so ⌘Z still reaches a focused text field")
        }
    }

    /// The routing rule the above depends on, asserted directly.
    func testAnEmptyStackHandsTheKeystrokeToTheFieldEditor() {
        XCTAssertEqual(MacUndoMenu.target(fieldEditorCanUndo: true, stackCanUndo: false), .fieldEditor)
        XCTAssertEqual(MacUndoMenu.target(fieldEditorCanUndo: true, stackCanUndo: true), .stack)
        XCTAssertEqual(MacUndoMenu.target(fieldEditorCanUndo: false, stackCanUndo: false), .none)
    }
}
#endif
