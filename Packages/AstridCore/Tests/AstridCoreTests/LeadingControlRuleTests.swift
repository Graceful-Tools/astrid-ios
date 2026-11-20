import AstridCore
import XCTest

/// AITD-622 / AITD-656 / AITD-672: the leading control is the core's row projection, which
/// follows iOS since core e0d8ce7 (AWTD2-214).
final class LeadingControlRuleTests: XCTestCase {

    private func answer(_ assignee: String?, me: String? = "me",
                        on surface: String = "listRow", completed: Bool = false) -> LeadingControlAnswer? {
        CoreRules.leadingControl(assigneeId: assignee, currentUserId: me, surface: surface,
                                 completed: completed)
    }

    func testAITD622_ADEV72_yourTaskIsACheckboxThatCompletes() {
        XCTAssertEqual(answer("me"), .init(kind: .checkbox, action: .complete))
        XCTAssertEqual(answer("me", on: "detail"), .init(kind: .checkbox, action: .complete))
    }

    func testAITD375_someoneElsesTaskOpensThePickerOnEverySurface() {
        for surface in ["listRow", "boardCard", "detail"] {
            XCTAssertEqual(answer("them", on: surface), .init(kind: .avatar("them"), action: .openPicker),
                           surface)
        }
    }

    func testAITD382_nobodysTaskOpensThePicker_emptyIsNobody() {
        XCTAssertEqual(answer(nil), .init(kind: .unassigned, action: .openPicker))
        XCTAssertEqual(answer(""), .init(kind: .unassigned, action: .openPicker))
    }

    func testAITD622_aBoardCardNeverCompletes_evenYourOwn() {
        XCTAssertEqual(answer("me", on: "boardCard"), .init(kind: .checkbox, action: .openPicker))
    }

    func testAITD375_nobodySignedInMakesEveryAssignedTaskSomeoneElses() {
        XCTAssertEqual(answer("me", me: nil), .init(kind: .avatar("me"), action: .openPicker))
    }

    // MARK: - ADEV-147: a completed task shows its check mark, whoever holds it

    /// The default completion filter must not drop the one completed row asked about.
    func testADEV147_aCompletedTaskIsStillAnswered() {
        XCTAssertNotNil(answer("them", completed: true))
        XCTAssertNotNil(answer(nil, completed: true))
    }

    /// Someone else's completed task draws the checked box, but tapping it still opens the
    /// picker (AITD-375) rather than reopening a task that is not yours.
    func testADEV147_someoneElsesCompletedTaskIsACheckboxThatOpensThePicker() {
        for surface in ["listRow", "boardCard", "detail"] {
            XCTAssertEqual(answer("them", on: surface, completed: true),
                           .init(kind: .checkbox, action: .openPicker), surface)
        }
    }

    /// Nobody's finished task is the checked box, and on a list row a tap puts it back: reopening
    /// takes nothing from anyone, so it never asks (core `contracts/fixtures/leading-control.json`).
    /// A board card still opens the picker.
    func testADEV147_nobodysCompletedTaskIsACheckbox() {
        XCTAssertEqual(answer(nil, completed: true), .init(kind: .checkbox, action: .complete))
        XCTAssertEqual(answer(nil, on: "boardCard", completed: true), .init(kind: .checkbox, action: .openPicker))
    }

    func testADEV147_yourCompletedTaskIsUnchanged() {
        XCTAssertEqual(answer("me", completed: true), .init(kind: .checkbox, action: .complete))
    }

    /// An open task is untouched by ADEV-147.
    func testADEV147_anOpenTaskStillShowsWhoseItIs() {
        XCTAssertEqual(answer("them", completed: false), .init(kind: .avatar("them"), action: .openPicker))
    }
}
