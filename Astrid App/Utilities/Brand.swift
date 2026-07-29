import Foundation
import SwiftUI

/// Brand configuration — the single source of truth for every brand-bearing value
/// in the iOS and Mac apps.
///
/// Task 97208a72. Mirrors `lib/brand/config.ts` on the web side, so a fork rebrands by
/// editing the defaults here (and the matching Info.plist keys / asset catalog) rather
/// than hunting literals through 500 Swift files.
///
/// Each value reads an optional Info.plist key first and falls back to the Astrid
/// default, so behaviour is unchanged unless a deployment overrides it. The Info.plist
/// route exists so a build can vary the brand without touching source; the defaults
/// below are what actually ships today.
///
/// Deliberately out of scope (see the task): bundle identifiers, keychain service, App
/// Group, the `astrid://` URL scheme, associated domains, Xcode target names and the
/// asset catalog. Those touch App Store Connect and provisioning.
enum Brand {

    // MARK: - Identity

    /// Short product name, e.g. "Astrid". Used wherever copy names the app.
    static let appName = infoString("BrandName") ?? "Astrid"

    /// Apex web host, without scheme. Universal Links and the production API live here.
    static let host = infoString("BrandHost") ?? "astrid.cc"

    /// Domain for AI agent identities (`claude@<domain>`).
    ///
    /// Separate from `host` because the server allows them to diverge, and because
    /// clients must never construct an agent address — they only compare what the
    /// server returned. See `AvailableAgent.isDefaultAssistant`.
    static let agentEmailDomain = infoString("BrandAgentEmailDomain") ?? "astrid.cc"

    /// Address shown to users for support requests.
    static let supportEmail = infoString("BrandSupportEmail") ?? "support@astrid.cc"

    /// Address users email to create a task.
    static let inboundTaskEmail = infoString("BrandInboundTaskEmail") ?? "remindme@astrid.cc"

    /// The header lockup, drawn on the sign-in screen.
    ///
    /// Astrid draws its mark in lowercase. That is a typographic choice about *this*
    /// mark, not a rule about names, so a partner can override it — hence a value of
    /// its own rather than `appName.lowercased()` at the call site.
    static let wordmark = infoString("BrandWordmark") ?? appName.lowercased()

    /// The line beneath the wordmark, e.g. "Get it done!".
    ///
    /// A brand value, not a translation: it defaults to the localized `auth.tagline` so
    /// Astrid keeps its twelve translations, and a partner overrides it with one string
    /// rather than commissioning twelve.
    ///
    /// COMPUTED, and it must stay that way. `LocalizationManager.setLanguage` changes the
    /// app's language at RUNTIME, so a `static let` here would freeze the slogan in
    /// whichever language happened to be active the first time it was read. The identity
    /// values above are stored because Info.plist cannot change after launch; anything
    /// that resolves through `NSLocalizedString` cannot be.
    ///
    /// The cost is a strings-table lookup on a screen that renders a handful of times,
    /// which is not a hot path. `accentColor` is the opposite case and is stored.
    static var slogan: String {
        infoString("BrandSlogan") ?? NSLocalizedString("auth.tagline", comment: "")
    }

    /// Filename stem for exported account data, e.g. `astrid-export-2026-07-18.json`.
    static var exportFilePrefix: String { "\(wordmark)-export" }

    /// Display name of the default assistant persona. Mirrors `NEXT_PUBLIC_BRAND_AGENT_NAME`.
    ///
    /// Distinct from `appName` because a brand may name its assistant separately from its
    /// product, and because the on-device model is *told* this name and then repeats it
    /// to the user — it is user-visible copy, not an internal identifier.
    static let agentName = infoString("BrandAgentName") ?? appName

    // MARK: - Appearance

    /// Default accent, as a hex string. Astrid blue (Tailwind `blue-500`).
    ///
    /// Kept as the one place the literal appears — `Theme`, `Theme.Dark` and
    /// `Theme.Ocean` all derive from it rather than repeating it.
    static let defaultAccentHex = "#3b82f6"

    /// The brand accent, e.g. `#3b82f6`. Always a parseable hex.
    static let accentColorHex = resolveAccentHex(infoString("BrandAccentColor"))

    /// Pressed / hovered state of the accent.
    static let accentHoverColorHex = resolveAccentHex(
        infoString("BrandAccentHoverColor"), fallback: "#2563eb")

