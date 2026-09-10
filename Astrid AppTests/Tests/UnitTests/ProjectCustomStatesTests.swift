import XCTest
@testable import Astrid_App

/// Task AITD-379 — "Port custom board states to `Project.customStates` — iOS
/// still reads them from deleted status-list rows."
///
/// iOS built a board's custom columns by scanning project-scoped
/// `listType: "status"` rows. Web's migration `20260821000000_drop_status_lists`
/// deleted every one of those rows, so that scan iterated an empty array and
/// **iOS rendered no custom column at all** — only the config-backed defaults.
/// The degradation was graceful (a card whose custom role matched no column
/// fell to Inbox rather than vanishing), which is exactly why it was silent.
///
/// Web moved the same feature onto `Project.customStates` in b346e377 /
/// 9ddf4a6f. This is the iOS half. `lib/task-status.ts#parseCustomStates` is
/// the canonical spec for the parse and `lib/project-status.ts` for the
/// columns; if these diverge, the two platforms render the same board
/// differently and that is a bug.
final class ProjectCustomStatesTests: XCTestCase {

    private let project = "p1"

    private func domainList() -> TaskList {
        var list = TaskList(id: "domain-1", name: "Work")
        list.listType = "list"
        list.projectId = project
        return list
    }

    /// A row of the kind the migration deleted, still sitting in a client's cache.
    private func staleStatusRow(_ role: String, _ id: String, _ name: String,
                                order: Int = 0, projectId: String? = nil) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.listType = "status"
        list.statusRole = role
        list.statusOrder = order
        list.projectId = projectId
        return list
    }

    private func task(statusRole: String?, completed: Bool = false) -> Task {
        var t = Task(id: "t1", title: "Card", description: "", creatorId: "u1")
        t.statusRole = statusRole
        t.listIds = ["domain-1"]
        t.completed = completed
        return t
    }

    private func state(_ role: String, _ name: String,
                       description: String? = nil, order: Int? = nil) -> ProjectCustomState {
        ProjectCustomState(role: role, name: name, description: description, order: order)
    }

    // MARK: - The acceptance criteria

    func testACustomStateOnTheProjectRendersAsAColumn() {
        let columns = getProjectBoardColumns(
            [domainList()],
            customStates: [state("blocked", "Blocked", order: 0)]
        )

        XCTAssertEqual(columns.map(\.name), ["Inbox", "Ready", "Doing", "Waiting", "Blocked", "Done"])
    }

    func testACustomColumnsIdIsItsRole() {
        // Task e5c74b5e's rule survives the change of source: the id is the
        // ROLE, never a row id, so the board's shape never depends on a cache.
        let columns = getProjectBoardColumns(
            [domainList()],
            customStates: [state("blocked", "Blocked", order: 0)]
        )

        XCTAssertEqual(columns.first { $0.name == "Blocked" }?.id, "blocked")
    }

    func testACardWithACustomRoleLandsInThatColumn() {
        let customStates = [state("blocked", "Blocked", order: 0)]
        let columns = getProjectBoardColumns([domainList()], customStates: customStates)

        let resolved = getTaskProjectColumnId(task(statusRole: "blocked"),
                                              lists: [domainList()],
                                              customStates: customStates)

        XCTAssertEqual(resolved, "blocked")
        XCTAssertTrue(columns.contains { $0.id == resolved },
                      "Card resolved to a column the board does not render")
    }

    func testACustomRoleTheBoardDoesNotDeclareStillFallsToInbox() {
        // Showing a card in the wrong column is recoverable; losing it is not.
        // Reachable whenever a board's customStates have not loaded yet.
        XCTAssertEqual(
            getTaskProjectColumnId(task(statusRole: "nowhere"),
                                   lists: [domainList()],
                                   customStates: [state("blocked", "Blocked", order: 0)]),
            VIRTUAL_INBOX_COLUMN_ID
        )
    }

    func testEveryResolvedColumnIdIsOneTheBoardRenders() {
        let customStates = [state("blocked", "Blocked", order: 0)]
        let columnIds = Set(getProjectBoardColumns([domainList()], customStates: customStates).map(\.id))

        for role in ["ready", "doing", "waiting", "blocked", "nowhere"] {
            let resolved = getTaskProjectColumnId(task(statusRole: role),
                                                  lists: [domainList()],
                                                  customStates: customStates)
            XCTAssertTrue(columnIds.contains(resolved),
                          "Role \(role) resolved to \"\(resolved)\", which is not a rendered column")
        }
    }

    func testNoCustomStatesMeansJustTheDefaults() {
        XCTAssertEqual(
            getProjectBoardColumns([domainList()], customStates: nil).map(\.name),
            ["Inbox", "Ready", "Doing", "Waiting", "Done"]
        )
    }

    // MARK: - The rows are no longer a source

    func testAStaleStatusRowNoLongerProducesACustomColumn() {
        // The whole point of the port. The rows are deleted server-side; a
        // client still holding one must not invent a column from it, or two
        // clients disagree about the shape of the same board.
        let blocked = staleStatusRow("custom-blocked", "l-blocked", "Blocked",
                                     order: 5, projectId: project)

        let columns = getProjectBoardColumns([domainList(), blocked], customStates: nil)

        XCTAssertEqual(columns.map(\.name), ["Inbox", "Ready", "Doing", "Waiting", "Done"])
    }

    func testTheBoardIsIdenticalWithAndWithoutStaleRows() {
        let customStates = [state("blocked", "Blocked", order: 0)]
        let withRows = getProjectBoardColumns(
            [domainList(),
             staleStatusRow("ready", "l-ready", "Ready"),
             staleStatusRow("custom-blocked", "l-blocked", "Blocked", order: 5, projectId: project)],
            customStates: customStates
        )
        let withoutRows = getProjectBoardColumns([domainList()], customStates: customStates)

        XCTAssertEqual(withRows.map(\.id), withoutRows.map(\.id))
    }

    // MARK: - parseProjectCustomStates — the port of web's parseCustomStates

    func testParseDropsEntriesMissingARoleOrAName() {
        let parsed = parseProjectCustomStates([
            state("", "No role"),
            state("no-name", ""),
            state("   ", "Blank role"),
            state("blocked", "Blocked"),
        ])

        XCTAssertEqual(parsed.map(\.role), ["blocked"])
    }

    func testParseTrimsRoleAndName() {
        let parsed = parseProjectCustomStates([state("  blocked  ", "  Blocked  ")])

        XCTAssertEqual(parsed.first?.role, "blocked")
        XCTAssertEqual(parsed.first?.name, "Blocked")
    }

    func testParseKeepsTheFirstEntryForARepeatedRole() {
        let parsed = parseProjectCustomStates([
            state("blocked", "First", order: 0),
            state("blocked", "Second", order: 1),
        ])

        XCTAssertEqual(parsed.map(\.name), ["First"])
    }

    func testParseSortsByOrder() {
        let parsed = parseProjectCustomStates([
            state("c", "Third", order: 2),
            state("a", "First", order: 0),
            state("b", "Second", order: 1),
        ])

        XCTAssertEqual(parsed.map(\.name), ["First", "Second", "Third"])
    }

    func testParseFallsBackToInsertionOrderWhenOrderIsAbsent() {
        let parsed = parseProjectCustomStates([
            state("a", "First"),
            state("b", "Second"),
            state("c", "Third"),
        ])

        XCTAssertEqual(parsed.map(\.name), ["First", "Second", "Third"])
    }

    func testCustomColumnsRenderInTheirParsedOrder() {
        let columns = getProjectBoardColumns([domainList()], customStates: [
            state("shipped", "Shipped", order: 1),
            state("blocked", "Blocked", order: 0),
        ])

        XCTAssertEqual(columns.map(\.name),
                       ["Inbox", "Ready", "Doing", "Waiting", "Blocked", "Shipped", "Done"])
    }

    // MARK: - A default role in customStates is a NAME OVERRIDE, not a column

    func testADefaultRoleInCustomStatesRenamesItRatherThanAddingAColumn() {
        // Web stores a renamed built-in in the same array and tells the two
        // apart with `isDefaultStatusRole` (lib/task-status.ts). Treating it as
        // a custom state instead would render "Ready" twice.
        let columns = getProjectBoardColumns([domainList()],
                                             customStates: [state("ready", "Backlog", order: 0)])

        XCTAssertEqual(columns.map(\.name), ["Inbox", "Backlog", "Doing", "Waiting", "Done"])
        XCTAssertEqual(columns.first { $0.name == "Backlog" }?.id, "ready")
    }

    func testARenameOverrideBeatsAStaleRowsName() {
        // Both sources can be present on a client that was open across the
        // deploy. The durable one wins.
        let renamedRow = staleStatusRow("ready", "l-ready", "From the row")
        let columns = getProjectBoardColumns([domainList(), renamedRow],
                                             customStates: [state("ready", "From customStates", order: 0)])

        XCTAssertEqual(columns.first { $0.id == "ready" }?.name, "From customStates")
    }

    // MARK: - Decoding `Project.customStates`

    private func decodeProject(_ json: String) throws -> Project {
        try JSONDecoder().decode(Project.self, from: Data(json.utf8))
    }

    func testDecodesCustomStatesFromTheProjectPayload() throws {
        let project = try decodeProject("""
        {"id":"p1","name":"Board",
         "customStates":[{"role":"blocked","name":"Blocked","description":"Stuck","order":0}]}
        """)

        XCTAssertEqual(project.customStates?.count, 1)
        XCTAssertEqual(project.customStates?.first?.role, "blocked")
        XCTAssertEqual(project.customStates?.first?.description, "Stuck")
    }

    func testAnAbsentCustomStatesFieldIsJustNoCustomStates() throws {
        XCTAssertNil(try decodeProject(#"{"id":"p1","name":"Board"}"#).customStates)
    }

    func testAMalformedEntryDoesNotFailTheWholeProject() throws {
        // The server column is a free-form `Json?`, so nothing guarantees the
        // shape. Web tolerates junk entry-by-entry; if iOS threw here, ONE bad
        // row would stop every project decoding — the board would be empty.
        let project = try decodeProject("""
        {"id":"p1","name":"Board",
         "customStates":[{"name":"No role"},{"role":42,"name":"Wrong type"},
                         {"role":"blocked","name":"Blocked"}]}
        """)

        XCTAssertEqual(parseProjectCustomStates(project.customStates).map(\.role), ["blocked"])
    }

    func testANonArrayCustomStatesIsToleratedAsEmpty() throws {
        // Mirrors web's `if (!Array.isArray(raw)) return []`.
        let project = try decodeProject(#"{"id":"p1","name":"Board","customStates":{"role":"blocked"}}"#)

        XCTAssertEqual(parseProjectCustomStates(project.customStates), [])
    }

    func testCustomStatesRoundTripThroughEncoding() throws {
        let original = Project(id: "p1", name: "Board",
                               customStates: [state("blocked", "Blocked", description: "Stuck", order: 0)])
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.customStates, original.customStates)
    }
}
