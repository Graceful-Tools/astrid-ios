import XCTest
@testable import Astrid_App

/// AITD-617 — the Google sign-in client is the brand's.
///
/// Astrid's `195880614240-…` client was written into `GoogleSignInManager` and both plists, so a
/// partner either shipped under Astrid's Google consent screen or edited source. The client now
/// comes from the profile's `ios.googleClientId`; a partner without one shows no Google button.
final class BrandGoogleClientTests: XCTestCase {

    private let astridClient = "195880614240-nps6cdlcceliaru5d3b4p6pofjbs7sks.apps.googleusercontent.com"

    func testAstridKeepsItsOwnClient_AITD617() {
        XCTAssertEqual(Brand.googleClientId, astridClient)
        XCTAssertEqual(Brand.googleRedirectScheme, "com.googleusercontent.apps.195880614240-nps6cdlcceliaru5d3b4p6pofjbs7sks")
    }

    func testAConfiguredClientWins_AITD617() {
        let acme = "123456789-abcdef.apps.googleusercontent.com"
        XCTAssertEqual(Brand.resolveGoogleClientId(acme, appName: "Acme"), acme)
        XCTAssertEqual(Brand.resolveGoogleClientId(" \(acme) ", appName: "Astrid"), acme)
    }

    /// Unconfigured, a partner has NO client — never Astrid's, which would put Astrid's consent
    /// screen in front of the partner's users. Garbage counts as unconfigured.
    func testAPartnerWithoutAClientHasNone_AITD617() {
        XCTAssertNil(Brand.resolveGoogleClientId(nil, appName: "Acme"))
        XCTAssertNil(Brand.resolveGoogleClientId("not-a-client", appName: "Acme"))
        XCTAssertNil(Brand.resolveGoogleClientId("$(GOOGLE_CLIENT)", appName: "Acme"))
        XCTAssertEqual(Brand.resolveGoogleClientId(nil, appName: "Astrid"), astridClient)
        XCTAssertEqual(Brand.resolveGoogleClientId("nonsense", appName: "Astrid"), astridClient)
    }

    func testTheRedirectSchemeIsTheReversedClient_AITD617() {
        XCTAssertEqual(Brand.reversedGoogleClient("123-abc.apps.googleusercontent.com"), "com.googleusercontent.apps.123-abc")
    }

    /// The server advertising Google is not enough: the build needs a client to sign in with.
    func testNoClientMeansNoGoogleButton_AITD617() throws {
        let auth = try JSONDecoder().decode(ServerCapabilities.Auth.self, from: Data(#"{"google":true}"#.utf8))
        XCTAssertFalse(SignInMethods.offered(by: auth, googleConfigured: false).google)
        XCTAssertTrue(SignInMethods.offered(by: auth, googleConfigured: true).google)
        let listed = try JSONDecoder().decode(ServerCapabilities.Auth.self,
                                              from: Data(#"{"providers":[{"id":"google","kind":"oauth"},{"id":"passkey","kind":"webauthn"}]}"#.utf8))
        XCTAssertEqual(SignInMethods.offered(by: listed, googleConfigured: false).buttons, [.passkey])
    }

    func testTheProfileKeyIsTheIOSBlocks_AITD617() {
        XCTAssertEqual(BrandProfile.keyMap["ios.googleClientId"], "BrandGoogleClientId")
    }
}
