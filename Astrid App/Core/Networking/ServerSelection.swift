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

/// Where the chosen server is kept between launches.
struct ServerSelectionStore {
    static let key = "custom_server_url"

    let defaults: UserDefaults

    static var standard: ServerSelectionStore { ServerSelectionStore(defaults: .standard) }

    /// The chosen server, or nil for the build's own. A stored value that no longer parses (an
    /// older build's, a hand edit) reads as nil rather than pointing the app at nothing.
    var custom: String? {
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
