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
    nonisolated static let appName = infoString("BrandName") ?? "Astrid"

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
    nonisolated static let agentName = infoString("BrandAgentName") ?? appName

    /// Asset name of the brand's character art — the mascot on sign-in, welcome, the sidebar
    /// and empty states — or nil to show none. Mirrors `NEXT_PUBLIC_BRAND_LOGO`, whose web
    /// default is `/images/astrid-character.png` (AITD-514).
    static let characterImage = resolveCharacterImage(infoString("BrandCharacterImage"), appName: appName) { name in
        #if os(macOS)
        NSImage(named: name) != nil
        #else
        UIImage(named: name) != nil
        #endif
    }

    /// The profile carries the web's path; the asset is named after its file, so
    /// `/images/whitelabel-logo.png` is the `whitelabel-logo` imageset. Unconfigured, Astrid
    /// shows its own character and a partner shows none — Astrid's mascot on a partner's
    /// sign-in screen is exactly the leak this exists to stop. Art the build does not carry
    /// is hidden rather than drawn as an empty frame.
    static func resolveCharacterImage(_ configured: String?, appName: String, exists: (String) -> Bool) -> String? {
        let astrid = "AstridCharacter"
        guard let configured else { return appName == "Astrid" ? astrid : nil }
        let name = ((configured as NSString).lastPathComponent as NSString).deletingPathExtension
        if name == "astrid-character" { return astrid }
        return !name.isEmpty && exists(name) ? name : nil
    }

    // MARK: - Appearance

    /// Default accent fill, as a hex string: astrid-core's `brand.accent` (`#2563EB`).
    ///
    /// DS26 (AITD-615) darkened it from `#3b82f6` so the white label on a button reads
    /// (5.17:1, was 3.68:1). It is the FILL; text and icons in the brand colour read
    /// `accentInkColor` instead. Kept as the one place the literal appears — `Theme`,
    /// `Theme.Dark` and `Theme.Ocean` all derive from it rather than repeating it.
    static let defaultAccentHex = "#2563eb"

    /// The brand accent, e.g. `#2563eb`. Always a parseable hex.
    static let accentColorHex = resolveAccentHex(infoString("BrandAccentColor"))

    /// Pressed / hovered state of the accent: core's `brand.accent-hover`.
    static let accentHoverColorHex = resolveAccentHex(
        infoString("BrandAccentHoverColor"), fallback: "#1d4ed8")

    /// Colour drawn ON the accent. A partner choosing a pale accent needs to change
    /// this with it, which is why it is configuration and not a constant `.white`.
    static let accentTextColorHex = resolveAccentHex(
        infoString("BrandAccentTextColor"), fallback: "#ffffff")

    /// The accent as text or an icon on a light theme (Light, Ocean): core's
    /// `brand.accent-ink` (DS25). A fill colour used as text drops below 4.5:1, so a link
    /// or an accent icon reads this, never `accentColor`.
    static let accentInkColorHex = resolveAccentInk(
        infoString("BrandAccentInkColor"), accentHex: accentColorHex, dark: false)

    /// The accent as text, an icon or a line on a dark theme: core's `brand.accent-ink-dark`.
    static let accentInkDarkColorHex = resolveAccentInk(
        infoString("BrandAccentInkDarkColor"), accentHex: accentColorHex, dark: true)

    // Stored, not computed: theme colours are read on every SwiftUI render, and parsing
    // a hex string with Scanner per access would be a real cost. `static let` resolves
    // once via swift_once, and the value cannot change after launch anyway.

    /// The brand accent as a `Color`. `Theme.accent` and friends resolve to this.
    static let accentColor: Color = color(accentColorHex, fallback: defaultAccentHex)

    /// Pressed / hovered accent.
    static let accentHoverColor: Color = color(accentHoverColorHex, fallback: "#1d4ed8")

    /// Foreground drawn on top of the accent.
    static let accentTextColor: Color = color(accentTextColorHex, fallback: "#ffffff")

    /// The accent's ink on light themes. `AstridTokens.light/ocean.accentInk` resolve to this.
    static let accentInkColor: Color = color(accentInkColorHex, fallback: astridInk.light)

    /// The accent's ink on the dark theme, which Dark's focus ring, selected border and
    /// low priority also take (DS26).
    static let accentInkDarkColor: Color = color(accentInkDarkColorHex, fallback: astridInk.dark)

    /// Astrid's designed inks for its own accent (core register DS25).
    private static let astridInk = (light: "#1D4ED8", dark: "#60A5FA")

    /// A brand ink: the configured one when it parses; Astrid's designed blue for Astrid's
    /// accent; otherwise derived from the accent by web's `accentInk()` rule
    /// (`lib/brand/css-vars.ts`) — the accent stepped toward black on a light card, white
    /// on a dark one, in twentieths, until it reads at 4.5:1 on the card and on its own 12%
    /// wash. Core's generator cannot derive one yet (AWTD2-159); when it can, this follows.
    static func resolveAccentInk(_ raw: String?, accentHex: String, dark: Bool) -> String {
        let configured = resolveAccentHex(raw, fallback: "")
        if !configured.isEmpty { return configured }
        if accentHex.lowercased() == defaultAccentHex { return dark ? astridInk.dark : astridInk.light }
        guard let accent = rgb(accentHex) else { return dark ? astridInk.dark : astridInk.light }
        // The cards the tokens hold inks to: light `bg-hover`, dark `bg-secondary`.
        let card: RGB = dark ? (31, 41, 55) : (255, 255, 255)
        let toward: Double = dark ? 255 : 0
        let wash = over(accent, card, alpha: 0.12)
        for step in 0...20 {
            let t = Double(step) / 20
            let ink: RGB = (
                (accent.0 + (toward - accent.0) * t).rounded(),
                (accent.1 + (toward - accent.1) * t).rounded(),
                (accent.2 + (toward - accent.2) * t).rounded())
            if contrast(ink, card) >= 4.5 && contrast(ink, wash) >= 4.5 { return hex(ink) }
        }
        return hex((toward, toward, toward))
    }

    typealias RGB = (Double, Double, Double)

    /// The first six hex digits of a resolved colour as 0–255 channels; alpha is ignored.
    static func rgb(_ hex: String) -> RGB? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff), Double((value >> 8) & 0xff), Double(value & 0xff))
    }

    /// WCAG 2.x contrast ratio, as web's `lib/design/contrast.ts` computes it.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        func luminance(_ c: RGB) -> Double {
            func lin(_ v: Double) -> Double {
                let s = v / 255
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `top` at `alpha` over `under`, rounded per channel as the browser composites it.
    static func over(_ top: RGB, _ under: RGB, alpha: Double) -> RGB {
        ((top.0 * alpha + under.0 * (1 - alpha)).rounded(),
         (top.1 * alpha + under.1 * (1 - alpha)).rounded(),
         (top.2 * alpha + under.2 * (1 - alpha)).rounded())
    }

    private static func hex(_ c: RGB) -> String {
        String(format: "#%02X%02X%02X", Int(c.0), Int(c.1), Int(c.2))
    }

    /// Normalise a configured accent to a `#rrggbb` / `#rrggbbaa` string, or fall back.
    ///
    /// Deliberately total: a brand colour is chrome, not a feature, so a typo in it must
    /// render the default rather than throw or produce a transparent control. Exposed
    /// (rather than inlined) so the fallback behaviour is testable without a second bundle.
    static func resolveAccentHex(_ raw: String?, fallback: String = defaultAccentHex) -> String {
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

    /// Copy that tells the user where to email a task, with `Brand.inboundTaskEmail` as
    /// its one argument. The address used to be written into each translation, so a
    /// partner build still showed Astrid's (AITD-516).
    static func inboundTaskEmailCopy(_ key: String) -> String {
        String(format: NSLocalizedString(key, comment: ""), inboundTaskEmail)
    }

    /// The address an OpenClaw agent named `name` will get, e.g. `bob.oc@astrid.cc`.
    /// `settings.openclaw.agent_name_preview` is "%1$@.oc@%2$@" — name, then domain.
    static func agentAddressPreview(_ name: String) -> String {
        String(format: NSLocalizedString("settings.openclaw.agent_name_preview", comment: ""),
               name, agentEmailDomain)
    }

    // MARK: - Private

    /// Parse a hex string that `resolveAccentHex` has already validated.
    ///
    /// The `fallback` is belt-and-braces: resolution guarantees a parseable value, so
    /// this only fires if the two ever disagree, and `.clear` chrome is not an option.
    private static func color(_ hex: String, fallback: String) -> Color {
        Color(hex: hex) ?? Color(hex: fallback) ?? Color(red: 37/255, green: 99/255, blue: 235/255)
    }

    /// Read a non-empty string from the running bundle's Info.plist.
    private nonisolated static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unsubstituted build setting (`$(BRAND_NAME)`) is not a brand — ignore it.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
