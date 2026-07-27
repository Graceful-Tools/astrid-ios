import Foundation

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

    // MARK: - Derived

    /// Canonical production origin, e.g. `https://astrid.cc`.
    static var productionBaseURL: String { "https://\(host)" }

    /// Hosts that count as this brand's web app, for Universal Link routing.
    static var webHosts: Set<String> { [host, "www.\(host)"] }

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

    /// Read a non-empty string from the running bundle's Info.plist.
    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unsubstituted build setting (`$(BRAND_NAME)`) is not a brand — ignore it.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
