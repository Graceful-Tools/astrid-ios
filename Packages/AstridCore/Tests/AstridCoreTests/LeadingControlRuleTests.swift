import AstridCore
import XCTest

/// AITD-622 / AITD-656 / AITD-672: the leading control is the core's row projection, which
/// follows iOS since core e0d8ce7 (AWTD2-214).
final class LeadingControlRuleTests: XCTestCase {

    private func answer(_ assignee: String?, me: String? = "me", mode: String = "list",
                        on surface: String = "listRow") -> LeadingControlAnswer? {
        CoreRules.leadingControl(assigneeId: assignee, currentUserId: me,
                                 displayMode: mode, surface: surface)
    }

    func testAITD622_yourTaskInListModeIsACheckboxThatCompletes() {
        XCTAssertEqual(answer("me"), .init(kind: .checkbox, action: .complete))
        XCTAssertEqual(answer("me", on: "detail"), .init(kind: .checkbox, action: .complete))
    }

    func testAITD622_yourTaskInProjectModeIsYourFaceAndOpensThePicker() {
        XCTAssertEqual(answer("me", mode: "project"), .init(kind: .avatar("me"), action: .openPicker))
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
}
