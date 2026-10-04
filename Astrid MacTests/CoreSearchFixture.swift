//  CoreSearchFixture.swift
//  A throwaway astrid-core holding just the given tasks — for the search parity spec (AITD-459),
//  which runs the tests the Swift `TaskSearch` had against the core's `searchTasks`.

#if os(macOS)
import AstridCore
import Foundation
@testable import Astrid_Mac

enum CoreSearchFixture {
    /// Nothing is ever signed in: the session never reaches the network.
    final class NoCredentials: CoreCredentialStore, @unchecked Sendable {
        func get(key: String) -> String? { nil }
        func set(key: String, value: String) -> Bool { true }
        func delete(key: String) -> Bool { true }
    }

    /// An in-memory core whose cache holds exactly `tasks`.
    static func session(seeding tasks: [Task]) throws -> CoreSession {
        let session = try CoreSession(cachePath: ":memory:", credentials: NoCredentials(), background: false)
        var command = CoreCommand(kind: "seedCache")
        command.set("tasks", tasks)
        struct Seeded: Decodable { let seeded: Bool }
        _ = try session.runBlocking(command, as: Seeded.self)
        return session
    }
}
#endif
