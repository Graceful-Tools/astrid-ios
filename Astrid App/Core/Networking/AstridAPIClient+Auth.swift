//  AstridAPIClient+Auth.swift
//  POST /api/v1/auth/desktop/exchange — the native half of browser sign-in (AITD-465).
//
//  An extension rather than more lines in AstridAPIClient.swift: the client sits on the source
//  file size ceiling (SourceFileSizeGuardTests), and the precedent from AITD-388 is to move a
//  cohesive group of endpoints out, not to raise the number. APIEndpointInventoryTests scans
//  this file too, so docs/API_ENDPOINTS.md stays honest about the paths it adds.

import Foundation

extension AstridAPIClient {
    /// Trade a desktop hand-off code and its PKCE verifier for a session (spec §6.5).
    /// Unauthenticated: the app has no session yet, which is the point. The token comes back in
    /// the body, never as Set-Cookie, so the caller stores it.
    func exchangeDesktopCode(_ body: DesktopExchangeRequest) async throws -> DesktopExchangeResponse {
        try await request(method: "POST", path: "/api/v1/auth/desktop/exchange", body: body)
    }
}
