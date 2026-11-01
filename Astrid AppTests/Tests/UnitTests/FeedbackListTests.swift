import XCTest
@testable import Astrid_App

/// AITD-571 — Report an Issue opens the DEPLOYMENT's feedback list, never a hardcoded one.
///
/// `Constants.Lists.bugsAndRequestsListId` was Astrid's own production list, so a white-label
/// build sent a partner's users to Astrid's Bugs & Feedback board. The id is brand config now:
/// it arrives as `brand.feedbackListId` in `/api/v1/capabilities` (astrid-core `a4352b30` reads
/// the same field the same way), and absent or blank means this deployment has no in-app list.
final class FeedbackListTests: XCTestCase {

    /// Astrid's production list — the id that used to be compiled in.
    private let astridsOwnList = "6afe098f-e163-46f7-ac4b-4f879a9314eb"
    private let baseURL = "https://partner.example"

    private func brand(_ json: String) throws -> ServerCapabilities.BrandInfo {
        try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8)).brand
    }

    /// The bug itself: a deployment that names no list must not land on Astrid's.
    func testAITD571_DeploymentNamingNoListDoesNotOpenAstrids() throws {
        let destination = ReviewPromptManager.feedbackDestination(
            brand: try brand(#"{"brand":{"appName":"Acme"}}"#), baseURL: baseURL)

        XCTAssertNotEqual(destination, .list(id: astridsOwnList))
        XCTAssertEqual(destination, .web(URL(string: baseURL)!))
    }

    func testAITD571_DeploymentsOwnListOpensInApp() throws {
        let destination = ReviewPromptManager.feedbackDestination(
            brand: try brand(#"{"brand":{"feedbackListId":"list-123"}}"#), baseURL: baseURL)

        XCTAssertEqual(destination, .list(id: "list-123"))
    }

    /// Blank is how a white-label brand profile turns the feature off. Not an id.
    func testAITD571_BlankOrWhitespaceIdMeansNoList() throws {
        XCTAssertNil(try brand(#"{"brand":{"feedbackListId":""}}"#).feedbackListId)
        XCTAssertNil(try brand(#"{"brand":{"feedbackListId":"   "}}"#).feedbackListId)
        XCTAssertEqual(try brand(#"{"brand":{"feedbackListId":"  abc  "}}"#).feedbackListId, "abc")
    }

    /// The id goes into a URL path, so anything that is not an id character is rejected.
    func testAITD571_NonIdCharactersAreRejected() throws {
        XCTAssertNil(try brand(#"{"brand":{"feedbackListId":"../admin"}}"#).feedbackListId)
        XCTAssertNil(try brand(#"{"brand":{"feedbackListId":"a b"}}"#).feedbackListId)
        XCTAssertNil(try brand(#"{"brand":{"feedbackListId":"abc?x=1"}}"#).feedbackListId)
    }

    /// Before the first fetch nothing is known, so nothing is assumed.
    func testAITD571_PermissiveCapabilitiesNameNoList() {
        XCTAssertNil(ServerCapabilities.permissive.brand.feedbackListId)
    }
}
