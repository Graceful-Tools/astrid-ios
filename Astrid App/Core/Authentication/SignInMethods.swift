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

    static func offered(by auth: ServerCapabilities.Auth, appleEntitled: Bool = true) -> SignInMethods {
        guard let listed = auth.providers else {
            return SignInMethods(google: auth.google, passkey: auth.passkey, apple: auth.apple && appleEntitled,
                                 github: auth.github, sso: auth.sso)
        }
        return SignInMethods(
            google: listed.contains(.google),
            passkey: listed.contains(.passkey),
            apple: listed.contains(.apple) && appleEntitled,
            github: listed.contains(.github),
            sso: listed.contains(.sso),
            order: listed
        )
    }
}
