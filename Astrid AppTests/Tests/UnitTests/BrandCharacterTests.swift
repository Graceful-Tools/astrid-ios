import XCTest
@testable import Astrid_App

/// AITD-514: the AstridCharacter mascot was hardcoded in nine views, so every partner build
/// showed Astrid's character. It now resolves through `Brand.characterImage`, fed from the
/// web's own `NEXT_PUBLIC_BRAND_LOGO` (whose default is astrid-character.png).
final class BrandCharacterTests: XCTestCase {

    func testAstridShowsItsCharacter_AITD514() {
        XCTAssertEqual(Brand.characterImage, "AstridCharacter")
        XCTAssertEqual(Brand.resolveCharacterImage(nil, appName: "Astrid", exists: { _ in true }), "AstridCharacter")
    }

    /// A partner that configures no art shows none — never Astrid's.
    func testAPartnerWithoutArtHidesTheCharacter_AITD514() {
        XCTAssertNil(Brand.resolveCharacterImage(nil, appName: "Acme", exists: { _ in true }))
    }

    /// The profile carries the web's path; the asset is named after its file.
    func testTheProfilesLogoPathNamesTheAsset_AITD514() {
        XCTAssertEqual(Brand.resolveCharacterImage("/images/whitelabel-logo.png", appName: "Whitelabel", exists: { _ in true }),
                       "whitelabel-logo")
        XCTAssertEqual(Brand.resolveCharacterImage("/images/astrid-character.png", appName: "Acme", exists: { _ in true }),
                       "AstridCharacter")
        // Art the build does not carry is hidden, not drawn as an empty frame.
        XCTAssertNil(Brand.resolveCharacterImage("/images/acme.png", appName: "Acme", exists: { _ in false }))
    }

    /// The Whitelabel variant names its art, and the art ships in both apps' catalogs.
    func testTheWhitelabelVariantCarriesItsCharacter_AITD514() throws {
        for plist in ["Brands/Whitelabel/Info-iOS.plist", "Brands/Whitelabel/Info-Mac.plist"] {
            let data = Data(try RepositoryLocator.source(at: plist).utf8)
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(values["BrandCharacterImage"] as? String, "/images/whitelabel-logo.png", plist)
        }
        for catalog in ["Astrid App/Assets.xcassets", "Astrid Mac/Assets.xcassets"] {
            XCTAssertNoThrow(try RepositoryLocator.source(at: "\(catalog)/whitelabel-logo.imageset/Contents.json"), catalog)
        }
    }
}
