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
//  The Mac's Developer ID build cannot carry the Sign in with Apple entitlement at all; that is
//  a property of the BUILD, so it arrives as `appleEntitled` and both conditions must hold.
//

import Foundation

struct SignInMethods: Equatable {
    var google: Bool
    var passkey: Bool
    var apple: Bool

    static func offered(by auth: ServerCapabilities.Auth, appleEntitled: Bool = true) -> SignInMethods {
        SignInMethods(google: auth.google, passkey: auth.passkey, apple: auth.apple && appleEntitled)
    }
}
