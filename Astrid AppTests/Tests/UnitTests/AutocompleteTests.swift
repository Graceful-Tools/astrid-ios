import XCTest
import SwiftUI
@testable import Astrid_App

/// Unit tests for the shared autocomplete system (@mentions, #lists, !tasks)
final class AutocompleteTests: XCTestCase {

    // MARK: - Trigger Detection Tests

    /// One row per input: the trigger it opens (nil: none) and what is searched for.
    func testDetectAutocompleteTrigger() {
        let cases: [(text: String, type: AutocompleteItem.AutocompleteType?, search: String?)] = [
            ("hello @", .mention, ""),
            ("hello @ast", .mention, "ast"),
            ("add to #", .list, ""),
            ("add to #car", .list, "car"),
            ("see !buy", .task, "buy"),
            ("hello world", nil, nil),
            ("@jon", .mention, "jon"),                    // at the start of the text
            ("@jon hello", nil, nil),                      // a space closes the trigger
            ("email@test", nil, nil),                      // @ must follow whitespace
            ("line one\n@ast", .mention, "ast"),           // a newline counts as whitespace
            ("@jon mentioned #car", .list, "car"),         // the trigger nearest the end wins
        ]
        for (text, type, search) in cases {
            let result = detectAutocompleteTrigger(in: text)
            XCTAssertEqual(result?.type, type, text)
            XCTAssertEqual(result?.search, search, text)
        }
    }

    // MARK: - Reference Reconstruction Tests

    func testReconstructMention() {
        let refs = [InsertedReference(id: "user-123", type: .mention, displayText: "@Jon")]
        let result = reconstructReferencesInText("hello @Jon", references: refs)
        XCTAssertEqual(result, "hello @[Jon](user-123)")
    }

    func testReconstructList() {
        let refs = [InsertedReference(id: "list-abc", type: .list, displayText: "#Career")]
        let result = reconstructReferencesInText("add to #Career please", references: refs)
        XCTAssertEqual(result, "add to #[Career](list-abc) please")
    }

    func testReconstructTask() {
        let refs = [InsertedReference(id: "task-xyz", type: .task, displayText: "!Buy milk")]
        let result = reconstructReferencesInText("see !Buy milk for details", references: refs)
        XCTAssertEqual(result, "see ![Buy milk](task-xyz) for details")
    }

    func testReconstructMultipleReferences() {
        let refs = [
            InsertedReference(id: "user-1", type: .mention, displayText: "@Astrid"),
            InsertedReference(id: "list-2", type: .list, displayText: "#Career"),
        ]
        let result = reconstructReferencesInText("@Astrid add to #Career", references: refs)
        XCTAssertEqual(result, "@[Astrid](user-1) add to #[Career](list-2)")
    }

    func testReconstructNoReferences() {
        let result = reconstructReferencesInText("plain text", references: [])
        XCTAssertEqual(result, "plain text")
    }

    // MARK: - AutocompleteItem Tests

