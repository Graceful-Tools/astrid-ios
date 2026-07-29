import Foundation

/// Bridges a web brand profile to the native apps' Info.plist keys.
///
/// Task 97208a72. `brands/<partner>.brand.json` in the web repository is already the
/// single description of a brand — name, domain, wordmark, slogan, accent, capability
/// switches. This maps the part the native apps consume onto the Info.plist keys
/// `Brand` reads, so a partner describes their brand ONCE rather than keeping a
/// parallel iOS description that drifts from the web one.
///
/// `scripts/apply-brand.sh <profile>` uses this mapping to write a partner build's
/// Info.plist. `BrandProfileTests` parses Brand.swift and fails if any key it reads is
/// missing here — so a brand value a partner cannot configure is a build failure rather
/// than something they discover after shipping.
enum BrandProfile {

    /// Web brand-profile variable → the Info.plist key `Brand` reads.
    ///
    /// Only what the native apps actually consume. A profile also carries web-only
    /// settings — capability switches, image paths, NEXTAUTH_URL — and those are skipped
    /// rather than rejected, because a shared profile is expected to describe more than
    /// one platform.
    static let keyMap: [String: String] = [
        "NEXT_PUBLIC_BRAND_NAME": "BrandName",
        // The brand's apex domain is the native apps' host: Universal Links, the
        // production API and the cookie-clearing boundary all derive from it.
        "NEXT_PUBLIC_BRAND_DOMAIN": "BrandHost",
        "NEXT_PUBLIC_BRAND_SUPPORT_EMAIL": "BrandSupportEmail",
        "NEXT_PUBLIC_BRAND_INBOUND_TASK_EMAIL": "BrandInboundTaskEmail",
        "NEXT_PUBLIC_BRAND_WORDMARK": "BrandWordmark",
        "NEXT_PUBLIC_BRAND_SLOGAN": "BrandSlogan",
        "NEXT_PUBLIC_BRAND_ACCENT_COLOR": "BrandAccentColor",
        // Native-only, and that is fine — a shared profile describes more than one
        // platform, so a key consumed by only one of them is normal. The web derives its
        // hover and on-accent colours in CSS; SwiftUI has no cascade to derive them from,
        // so the native apps need them as values. The drift guard in BrandProfileTests
        // is what surfaced these two: Brand read them and no profile could set them.
        "NEXT_PUBLIC_BRAND_ACCENT_HOVER_COLOR": "BrandAccentHoverColor",
        "NEXT_PUBLIC_BRAND_ACCENT_TEXT_COLOR": "BrandAccentTextColor",
        "NEXT_PUBLIC_BRAND_AGENT_NAME": "BrandAgentName",
        // Its own variable on both sides: the server allows the agent-email domain to
        // differ from the brand domain, so they cannot share one key.
        "BRAND_AGENT_EMAIL_DOMAIN": "BrandAgentEmailDomain",
    ]

    /// The Info.plist entries a profile's `env` implies. Unmapped keys are skipped.
    static func infoPlistValues(fromProfileEnv env: [String: String]) -> [String: String] {
        var values: [String: String] = [:]
        for (variable, value) in env {
            guard let key = keyMap[variable] else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            values[key] = trimmed
        }
        return values
    }
}
