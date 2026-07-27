//  MacSignInOptions.swift
//  Astrid for Mac — which sign-in methods this BUILD can actually offer.
//
//  Apple does not issue `com.apple.developer.applesignin` in Developer ID provisioning profiles,
//  so the direct-download (DMG) build is signed with "Astrid Mac Direct.entitlements", which omits
//  it. Showing an Apple button there would fail at the point of tapping it — ASAuthorization
//  rejects an app whose code signature lacks the entitlement — so the button is hidden instead.
//  TestFlight / App Store builds carry the full entitlements and show it.
//
//  Decided from the running app's OWN code signature, not from a compile-time flag: the entitlement
//  is applied at export time, so only the signature knows the truth.

#if os(macOS)
import Foundation
import Security

enum MacSignInOptions {

    /// Pure form, for tests: Apple sign-in needs the entitlement to be present and non-empty.
    static func showsAppleSignIn(entitlements: [String: Any]) -> Bool {
        guard let value = entitlements["com.apple.developer.applesignin"] else { return false }
        if let array = value as? [String] { return !array.isEmpty }
        return true
    }

    /// The running build's answer, read once from its code signature.
    static let showsAppleSignIn: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.applesignin" as CFString, nil)
        guard let value else { return false }
        if let array = value as? [String] { return !array.isEmpty }
        return true
    }()
}
#endif
