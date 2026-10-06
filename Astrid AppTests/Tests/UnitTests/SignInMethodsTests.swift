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
            XCTAssertTrue(source.contains("signInMethods.buttons"), "\(path) must draw the buttons the server lists, in its order")
        }
    }

    // MARK: - AITD-465: auth.providers, GitHub and SSO

    private func decode(_ json: String) throws -> ServerCapabilities.Auth {
        try JSONDecoder().decode(ServerCapabilities.Auth.self, from: Data(json.utf8))
    }

    func testAITD465_GitHubAndSSOAreNotOfferedWhenTheServerSaysNothing() throws {
        // Opt-in providers: an absent key means the deployment has not configured them. Reading
        // it as "offered" (the convention for google/apple/passkey) gives every older deployment
        // buttons that fail on tap.
        let silent = try decode("{}")
        XCTAssertFalse(silent.github)
        XCTAssertFalse(silent.sso)
        XCTAssertFalse(ServerCapabilities.permissive.auth.github)
        XCTAssertFalse(ServerCapabilities.permissive.auth.sso)
        XCTAssertEqual(SignInMethods.offered(by: silent).buttons, [.google, .passkey, .apple])
    }

    func testAITD465_ButtonsFollowTheServersProviderOrder() throws {
        let auth = try decode(#"""
        {"google":true,"apple":true,"passkey":true,"github":true,"sso":true,
         "providers":[{"id":"github","kind":"oauth"},{"id":"passkey","kind":"webauthn"},
                      {"id":"sso","kind":"oidc"},{"id":"google","kind":"oauth"}]}
        """#)
        XCTAssertEqual(auth.providers, [.github, .passkey, .sso, .google])
        // Apple is not in the list, so it is not drawn even though the legacy boolean says true.
        XCTAssertEqual(SignInMethods.offered(by: auth).buttons, [.github, .passkey, .sso, .google])
    }

    func testAITD465_UnknownAndRepeatedProvidersAreDropped() throws {
        let auth = try decode(#"""
        {"providers":[{"id":"saml-broker","kind":"saml"},{"id":"github","kind":"oauth"},
                      {"id":"github","kind":"oauth"},{"kind":"oauth"},{"id":"apple","kind":"oauth"}]}
        """#)
        XCTAssertEqual(auth.providers, [.github, .apple])
    }

    func testAITD465_AppleStillNeedsTheEntitlementInsideAProviderList() throws {
        let auth = try decode(#"{"providers":[{"id":"apple","kind":"oauth"},{"id":"github","kind":"oauth"}]}"#)
        XCTAssertEqual(SignInMethods.offered(by: auth, appleEntitled: false).buttons, [.github])
    }

    func testAITD465_AServerWithFlagsButNoListAppendsGitHubAndSSO() throws {
        // A deployment between the booleans and the list: keep the legacy order, then the opt-ins.
        let auth = try decode(#"{"google":false,"github":true,"sso":true}"#)
        XCTAssertEqual(SignInMethods.offered(by: auth).buttons, [.passkey, .apple, .github, .sso])
    }

    func testAITD465_OnlyGitHubAndSSOGoThroughTheBrowser() {
        XCTAssertTrue(SignInProvider.github.usesBrowserHandoff)
        XCTAssertTrue(SignInProvider.sso.usesBrowserHandoff)
        XCTAssertFalse(SignInProvider.google.usesBrowserHandoff)
        XCTAssertFalse(SignInProvider.apple.usesBrowserHandoff)
        XCTAssertFalse(SignInProvider.passkey.usesBrowserHandoff)
    }
}
