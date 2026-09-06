//  PasskeySignInPlan.swift
//  How a passkey sign-in is asked for, and what to do when it does not come back (AITD-298).
//
//  On macOS the full system sheet leads with the nearby-device QR whenever iCloud Keychain holds
//  no passkey for the site, and third-party managers (Dashlane, 1Password…) appear only once the
//  user has enabled them in System Settings › Passwords › Password Options. Asking for LOCAL
//  credentials first keeps the QR out of the way; when nothing local answers, the alternatives
//  are offered explicitly rather than imposed. Decided here, as a rule, so it can be asserted.

import Foundation
import AuthenticationServices

/// Which system sheet a passkey request asks for.
enum PasskeyPresentation: Equatable {
    /// Credentials on this device only — iCloud Keychain and enabled third-party providers.
    /// With nothing available the request ends at once, without UI; the nearby-device (QR)
    /// option is never shown.
    case localOnly
    /// The full system sheet, nearby-device option included.
    case fullSheet

    /// The `ASAuthorizationController` options that produce this presentation.
    var requestOptions: ASAuthorizationController.RequestOptions {
        switch self {
        case .localOnly: return [.preferImmediatelyAvailableCredentials]
        case .fullSheet: return []
        }
    }
}

enum PasskeySignInPlan {

    /// What a tap on "Sign in with Passkey" asks for.
    ///
    /// Mac: local first — the QR is a fallback, not the greeting. iOS: the phone IS the passkey
    /// device and its sheet already leads with local credentials, so the full sheet stays.
    static func initialPresentation(isMac: Bool) -> PasskeyPresentation {
        isMac ? .localOnly : .fullSheet
    }

    /// The explicit "use a passkey from another device" route: the full sheet, QR included.
    static let otherDevicePresentation: PasskeyPresentation = .fullSheet

    /// Where a third-party password manager is enabled as a passkey provider on macOS.
    static let passwordOptionsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension")!

    enum NextStep: Equatable {
        /// Show the alternatives: another device (QR), a password manager, the other sign-ins.
        case offerAlternatives
        /// A real failure the user should read.
        case surfaceError
        /// A deliberate dismissal — say nothing.
        case none
    }

    /// What follows a failed attempt made with `presentation`.
    static func nextStep(after presentation: PasskeyPresentation, error: PasskeyError) -> NextStep {
        switch error {
        case .noLocalPasskey:
            return .offerAlternatives
        case .userCancelled:
            // Under local-only a cancel and "nothing available" are the same code; the manager
            // already maps that to `.noLocalPasskey`, so a `.userCancelled` here is a real dismissal.
            return .none
        default:
            return .surfaceError
        }
    }
}
