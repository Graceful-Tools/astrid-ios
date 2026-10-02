//  AppRelativeLink.swift
//  Server-written chat copy links within the web app the way web does — the "set up a model"
//  prompt says `[Settings > AI Agents](/settings/agents)`. Shared by the iOS DeepLinkManager
//  (AITD-451) and the Mac chat's link handler (AITD-452).

import Foundation

enum AppRelativeLink {
    /// A root-relative link (`/settings/agents`) as the brand-origin URL the routers understand,
    /// or nil for anything else.
    ///
    /// With no scheme and no host, such a link reached the system as a URL it could not open,
    /// so the prompt was a dead tap. A protocol-relative `//host/…` names a host and is NOT one
    /// of these: resolving it would hand an attacker-chosen site the trust of an app link.
    static func resolve(_ url: URL) -> URL? {
        guard url.scheme == nil, url.host == nil, url.path.hasPrefix("/") else { return nil }
        return URL(string: Brand.productionBaseURL + url.absoluteString)
    }
}