    /// Colour drawn ON the accent. A partner choosing a pale accent needs to change
    /// this with it, which is why it is configuration and not a constant `.white`.
    static let accentTextColorHex = resolveAccentHex(
        infoString("BrandAccentTextColor"), fallback: "#ffffff")

    // Stored, not computed: theme colours are read on every SwiftUI render, and parsing
    // a hex string with Scanner per access would be a real cost. `static let` resolves
    // once via swift_once, and the value cannot change after launch anyway.

    /// The brand accent as a `Color`. `Theme.accent` and friends resolve to this.
    static let accentColor: Color = color(accentColorHex, fallback: defaultAccentHex)

    /// Pressed / hovered accent.
    static let accentHoverColor: Color = color(accentHoverColorHex, fallback: "#2563eb")

    /// Foreground drawn on top of the accent.
    static let accentTextColor: Color = color(accentTextColorHex, fallback: "#ffffff")

    /// Normalise a configured accent to a `#rrggbb` / `#rrggbbaa` string, or fall back.
    ///
    /// Deliberately total: a brand colour is chrome, not a feature, so a typo in it must
    /// render the default rather than throw or produce a transparent control. Exposed
    /// (rather than inlined) so the fallback behaviour is testable without a second bundle.
    static func resolveAccentHex(_ raw: String?, fallback: String = "#3b82f6") -> String {
        guard let raw else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unsubstituted build setting (`$(BRAND_ACCENT)`) is not a colour.
        guard !trimmed.hasPrefix("$(") else { return fallback }
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit) else { return fallback }
        return "#\(digits)"
    }

    // MARK: - Derived

    /// Canonical production origin, e.g. `https://astrid.cc`.
    static var productionBaseURL: String { "https://\(host)" }

    /// Hosts that count as this brand's web app, for Universal Link routing.
    static var webHosts: Set<String> { [host, "www.\(host)"] }

    /// Does this cookie domain belong to the brand? Used when clearing session state.
    ///
    /// The previous test was `domain.contains("astrid")`, which is brand-coupled AND too
    /// broad. The leading dot below is load-bearing: `hasSuffix(host)` alone also accepts
    /// `evil-astrid.cc`, and `contains` accepts `astrid.evil.com`. Cookie domains are
    /// commonly stored with a leading dot (`.astrid.cc`), so that form is normalised away
    /// before matching rather than being treated as a subdomain.
    static func isBrandCookieDomain(_ domain: String) -> Bool {
        let normalized = domain
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .drop(while: { $0 == "." })
        guard !normalized.isEmpty else { return false }
        let host = self.host.lowercased()
        return normalized == host || normalized.hasSuffix(".\(host)")
    }

    /// Subsystem for `os.log` / `Logger`, e.g. `com.graceful-tools.astrid`.
    ///
    /// Derived from the bundle identifier so it follows a fork automatically rather
    /// than needing its own configuration.
    static let logSubsystem = Bundle.main.bundleIdentifier ?? "com.graceful-tools.astrid"

    // MARK: - Localized copy

    /// Look up a localized string whose copy names the app, and substitute the brand.
    ///
    /// `.strings` files have no named placeholders, so brand-bearing copy stores the app
    /// name as the FIRST positional argument (`%1$@`) and any real arguments follow
    /// (`%2$@`, …). Callers use this instead of `NSLocalizedString` so no view has to
    /// know that the first argument is the brand.
    ///
    ///     Brand.localized("welcome.title")                 // "Welcome to Astrid!"
    ///     Brand.localized("debug.app_version", version)    // "Astrid v1.2.3"
    static func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        // `arguments` is an array here — pass it via the array overload rather than as a
        // single value, or every caller-supplied argument formats as "(\n ...)".
        return String(format: format, arguments: [appName] + arguments)
    }

    // MARK: - Private

    /// Parse a hex string that `resolveAccentHex` has already validated.
    ///
    /// The `fallback` is belt-and-braces: resolution guarantees a parseable value, so
    /// this only fires if the two ever disagree, and `.clear` chrome is not an option.
    private static func color(_ hex: String, fallback: String) -> Color {
        Color(hex: hex) ?? Color(hex: fallback) ?? Color(red: 59/255, green: 130/255, blue: 246/255)
    }

    /// Read a non-empty string from the running bundle's Info.plist.
    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unsubstituted build setting (`$(BRAND_NAME)`) is not a brand — ignore it.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