    func testAutocompleteItemTriggerChars() {
        let mention = AutocompleteItem(id: "1", type: .mention, label: "Jon", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(mention.triggerChar, "@")

        let list = AutocompleteItem(id: "2", type: .list, label: "Career", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(list.triggerChar, "#")

        let task = AutocompleteItem(id: "3", type: .task, label: "Buy milk", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(task.triggerChar, "!")
    }

    func testAutocompleteItemIcons() {
        let agent = AutocompleteItem(id: "1", type: .mention, label: "Astrid", secondaryLabel: nil, image: nil, isAIAgent: true, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(agent.icon, "sparkles")

        let person = AutocompleteItem(id: "2", type: .mention, label: "Jon", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(person.icon, "person.circle")

        let completedTask = AutocompleteItem(id: "3", type: .task, label: "Done", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: true)
        XCTAssertEqual(completedTask.icon, "checkmark.circle.fill")

        let incompleteTask = AutocompleteItem(id: "4", type: .task, label: "Todo", secondaryLabel: nil, image: nil, isAIAgent: false, isShared: false, privacy: nil, completed: false)
        XCTAssertEqual(incompleteTask.icon, "circle")
    }

    // MARK: - Colored Text Tests

    func testAttributedWithReferencesColorsAtMention() {
        let text = "@[Astrid](id123) hello"
        let attributed = text.attributedWithReferences(defaultColor: .black)
        // Should contain "Astrid" (without brackets/id) and "hello"
        let plainString = String(attributed.characters)
        XCTAssertTrue(plainString.contains("@Astrid"))
        XCTAssertTrue(plainString.contains("hello"))
        XCTAssertFalse(plainString.contains("id123"))
    }

    func testAttributedWithReferencesColorsHashList() {
        let text = "see #[Career](list-1) for tasks"
        let attributed = text.attributedWithReferences(defaultColor: .black)
        let plainString = String(attributed.characters)
        XCTAssertTrue(plainString.contains("#Career"))
        XCTAssertFalse(plainString.contains("list-1"))
    }

    func testAttributedWithReferencesBangTask() {
        let text = "check ![Buy milk](task-2)"
        let attributed = text.attributedWithReferences(defaultColor: .black)
        let plainString = String(attributed.characters)
        XCTAssertTrue(plainString.contains("!Buy milk"))
        XCTAssertFalse(plainString.contains("task-2"))
    }

    func testAttributedWithNoReferences() {
        let text = "plain text with no references"
        let attributed = text.attributedWithReferences(defaultColor: .black)
        let plainString = String(attributed.characters)
        XCTAssertEqual(plainString, text)
    }

    func testAttributedWithMultipleReferences() {
        let text = "@[Jon](u1) assigned #[Career](l1) task ![Report](t1)"
        let attributed = text.attributedWithReferences(defaultColor: .black)
        let plainString = String(attributed.characters)
        XCTAssertTrue(plainString.contains("@Jon"))
        XCTAssertTrue(plainString.contains("#Career"))
        XCTAssertTrue(plainString.contains("!Report"))
        XCTAssertFalse(plainString.contains("u1"))
        XCTAssertFalse(plainString.contains("l1"))
        XCTAssertFalse(plainString.contains("t1"))
    }

    // MARK: - InsertedReference Tests

    func testInsertedReferenceDisplayText() {
        let ref = InsertedReference(id: "abc", type: .mention, displayText: "@Astrid")
        XCTAssertEqual(ref.displayText, "@Astrid")
        XCTAssertEqual(ref.id, "abc")
    }

    // MARK: - Prune References Tests

    func testPruneRemovesDeletedReferences() {
        let refs = [
            InsertedReference(id: "1", type: .mention, displayText: "@Jon"),
            InsertedReference(id: "2", type: .list, displayText: "#Career"),
        ]
        let kept = pruneReferences(refs, to: "hello #Career")  // @Jon was deleted
        XCTAssertEqual(kept.map(\.id), ["2"])
    }

    func testPruneKeepsAllWhenPresent() {
        let refs = [
            InsertedReference(id: "1", type: .mention, displayText: "@Jon"),
            InsertedReference(id: "2", type: .list, displayText: "#Career"),
        ]
        let kept = pruneReferences(refs, to: "@Jon check #Career")
        XCTAssertEqual(kept.map(\.id), ["1", "2"], "order is kept, so references reconstruct in place")
    }

    /// The editors call this on every keystroke; deleting one character of a reference drops it,
    /// so the send does not link text the user has since edited (AITD-538).
    func testPruneDropsAReferenceWhoseTextWasEdited_AITD538() {
        let refs = [InsertedReference(id: "1", type: .task, displayText: "!Buy milk")]
        XCTAssertTrue(pruneReferences(refs, to: "!Buy mil").isEmpty)
        XCTAssertTrue(pruneReferences(refs, to: "").isEmpty)
    }
}
