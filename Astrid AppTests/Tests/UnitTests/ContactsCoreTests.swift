//  ContactsCoreTests.swift
//  Contacts sync, the synced-contact count and the people search behind the assignee, mention
//  and member pickers go through astrid-core (AITD-620, ninth slice): the commands they send and
//  the core's answers read back.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`dispatch/tests/account.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class ContactsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: The commands

    func testTheContactCountIsTheCoresContactsCommand_AITD620() throws {
        XCTAssertEqual(try json(ContactCommands.status())["kind"] as? String, "contacts")
    }

    /// The whole address book goes in one command: the core batches it (500 a request, the first
    /// replacing), so the Swift no longer does.
    func testUploadSendsEveryContactInOneCommand_AITD620() throws {
        let book = (0..<1_201).map { DeviceContact(email: "p\($0)@x.io", name: $0 == 0 ? "Ann" : nil, phoneNumber: nil) }
        let sent = try json(ContactCommands.upload(book))
        XCTAssertEqual(sent["kind"] as? String, "uploadContacts")
        let contacts = try XCTUnwrap(sent["contacts"] as? [[String: Any]])
        XCTAssertEqual(contacts.count, 1_201)
        XCTAssertEqual(contacts[0]["email"] as? String, "p0@x.io")
        XCTAssertEqual(contacts[0]["name"] as? String, "Ann")
    }

    /// An empty address book still sends the command — the core turns it into one replacing
    /// request, so someone who deleted everyone stops being suggested.
    func testAnEmptyAddressBookStillUploads_AITD620() throws {
        let sent = try json(ContactCommands.upload([]))
        XCTAssertEqual(sent["kind"] as? String, "uploadContacts")
        XCTAssertEqual((sent["contacts"] as? [Any])?.count, 0)
    }

    /// The pickers always asked for the AI agents too; the core adds them only when told.
    func testPeopleSearchAsksForAgentsAndScopes_AITD620() throws {
        let sent = try json(ContactCommands.searchUsers(query: "ad", taskId: "t1", listIds: ["l1", "l2"]))
        XCTAssertEqual(sent["kind"] as? String, "searchUsers")
        XCTAssertEqual(sent["query"] as? String, "ad")
        XCTAssertEqual(sent["taskId"] as? String, "t1")
        XCTAssertEqual(sent["listIds"] as? [String], ["l1", "l2"])
        XCTAssertEqual(sent["includeAgents"] as? Bool, true)
    }

    func testAnUnscopedSearchLeavesTheScopeOut_AITD620() throws {
        let sent = try json(ContactCommands.searchUsers(query: "", taskId: nil, listIds: nil))
        XCTAssertNil(sent["taskId"])
        XCTAssertNil(sent["listIds"])
        XCTAssertEqual(sent["includeAgents"] as? Bool, true)
    }

    /// Autocomplete when adding a member (AITD-620, tenth slice): the core's `searchContacts`,
    /// with the app's limit of 10 and the list whose members are left out.
    func testContactAutocompleteIsTheCoresSearchContacts_AITD620() throws {
        let sent = try json(ContactCommands.searchContacts(query: "an", excludeListId: "l1"))
        XCTAssertEqual(sent["kind"] as? String, "searchContacts")
        XCTAssertEqual(sent["query"] as? String, "an")
        XCTAssertEqual(sent["excludeListId"] as? String, "l1")
        XCTAssertEqual(sent["limit"] as? Int, 10)
    }

    func testAutocompleteWithNoListLeavesTheExclusionOut_AITD620() throws {
        let sent = try json(ContactCommands.searchContacts(query: "an", excludeListId: nil))
        XCTAssertNil(sent["excludeListId"])
    }

    /// Recommended collaborators: the core's `recommendedCollaborators`, still asking for 20.
    func testRecommendationsAreTheCoresRecommendedCollaborators_AITD620() throws {
        let sent = try json(ContactCommands.recommendedCollaborators(excludeListId: "l1"))
        XCTAssertEqual(sent["kind"] as? String, "recommendedCollaborators")
        XCTAssertEqual(sent["excludeListId"] as? String, "l1")
        XCTAssertEqual(sent["limit"] as? Int, 20)
        XCTAssertNil(try json(ContactCommands.recommendedCollaborators(excludeListId: nil))["excludeListId"])
    }

    // MARK: The core's answers

    /// `contacts` answers `{ contacts, total }`; the settings row only shows the total.
    func testTheCoresContactsAnswerReadsAsTheCount_AITD620() throws {
        let answer = try JSONDecoder().decode(ContactStatus.self, from: Data(
            #"{"contacts":[{"id":"c1","email":"ann@x.io","name":"Ann"}],"total":42}"#.utf8))
        XCTAssertEqual(answer.total, 42)
    }

    /// `uploadContacts` answers the last batch's stats, whose `total` is the account's whole count.
    func testTheCoresUploadAnswerReadsAsTheStats_AITD620() throws {
        let stats = try JSONDecoder().decode(ContactSyncStats.self, from: Data(
            #"{"received":2,"valid":2,"created":1,"updated":1,"total":1201,"errors":0}"#.utf8))
        XCTAssertEqual(stats.total, 1_201)
    }

    /// The core's `User` rows (camelCase, agents flagged) read as the app's `User`.
    func testTheCoresSearchRowsReadAsUsers_AITD620() throws {
        let users = try JSONDecoder().decode([User].self, from: Data(#"""
            [{"id":"u1","email":"ada@x.io","name":"Ada"},
             {"id":"ai-agent-claude","name":"Claude Agent","image":"https://x/c.png","isAIAgent":true,"aiAgentType":"claude"}]
            """#.utf8))
        XCTAssertEqual(users.map(\.id), ["u1", "ai-agent-claude"])
        XCTAssertEqual(users[1].isAIAgent, true)
        XCTAssertEqual(users[1].aiAgentType, "claude")
    }

    /// `searchContacts` answers `{ results: [...] }`, each row as the route sends it.
    func testTheCoresAutocompleteAnswerReadsAsContactRows_AITD620() throws {
        let answer = try JSONDecoder().decode(ContactSearchAnswer.self, from: Data(#"""
            {"results":[{"id":"c1","email":"ann@x.io","name":"Ann","phoneNumber":null,
                         "isAstridUser":true,"astridUserName":"Ann A","astridUserImage":"https://x/a.png"},
                        {"id":"c2","email":"bo@x.io","name":null,"phoneNumber":"+1",
                         "isAstridUser":false,"astridUserName":null,"astridUserImage":null}]}
            """#.utf8))
        XCTAssertEqual(answer.results.map(\.id), ["c1", "c2"])
        XCTAssertEqual(answer.results[0].displayName, "Ann A")
        XCTAssertEqual(answer.results[1].displayName, "bo@x.io")
    }

    /// `recommendedCollaborators` answers `{ recommended, stats, message }`; with no contacts
    /// uploaded `stats` is null and `recommended` empty, which must still read.
    func testTheCoresRecommendationsAnswerReads_AITD620() throws {
        let some = try JSONDecoder().decode(RecommendedCollaboratorsAnswer.self, from: Data(#"""
            {"recommended":[{"id":"u1","email":"ada@x.io","name":"Ada","image":null,
                             "contactName":"Ada L","isMutual":true}],
             "stats":{"mutual":1,"nonMutual":0,"total":1},"message":null}
            """#.utf8))
        XCTAssertEqual(some.recommended.map(\.id), ["u1"])
        XCTAssertTrue(some.recommended[0].isMutual)
        let none = try JSONDecoder().decode(RecommendedCollaboratorsAnswer.self, from: Data(
            #"{"recommended":[],"stats":null,"message":"No contacts uploaded yet."}"#.utf8))
        XCTAssertTrue(none.recommended.isEmpty)
    }
}
