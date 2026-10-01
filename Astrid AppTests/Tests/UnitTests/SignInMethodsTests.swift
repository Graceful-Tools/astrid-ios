import XCTest
@testable import Astrid_App

/// The login screens show only the sign-in methods the connected deployment offers.
///
/// They drew Google, Passkey and Apple unconditionally, so a partner deployment without
/// Google or Apple sign-in (tasks.gracefultools.com, brands/whitelabel-partner.brand.json)
/// showed buttons that fail on tap.
final class SignInMethodsTests: XCTestCase {

    private func auth(google: Bool = true, apple: Bool = true, passkey: Bool = true) throws -> ServerCapabilities.Auth {
        let json = #"{"google":\#(google),"apple":\#(apple),"passkey":\#(passkey)}"#
        return try JSONDecoder().decode(ServerCapabilities.Auth.self, from: Data(json.utf8))
    }

    func testOffersEverythingAnAstridDeploymentSupports() throws {
        XCTAssertEqual(SignInMethods.offered(by: try auth()), SignInMethods(google: true, passkey: true, apple: true))
    }

    func testAPasskeyOnlyPartnerShowsOnlyPasskey() throws {
        let methods = SignInMethods.offered(by: try auth(google: false, apple: false))
        XCTAssertEqual(methods, SignInMethods(google: false, passkey: true, apple: false))
    }

    func testAppleNeedsTheBuildEntitlementAsWellAsTheServer() throws {
        // The Mac Developer ID build cannot carry Sign in with Apple, whatever the server says.
        XCTAssertFalse(SignInMethods.offered(by: try auth(), appleEntitled: false).apple)
        XCTAssertFalse(SignInMethods.offered(by: try auth(apple: false), appleEntitled: true).apple)
    }

    func testAnOlderServerThatSaysNothingKeepsEveryButton() throws {
        // ServerCapabilities decodes a missing key as "offered".
        let silent = try JSONDecoder().decode(ServerCapabilities.Auth.self, from: Data("{}".utf8))
        XCTAssertEqual(SignInMethods.offered(by: silent), SignInMethods(google: true, passkey: true, apple: true))
    }

    func testBothLoginScreensAskTheServer() throws {
        // A screen that draws its buttons without consulting SignInMethods regresses this.
        for path in ["Astrid App/Views/Authentication/LoginView.swift", "Astrid Mac/App/MacAuthGateView.swift"] {
            let source = try RepositoryLocator.source(at: path)
            XCTAssertTrue(source.contains("SignInMethods"), "\(path) must decide its buttons with SignInMethods")
            for method in ["google", "passkey", "apple"] {
                XCTAssertTrue(source.contains("if signInMethods.\(method)"), "\(path) must gate the \(method) button")
            }
        }
    }
}
