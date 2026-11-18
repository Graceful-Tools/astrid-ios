//
//  SignInMethods.swift
//  Which sign-in buttons the login screen shows — decided by the deployment, not the build.
//
//  The login screens drew Google, Passkey and Apple unconditionally. One binary can point at
//  several deployments (Brand.host, the Debug server picker), and a partner deployment that
//  runs without Google or Apple sign-in — no OAuth client registered for its domain — would
//  show buttons that fail on tap. The server already says what it supports in
//  `/api/v1/capabilities` → `auth`, and ServerCapabilities decodes it permissively (a missing
//  key means "offered"), so an older server keeps every button.
//
//  Since AITD-465 the server also sends `auth.providers`, the configured providers in button
//  order, which is how GitHub and SSO arrive. When it is present it decides both which buttons
//  appear and their order; when it is absent the legacy booleans decide, in this app's own order.
//
//  The Mac's Developer ID build cannot carry the Sign in with Apple entitlement at all; that is
//  a property of the BUILD, so it arrives as `appleEntitled` and both conditions must hold.
//  Google is the same: a build with no OAuth client of its own (a partner that set none,
//  AITD-617) cannot sign in with it, so `googleConfigured` must hold too.
//

import Foundation

/// A sign-in provider a deployment can offer. Raw values are the server's ids (spec §6.2).
enum SignInProvider: String, CaseIterable, Identifiable, Equatable {
    case github, google, apple, passkey, sso

    var id: String { rawValue }

    /// GitHub and SSO have no native SDK in the app: they sign in through the browser and hand
    /// a session back (`DesktopHandoff`, spec §6.5). Google, Apple and passkeys keep their
    /// native flows.
    var usesBrowserHandoff: Bool {
        switch self {
        case .github, .sso: return true
        case .google, .apple, .passkey: return false
        }
    }
}

struct SignInMethods: Equatable {
    var google: Bool
    var passkey: Bool
    var apple: Bool
    var github = false
    var sso = false
    /// Button order. Only offered providers in it are drawn.
    var order: [SignInProvider] = SignInMethods.legacyOrder

    /// The order this app drew before the server sent one, then the opt-in providers.
    static let legacyOrder: [SignInProvider] = [.google, .passkey, .apple, .github, .sso]

    /// The buttons to draw, in order.
    var buttons: [SignInProvider] { order.filter(isOffered) }

    func isOffered(_ provider: SignInProvider) -> Bool {
        switch provider {
        case .google: return google
        case .passkey: return passkey
        case .apple: return apple
        case .github: return github
        case .sso: return sso
        }
    }

    static func offered(by auth: ServerCapabilities.Auth, appleEntitled: Bool = true,
                        googleConfigured: Bool = Brand.googleClientId != nil) -> SignInMethods {
        guard let listed = auth.providers else {
            return SignInMethods(google: auth.google && googleConfigured, passkey: auth.passkey,
                                 apple: auth.apple && appleEntitled, github: auth.github, sso: auth.sso)
        }
        return SignInMethods(
            google: listed.contains(.google) && googleConfigured,
            passkey: listed.contains(.passkey),
            apple: listed.contains(.apple) && appleEntitled,
            github: listed.contains(.github),
            sso: listed.contains(.sso),
            order: listed
        )
    }
}

/// How the sign-in screen signs in (ADEV-119).
///
/// On the build's own server: its native buttons, as the server lists them. On anyone else's,
/// one button that opens that server's own sign-in page in the browser. The native flows cannot
/// work there: passkeys and Universal Links are bound to the domains in this app's entitlements,
/// and Google and Apple sign-in to this app's own client ids. The server's page offers whatever
/// it has, passkeys on its own domain included.
enum SignInPlan: Equatable {
    case native(SignInMethods)
    /// Sign in on this host's page.
    case serverPage(host: String)

    static func forServer(isCustom: Bool, host: String, auth: ServerCapabilities.Auth,
                          appleEntitled: Bool = true,
                          googleConfigured: Bool = Brand.googleClientId != nil) -> SignInPlan {
        if isCustom { return .serverPage(host: host) }
        return .native(.offered(by: auth, appleEntitled: appleEntitled, googleConfigured: googleConfigured))
    }
}
