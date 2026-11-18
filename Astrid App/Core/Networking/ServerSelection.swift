import Foundation

/// Which server this app talks to (ADEV-118, "bring your own server").
///
/// One App Store binary can sign in to a partner's own deployment of astrid-web instead of the
/// build's own, the way a Mastodon or Nextcloud client does. The person (or, later, their
/// company's device management) names the server on the sign-in screen; everything the app
/// sends goes there and nowhere else.
///
/// The choice is made while signed out and survives relaunches. Switching is `ServerSwitcher`'s
/// job, because a switch has to wipe what the previous server's account left on the device.
enum ServerSelection {
    /// Why something typed is not a server address.
    enum InputError: Error, Equatable {
        case empty
        /// Only https. A token and every task travel on this connection.
        case notHTTPS
        case invalid
    }

    /// The origin a person meant: `https://host[:port]`, lowercased host, no path.
    ///
    /// A bare host gets `https://`. A path, query or fragment is dropped, since every request the
    /// app makes starts at the origin (`/api/v1/...`), and someone pasting their sign-in page's
    /// address still means the server. Credentials in the URL are refused rather than dropped:
    /// that input was not meant for this field.
    static func origin(from input: String) -> Result<String, InputError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased() else { return .failure(.invalid) }
        guard scheme == "https" else { return .failure(.notHTTPS) }
        guard components.user == nil, components.password == nil,
              let host = components.host?.lowercased(), isPlausibleHost(host)
        else { return .failure(.invalid) }

        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.port = components.port
        guard let value = origin.string else { return .failure(.invalid) }
        return .success(value)
    }

    /// The server the app uses: the chosen one, else the build's own.
    static func resolve(custom: String?, brandDefault: String) -> String {
        guard let custom, !custom.isEmpty else { return brandDefault }
        return custom
    }

    /// Whether `origin` is somewhere other than the build's own server.
    static func isCustom(_ origin: String, brandDefault: String) -> Bool {
        normalized(origin) != normalized(brandDefault)
    }

    private static func normalized(_ origin: String) -> String {
        (try? Self.origin(from: origin).get()) ?? origin.lowercased()
    }

    /// Letters, digits, dots and hyphens (IDNs arrive punycoded), with at least one dot or a
    /// bracketed IPv6 literal. `localhost` is the developer's, through the DEBUG picker.
    private static func isPlausibleHost(_ host: String) -> Bool {
        if host.hasPrefix("[") { return host.hasSuffix("]") && host.count > 2 }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return host.contains(".")
            && !host.hasPrefix(".") && !host.hasSuffix(".")
            && host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// The server a company's device management sets (ADEV-122).
///
/// Managed App Configuration arrives in `UserDefaults` under `com.apple.configuration.managed`
/// on iOS and Mac alike. Two keys: `serverURL`, the server to use, and `serverLocked`, which
/// hides both ways to change it. An address that does not parse is ignored rather than pointing
/// the app at nothing. Keys for IT admins: docs/MANAGED_CONFIG.md.
struct ManagedServerConfig: Equatable {
    static let defaultsKey = "com.apple.configuration.managed"
    static let serverKey = "serverURL"
    static let lockedKey = "serverLocked"

    var server: String?
    var locked: Bool

    init(server: String? = nil, locked: Bool = false) {
        self.server = server
        self.locked = locked
    }

    init(_ configuration: [String: Any]?) {
        let raw = configuration?[Self.serverKey] as? String
        server = raw.flatMap { try? ServerSelection.origin(from: $0).get() }
        locked = (configuration?[Self.lockedKey] as? Bool)
            ?? (configuration?[Self.lockedKey] as? NSNumber)?.boolValue
            ?? false
    }
}

/// Where the chosen server is kept between launches.
struct ServerSelectionStore {
    static let key = "custom_server_url"

    let defaults: UserDefaults

    static var standard: ServerSelectionStore { ServerSelectionStore(defaults: .standard) }

    /// What device management set, if anything.
    var managed: ManagedServerConfig {
        ManagedServerConfig(defaults.dictionary(forKey: ManagedServerConfig.defaultsKey))
    }

    /// The server to use other than the build's own: device management's, else the person's.
    var custom: String? { managed.server ?? saved }

    /// Device management has fixed the server; nobody on the device can change it.
    var isLocked: Bool { managed.locked }

    /// The person's own choice. A stored value that no longer parses (an older build's, a hand
    /// edit) reads as nil rather than pointing the app at nothing.
    var saved: String? {
        guard let stored = defaults.string(forKey: Self.key) else { return nil }
        return try? ServerSelection.origin(from: stored).get()
    }

    /// Remember `origin`; nil, or the build's own server, forgets the choice.
    func save(_ origin: String?, brandDefault: String) {
        guard let origin, ServerSelection.isCustom(origin, brandDefault: brandDefault) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(origin, forKey: Self.key)
    }
}

/// Which server the saved sign-in belongs to (ADEV-122).
///
/// The server can change while the app is not running: device management pushes a new one, or
/// a developer changes the debug server. The Keychain still holds the previous server's session,
/// and the core would send it to the new server the moment it starts. `AppCore` asks this first
/// and wipes the sign-in when the answer is yes.
enum SessionServerGuard {
    static let key = "session_server"

    /// Record `current` and say whether the last recorded server was a different one. The first
    /// launch with this guard records without wiping.
    static func serverChanged(current: String, defaults: UserDefaults) -> Bool {
        let previous = defaults.string(forKey: key)
        defaults.set(current, forKey: key)
        guard let previous else { return false }
        return previous != current
    }
}

/// The server in use, as links and link handling need it (ADEV-120).
///
/// Thread-safe and nonisolated: link builders run everywhere. "Chosen" means the person picked
/// this server at sign-in and the app is talking to it. A developer's localhost or a UI-test
/// run's production override is not a choice, so links keep the build's own origin there.
enum ActiveServer {
    /// The origin every request goes to.
    static var origin: String { Constants.API.baseURL }

    /// Whether the app is on a server the person chose.
    static var isChosen: Bool { isChosen(origin: origin, chosen: ServerSelectionStore.standard.custom) }

    static func isChosen(origin: String, chosen: String?) -> Bool {
        guard let chosen else { return false }
        return chosen == origin
    }

    /// Where links to the person's data point: the chosen server, else the build's own web.
    static var linkOrigin: String { linkOrigin(origin: origin, chosen: isChosen) }

    static func linkOrigin(origin: String, chosen: Bool, brandOrigin: String = Brand.productionBaseURL) -> String {
        chosen ? origin : brandOrigin
    }

    /// The hosts whose https links the app opens in place: the chosen server's, else the
    /// build's own. Never both: a link to the build's own web, opened against a partner's
    /// server, would look the id up in the wrong place.
    static var webHosts: Set<String> { webHosts(origin: origin, chosen: isChosen) }

    static func webHosts(origin: String, chosen: Bool, brandHosts: Set<String> = Brand.webHosts) -> Set<String> {
        guard chosen, let host = URL(string: origin)?.host else { return brandHosts }
        return [host]
    }
}

/// Whether a server the person chose is new enough for this app (ADEV-121).
///
/// The app updates on our schedule and a partner's server on theirs. Below the level this app
/// needs, it says so by name ("this server needs an update") instead of signing in and failing
/// somewhere odd. Only a CHOSEN server is gated: the build's own server ships with the build.
/// Optional features follow the capability flags instead, so a newer app keeps working, with
/// less, against an older server. Policy: astrid-web `docs/deployment/WHITE_LABEL_COMPATIBILITY.md`.
enum ServerCompatibility {
    /// The level this app needs. 1: browser sign-in calls back on this app's own scheme
    /// (astrid-web ADEV-124), without which sign-in on a partner's server never returns.
    /// Raise it only for something the app cannot work without, never for an optional feature.
    static let requiredLevel = 1

    static func isTooOld(_ capabilities: ServerCapabilities, required: Int = requiredLevel) -> Bool {
        capabilities.meta.level < required
    }

    static func message(host: String) -> String {
        String(format: NSLocalizedString("server.error_too_old", comment: ""), host, Brand.appName)
    }
}
