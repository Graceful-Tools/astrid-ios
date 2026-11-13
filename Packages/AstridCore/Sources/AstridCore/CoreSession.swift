import AstridCoreBindings
import Foundation

/// Credentials at rest, implemented by the app over the Keychain. Synchronous, because the
/// Keychain is.
public typealias CoreCredentialStore = AstridCoreBindings.CredentialStore

/// Told when the core's cache moves, on one of the core's threads — hop to where you draw.
public typealias CoreChangeListener = AstridCoreBindings.ChangeListener

/// Which client this is, stated on every request (`x-platform`), exactly as the server matches it.
public enum CorePlatform: String, Sendable {
    case ios = "ios-app"
    case mac = "mac-app"
}

/// A running astrid-core client — its cache, its Outbox and, when started with `background`, the
/// loops that keep them current (sync, delivery, the live stream, reminders).
///
/// The client door: every command is a value (`astrid_core::app::Command`) sent as JSON in the
/// API wire shape and answered in the core's envelope. The work runs on the core's own threads;
/// awaiting an answer never blocks the caller's.
public final class CoreSession: Sendable {
    private let client: CoreClient

    /// - Parameters:
    ///   - cachePath: the SQLite file the cache lives in, or `":memory:"` for a test.
    ///   - baseURL: the server. Always named: a core built with `require-base-url` has no default
    ///     and refuses to start without one, so a white-label binary never reaches astrid.cc by
    ///     omission (AITD-651, astrid-web AWTD-1627). A test names any server and passes
    ///     `background: false`, so it is never reached.
    ///   - background: start the loops that keep the app current. A test, and a UI-test build that
    ///     must never reach the network, pass `false`.
    ///   - urlScheme: the scheme this build registers for its sign-in callback, without `://`;
    ///     the core's `astrid` when nil. A white-label build names its own (AWTD2-95, AITD-616).
    ///   - handoffClientId: the id the server's desktop hand-off registry knows this app by; the
    ///     platform's own when nil.
    public init(
        cachePath: String, baseURL: String, platform: CorePlatform? = nil,
        urlScheme: String? = nil, handoffClientId: String? = nil,
        credentials: CoreCredentialStore, background: Bool
    ) throws {
        client = try CoreClient.start(
            configJson: Self.configJSON(cachePath: cachePath, baseURL: baseURL, platform: platform,
                                        urlScheme: urlScheme, handoffClientId: handoffClientId),
            credentials: credentials, background: background)
        // The rules door draws markdown too, and its relative links open on this same server.
        CoreRules.markdownOrigin = baseURL
    }

    /// The start config as the core reads it. The server is always sent; any other value left nil
    /// is OMITTED, not sent empty: absence is how a shell asks for the core's default, and the core ignores a key it does not know, so
    /// the encoding is the only place a misspelled key would show (tested).
    static func configJSON(cachePath: String, baseURL: String, platform: CorePlatform?,
                           urlScheme: String?, handoffClientId: String?) throws -> String {
        struct Config: Encodable {
            let cachePath: String
            let baseUrl: String
            let platform: String?
            let urlScheme: String?
            let handoffClientId: String?
        }
        return try CoreJSON.encode(Config(cachePath: cachePath, baseUrl: baseURL, platform: platform?.rawValue,
                                          urlScheme: urlScheme, handoffClientId: handoffClientId))
    }

    /// Run one command and decode its answer.
    public func run<Answer: Decodable>(
        _ command: some Encodable, as answer: Answer.Type = Answer.self
    ) async throws -> Answer {
        try CoreJSON.answer(await client.run(request: CoreJSON.encode(command)), as: answer)
    }

    /// Run one command whose answer is only whether it worked.
    public func run(_ command: some Encodable) async throws {
        _ = try await run(command, as: Empty.self)
    }

    /// Run one command and wait on this thread for its answer. For the read that must land before
    /// the first frame, and nothing else — every other call awaits `run`.
    public func runBlocking<Answer: Decodable>(
        _ command: some Encodable, as answer: Answer.Type = Answer.self
    ) throws -> Answer {
        try CoreJSON.answer(client.runBlocking(request: CoreJSON.encode(command)), as: answer)
    }

    /// Hear every change to the cache from now on. Subscribe once, not per screen.
    public func subscribe(_ listener: CoreChangeListener) {
        client.subscribe(listener: listener)
    }

    /// Ask the background loops to stop. Commands still run afterwards.
    public func stop() {
        client.stop()
    }

    /// The version of astrid-core this build links.
    public static var coreVersion: String { AstridCoreBindings.coreVersion() }

    private struct Empty: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
