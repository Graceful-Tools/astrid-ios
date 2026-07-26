//  OAuthCallbackValidator.swift
//  Security: validate the OAuth redirect before spending the authorization code.
//
//  The Google sign-in flow generated a `state` value "for CSRF protection" and sent it in the
//  authorization request — but nothing ever checked it on the way back, so the guarantee it was
//  supposed to provide did not exist. An attacker-supplied callback could hand the app an
//  authorization code of the attacker's choosing (code injection), which on success would bind
//  the victim's Astrid session to the attacker's Google identity.
//
//  PKCE limits the damage (a foreign code won't match our code_verifier), but state validation is
//  the defense that is actually supposed to stop this, and it must not be silently absent.
//
//  Pure and synchronous so the rule is unit-testable without a browser session.
import Foundation

enum OAuthCallbackError: Error, Equatable {
    case providerError(String)   // provider reported ?error=... (e.g. access_denied)
    case stateMismatch           // missing or forged state — do NOT use the code
    case missingCode
}

enum OAuthCallbackValidator {

    /// Extract the authorization code from a redirect, rejecting anything whose `state`
    /// does not match the value we generated for this attempt.
    static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        // A provider-reported error is the honest reason for failure; surface it before anything else.
        if let error = value("error") {
            throw OAuthCallbackError.providerError(error)
        }

        // Constant-time-ish comparison isn't required (state is single-use and compared once),
        // but an empty expected state must never be treated as "matches anything".
        guard !expectedState.isEmpty, let returned = value("state"), returned == expectedState else {
            throw OAuthCallbackError.stateMismatch
        }

        guard let code = value("code"), !code.isEmpty else {
            throw OAuthCallbackError.missingCode
        }
        return code
    }
}
