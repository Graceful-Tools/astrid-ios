//  MacDraftDefaultsPickerTests.swift
//  Regression guard for the second half of AITD-387 — the ⌥Space quick-add window "should have
//  all the same options as the add task input".
//
//  It had none: a text field and an Add button. So the same act — type a task, press Return —
//  offered priority and assignee at the bottom of a list and nothing at all from the global
//  window, which is the sort of difference you only discover by missing it.
//
//  The picker was a private @ViewBuilder inside MacRootView. These tests cover the pure half that
//  came out with it, plus the thing a unit test can actually check about the views: that there is
//  still only ONE picker. Two copies drifting apart is the failure mode ASTRID.md rule 8 names,
//  and it is invisible to the compiler.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacDraftDefaultsPickerTests: XCTestCase {

    private let me = "u-me"

    // MARK: - What the default row says

    /// With no list the default is YOU, and the row has to say so.
    ///
    /// The obvious guess is "Unassigned" — no list, no default. It is wrong:
    /// `NewTaskDefaults.assignee(nil, …)` is "task_creator", which is the same answer a real list
    /// gives when it names no assignee of its own, so the task really does start as yours
    /// (AITD-387). A row reading "Unassigned" above a task that arrives assigned to you is the
    /// kind of small lie that makes people stop trusting the picker.
    func testWithNoListTheDefaultIsYou() {
        let label = MacDraftDefaults.defaultAssigneeLabel(defaultAssigneeId: nil,
                                                          currentUserId: me, members: [])
        XCTAssertEqual(label, NSLocalizedString("lists.me", comment: ""))
    }

    /// Signed out there is no creator to fall back to, so it really is unassigned.
    func testWithNoListAndNoUserTheDefaultIsUnassigned() {
        let label = MacDraftDefaults.defaultAssigneeLabel(defaultAssigneeId: nil,
                                                          currentUserId: nil, members: [])
        XCTAssertEqual(label, NSLocalizedString("assignee.unassigned", comment: ""))
    }

    /// A list that defaults to you says "Me", not your user id.
    func testAListDefaultingToYouSaysMe() {
        let label = MacDraftDefaults.defaultAssigneeLabel(defaultAssigneeId: me,
                                                          currentUserId: me, members: [])
        XCTAssertEqual(label, NSLocalizedString("lists.me", comment: ""))
    }

    /// Somebody else's name, when we can actually name them.
    func testAListDefaultingToSomeoneElseNamesThem() {
        let label = MacDraftDefaults.defaultAssigneeLabel(
            defaultAssigneeId: "u-sam", currentUserId: me,
            members: [MacAssigneeChoice(id: "u-sam", label: "Sam")])
        XCTAssertEqual(label, "Sam")
    }

    // MARK: - Who the picker offers

    /// In a list, its members.
    func testAListOffersItsMembers() {
        let members = [MacAssigneeChoice(id: "u-sam", label: "Sam"),
                       MacAssigneeChoice(id: me, label: "Jon")]
        XCTAssertEqual(MacDraftDefaults.assigneeChoices(members: members, currentUserId: me,
                                                        hasList: true),
                       members)
    }

    /// Without a list there is no membership to draw names from — but "this one is mine" is the
    /// whole point of having the option there, so you are offered.
    func testWithNoListYouAreStillOffered() {
        let choices = MacDraftDefaults.assigneeChoices(members: [], currentUserId: me,
                                                        hasList: false)
        XCTAssertEqual(choices.map(\.id), [me],
                       "AITD-387: My Tasks must still let you assign the task to yourself")
    }

    /// Signed out, the picker offers nobody rather than a row with an empty id that would
    /// silently assign the task to "".
    func testWithNoListAndNoUserNobodyIsOffered() {
        XCTAssertTrue(MacDraftDefaults.assigneeChoices(members: [], currentUserId: nil,
                                                        hasList: false).isEmpty)
        XCTAssertTrue(MacDraftDefaults.assigneeChoices(members: [], currentUserId: "",
                                                        hasList: false).isEmpty)
    }

    // MARK: - One picker, not two

    /// Both surfaces must USE the shared picker rather than build their own. This is the check the
    /// compiler cannot do: a second hand-rolled VStack of the same controls compiles perfectly and
    /// then drifts.
    func testBothQuickAddSurfacesUseTheSharedPicker() throws {
        for path in ["Astrid Mac/App/MacRootView.swift",
                     "Astrid Mac/Support/QuickEntryView.swift"] {
            XCTAssertTrue(try Self.source(of: path).contains("MacDraftDefaultsPicker("),
                          "\(path): AITD-387 — the options popover is shared, not re-made here")
        }
    }

    /// The quick-add window must pass the overrides on. Building the picker and then dropping what
    /// the user chose would look right on screen and create the wrong task.
    func testTheQuickAddWindowSendsItsOverridesToTheTask() throws {
        let source = try Self.source(of: "Astrid Mac/Support/QuickEntryView.swift")
        XCTAssertTrue(source.contains("priorityOverride: priorityOverride"),
                      "AITD-387: the chosen priority must reach makeGlobalArgs")
        XCTAssertTrue(source.contains("\"unassigned\" ? nil :"),
                      "AITD-387: an explicit nobody is not a missing value")
    }

    private static func source(of path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
#endif
