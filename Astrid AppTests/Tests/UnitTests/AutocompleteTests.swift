import XCTest
import SwiftUI
@testable import Astrid_App

/// Unit tests for the shared autocomplete system (@mentions, #lists, !tasks)
final class AutocompleteTests: XCTestCase {

    // MARK: - Trigger Detection Tests

    func testDetectAtMentionTrigger() {
        let result = detectAutocompleteTrigger(in: "hello @")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .mention)
        XCTAssertEqual(result?.search, "")
    }

    func testDetectAtMentionWithSearch() {
        let result = detectAutocompleteTrigger(in: "hello @ast")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .mention)
        XCTAssertEqual(result?.search, "ast")
    }

    func testDetectHashListTrigger() {
        let result = detectAutocompleteTrigger(in: "add to #")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .list)
        XCTAssertEqual(result?.search, "")
    }

    func testDetectHashListWithSearch() {
        let result = detectAutocompleteTrigger(in: "add to #car")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .list)
        XCTAssertEqual(result?.search, "car")
    }

    func testDetectBangTaskTrigger() {
        let result = detectAutocompleteTrigger(in: "see !buy")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .task)
        XCTAssertEqual(result?.search, "buy")
    }

    func testNoTriggerInPlainText() {
        let result = detectAutocompleteTrigger(in: "hello world")
        XCTAssertNil(result)
    }

    func testTriggerAtStartOfText() {
        let result = detectAutocompleteTrigger(in: "@jon")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .mention)
        XCTAssertEqual(result?.search, "jon")
    }

    func testTriggerClosedBySpace() {
        // "@jon " has a space after — trigger is closed
        let result = detectAutocompleteTrigger(in: "@jon hello")
        XCTAssertNil(result)
    }

    func testTriggerRequiresWhitespaceBefore() {
        // "email@test" — @ not preceded by whitespace, should not trigger
        let result = detectAutocompleteTrigger(in: "email@test")
        XCTAssertNil(result)
    }

    func testTriggerAfterNewline() {
        let result = detectAutocompleteTrigger(in: "line one\n@ast")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .mention)
        XCTAssertEqual(result?.search, "ast")
    }

    func testMostRecentTriggerWins() {
        // Multiple triggers — closest to end wins
        let result = detectAutocompleteTrigger(in: "@jon mentioned #car")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, .list)
        XCTAssertEqual(result?.search, "car")
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
        var refs = [
            InsertedReference(id: "1", type: .mention, displayText: "@Jon"),
            InsertedReference(id: "2", type: .list, displayText: "#Career"),
        ]
        let text = "hello #Career"  // @Jon was deleted
        refs.removeAll { ref in !text.contains(ref.displayText) }
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs.first?.displayText, "#Career")
    }

    func testPruneKeepsAllWhenPresent() {
        var refs = [
            InsertedReference(id: "1", type: .mention, displayText: "@Jon"),
            InsertedReference(id: "2", type: .list, displayText: "#Career"),
        ]
        let text = "@Jon check #Career"
        refs.removeAll { ref in !text.contains(ref.displayText) }
        XCTAssertEqual(refs.count, 2)
    }
}
