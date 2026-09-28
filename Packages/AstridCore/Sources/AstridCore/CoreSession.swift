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
    ///   - baseURL: the server; the core's default (astrid.cc) when nil.
    ///   - background: start the loops that keep the app current. A test, and a UI-test build that
    ///     must never reach the network, pass `false`.
    public init(
        cachePath: String, baseURL: String? = nil, platform: CorePlatform? = nil,
        credentials: CoreCredentialStore, background: Bool
    ) throws {
        struct Config: Encodable {
            let cachePath: String
            let baseUrl: String?
            let platform: String?
        }
        client = try CoreClient.start(
            configJson: CoreJSON.encode(
                Config(cachePath: cachePath, baseUrl: baseURL, platform: platform?.rawValue)),
            credentials: credentials, background: background)
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
