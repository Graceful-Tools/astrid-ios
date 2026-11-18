import Foundation

/// Asks a server whether it is one this app can sign in to, before the app is pointed at it
/// (ADEV-118).
///
/// `GET /api/v1/capabilities` is unauthenticated and every astrid-web deployment serves it, so a
/// typo, a captive portal or someone else's website fails here with a message, rather than after
/// the switch as a sign-in that never works.
struct ServerProbe {
    enum Failure: Error, Equatable {
        /// Nothing answered: a typo in the host, no network.
        case unreachable
        /// Something answered, but not an Astrid server.
        case notAstrid
    }

    let session: URLSession

    static var live: ServerProbe {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return ServerProbe(session: URLSession(configuration: configuration))
    }

    /// What the server at `origin` offers, or why it is not one to use.
    func check(_ origin: String) async throws -> ServerCapabilities {
        guard let url = URL(string: origin + "/api/v1/capabilities") else { throw Failure.unreachable }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AnalyticsPlatformHeader.current, forHTTPHeaderField: AnalyticsPlatformHeader.headerName)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              Self.looksLikeAstrid(data),
              let capabilities = try? JSONDecoder().decode(ServerCapabilities.self, from: data)
        else { throw Failure.notAstrid }
        return capabilities
    }

    /// The capabilities document has a `meta.apiVersion` and an `auth` section. Every decodable
    /// field of `ServerCapabilities` is optional, so decoding alone would accept any JSON object.
    static func looksLikeAstrid(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meta = object["meta"] as? [String: Any],
              let version = meta["apiVersion"] as? String, !version.isEmpty,
              object["auth"] is [String: Any]
        else { return false }
        return true
    }
}

/// Points the app at another server, or back at the build's own (ADEV-118).
///
/// A switch is a clean break. Nothing from one server's account may show, or be sent, under
/// another's, so it signs out first (which wipes the core's cache and journal, the Keychain and
/// every cache) and then restarts the core against the new server.
@MainActor
final class ServerSwitcher {
    struct Dependencies {
        var store: ServerSelectionStore
        var brandDefault: String
        var currentServer: () -> String
        var reloadServer: () -> Void
        var isSignedIn: () -> Bool
        var signOut: () async -> Void
        var clearCookies: (_ host: String) -> Void
        var restartCore: () async -> Void
        var resetCapabilities: () -> Void
        var refreshCapabilities: () async -> Void
        /// Note which server the sign-in now belongs to (`SessionServerGuard`).
        var recordSessionServer: (String) -> Void = { _ in }
    }

    static let shared = ServerSwitcher(.live)

    private let deps: Dependencies

    init(_ deps: Dependencies) {
        self.deps = deps
    }

    /// The server in use, and whether it is someone else's.
    var currentServer: String { deps.currentServer() }
    /// The person chose this server; a developer's localhost or a test override is not a choice.
    var isCustom: Bool { ActiveServer.isChosen(origin: deps.currentServer(), chosen: deps.store.custom) }

    /// The host to show a person: `tasks.example.com`, not the whole origin.
    var currentHost: String { URL(string: deps.currentServer())?.host ?? deps.currentServer() }

    /// Device management has fixed the server (ADEV-122): no way to change it is offered.
    var isLocked: Bool { deps.store.isLocked }

    /// Use `origin` from now on; nil goes back to the build's own server. Returns whether the
    /// server changed. Refused while device management has locked the server.
    @discardableResult
    func use(_ origin: String?) async -> Bool {
        guard !isLocked else { return false }
        deps.store.save(origin, brandDefault: deps.brandDefault)
        return await reconcile()
    }

    private var isSwitching = false

    /// Make the app match the configured server: the person's choice, or device management's,
    /// which can change at any moment. Nothing happens unless the server actually moved.
    @discardableResult
    func reconcile() async -> Bool {
        guard !isSwitching else { return false }
        isSwitching = true
        defer { isSwitching = false }

        let previous = deps.currentServer()
        deps.reloadServer()
        let next = deps.currentServer()
        guard next != previous else { return false }

        if deps.isSignedIn() { await deps.signOut() }
        if let host = URL(string: previous)?.host { deps.clearCookies(host) }
        await deps.restartCore()
        deps.recordSessionServer(next)
        // The old server's brand and sign-in methods must not show while the new one answers.
        deps.resetCapabilities()
        await deps.refreshCapabilities()
        return true
    }

    private var managedObserver: NSObjectProtocol?

    /// Follow device management from now on (ADEV-122). Called once at launch.
    func watchManagedConfiguration() {
        guard managedObserver == nil else { return }
        lastManaged = deps.store.managed
        managedObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in await self?.managedConfigurationMayHaveChanged() }
        }
    }

    private var lastManaged: ManagedServerConfig?

    /// Every defaults write posts the same notification; act only when device management's
    /// configuration is what moved.
    @discardableResult
    func managedConfigurationMayHaveChanged() async -> Bool {
        let managed = deps.store.managed
        guard managed != lastManaged else { return false }
        lastManaged = managed
        return await reconcile()
    }
}

extension ServerSwitcher.Dependencies {
    static var live: Self {
        Self(
            store: .standard,
            brandDefault: Brand.productionBaseURL,
            currentServer: { Constants.API.baseURL },
            reloadServer: { Constants.API.reloadBaseURL() },
            isSignedIn: { AuthManager.shared.isAuthenticated },
            signOut: { try? await AuthManager.shared.signOut() },
            clearCookies: { host in
                let storage = HTTPCookieStorage.shared
                for cookie in storage.cookies ?? [] where cookie.domain.trimmingCharacters(in: ["."]) == host
                    || host.hasSuffix("." + cookie.domain.trimmingCharacters(in: ["."])) {
                    storage.deleteCookie(cookie)
                }
            },
            restartCore: { await AppCore.shared.restart() },
            resetCapabilities: { ServerCapabilityService.shared.reset() },
            refreshCapabilities: { await ServerCapabilityService.shared.refresh() },
            recordSessionServer: { _ = SessionServerGuard.serverChanged(current: $0, defaults: .standard) })
    }
}
