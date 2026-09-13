//  ListOwnershipTransferTests.swift
//  Regression guard for Task AITD-392 — "Turn the Transfer Ownership dead end into a real control
//  — the v1 endpoints now exist".
//
//  The owner of a shared list could not hand it to anyone from the apps. `leaveOption` already
//  returned `.transferOwnership`, and both platforms mapped that case to a line telling the user
//  to go and do it on the web app.
//
//  The GET is the button probe, and the whole risk in this feature is collapsing its four answers
//  into two. They are not the same:
//
//  - An EMPTY eligible list is a 200. "There is nobody to hand this to" is not "you may not do
//    this", and the v1 contract is explicit that the empty array is success.
//  - A 404 means the ROUTE IS NOT THERE. astrid-web does not auto-deploy, so a shipped build can
//    reach a server that has never heard of this endpoint. Treating that as an error would put a
//    broken button in front of an owner; treating it as `.unavailable` keeps the honest "use the
//    web app" line until the deploy lands, and the control then appears on its own.
//
//  That is what makes this shippable ahead of astrid-web's manual production deploy, which is the
//  one ordering requirement the task description names.

import XCTest
@testable import Astrid_App

final class ListOwnershipTransferTests: XCTestCase {

    private func user(_ id: String, isAIAgent: Bool? = nil) -> User {
        User(id: id, email: "\(id)@example.com", name: id.capitalized, image: nil,
             createdAt: nil, defaultDueTime: nil, isPending: nil,
             isAIAgent: isAIAgent, aiAgentType: nil)
    }

    private func appSource(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The four answers

    func testPeopleComingBackOffersThePicker() {
        let successors = [user("ada"), user("grace")]
        XCTAssertEqual(ListOwnershipTransfer.availability(from: .success(successors)),
                       .available(successors))
    }

    /// The distinction the v1 contract calls out by name.
    func testAnEmptyListIsNobodyToHandItToAndNotARefusal() {
        XCTAssertEqual(ListOwnershipTransfer.availability(from: .success([])),
                       .noEligibleOwners,
                       "an empty array is a 200 — 'nobody yet' and 'you may not' want different UI")
        XCTAssertNotEqual(ListOwnershipTransfer.availability(from: .success([])),
                          .notPermitted)
    }

    func testA403IsTheServerSayingYouAreNotTheOwner() {
        let forbidden = AstridAPIError.httpError(statusCode: 403, message: "Forbidden")
        XCTAssertEqual(ListOwnershipTransfer.availability(from: .failure(forbidden)),
                       .notPermitted)
    }

    /// The reason this can ship before astrid-web's manual deploy.
    func testA404MeansTheRouteIsNotDeployedYetAndKeepsTheOldExplanation() {
        let missing = AstridAPIError.httpError(statusCode: 404, message: "Not Found")
        XCTAssertEqual(ListOwnershipTransfer.availability(from: .failure(missing)),
                       .unavailable,
                       "an undeployed route must not become a broken button")
    }

    func testATransportFailureIsAlsoJustNotNow() {
        struct Offline: Error {}
        XCTAssertEqual(ListOwnershipTransfer.availability(from: .failure(Offline())),
                       .unavailable)
        XCTAssertEqual(
            ListOwnershipTransfer.availability(
                from: .failure(AstridAPIError.httpError(statusCode: 500, message: "Internal Server Error"))),
            .unavailable,
            "a server fault is not a statement about this user's rights")
    }

    // MARK: - One call, not two

    /// The transfer and the leave happen in ONE server transaction. Following it with `leave`
    /// would be a second call against a list the caller is no longer a member of — a guaranteed
    /// 403, and on a bad day something worse.
    func testTheServiceTransfersWithoutAlsoCallingLeave() throws {
        let service = try appSource("Astrid App/Core/Services/ListService.swift")

        guard let start = service.range(of: "func transferOwnership(") else {
            return XCTFail("ListService.transferOwnership is the service boundary for AITD-392")
        }
        // The body runs to the start of the next declaration.
        let rest = service[start.upperBound...]
        let body = rest.range(of: "\n    /// ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)

        XCTAssertFalse(body.contains("leaveList"),
                       "the server transfers and removes the caller in one transaction — "
                       + "a follow-up leave is a second call the contract says not to make")
        XCTAssertTrue(body.contains("transferListOwnership"),
                      "the service must call the transfer endpoint through the client")
    }

    /// After the transfer the caller is not a member, so the list has to go locally exactly as
    /// leaving makes it go — otherwise it lingers until the next full sync and taps into a 403.
    func testTheServiceTearsTheListDownLocallyJustAsLeavingDoes() throws {
        let service = try appSource("Astrid App/Core/Services/ListService.swift")

        guard let start = service.range(of: "func transferOwnership(") else {
            return XCTFail("ListService.transferOwnership is the service boundary for AITD-392")
        }
        let rest = service[start.upperBound...]
        let body = rest.range(of: "\n    /// ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)

        for teardown in ["cachedLists.removeValue", "lists.removeAll", "deleteListFromCoreData"] {
            XCTAssertTrue(body.contains(teardown),
                          "\(teardown) is part of how leaveList makes a list go away — "
                          + "a transferred list is just as gone")
        }
    }

    // MARK: - The views ask the service, never the client (ASTRID.md §0 rule 1)

    func testNeitherMembershipTabReachesPastTheServiceToTheAPIClient() throws {
        for path in ["Astrid App/Views/Lists/ListMembershipTab.swift",
                     "Astrid Mac/Views/MacListMembershipTab.swift"] {
            let view = try appSource(path)
            XCTAssertFalse(view.contains("AstridAPIClient.shared.transferListOwnership"),
                           "\(path) must go through ListService — ASTRID.md §0 rule 1")
            XCTAssertFalse(view.contains("AstridAPIClient.shared.eligibleNewOwners"),
                           "\(path) must go through ListService — ASTRID.md §0 rule 1")
        }
    }

    /// The line this feature replaces is not deleted — it is what `.unavailable` shows.
    func testTheOldExplanationSurvivesAsTheNotDeployedState() throws {
        for path in ["Astrid App/Views/Lists/ListMembershipTab.swift",
                     "Astrid Mac/Views/MacListMembershipTab.swift"] {
            let view = try appSource(path)
            XCTAssertTrue(view.contains("lists.owner_cannot_leave_yet"),
                          "\(path) still needs the honest line for a server without the route")
        }
    }
}
