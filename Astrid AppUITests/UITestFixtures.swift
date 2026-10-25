import Foundation

/// The fixtures this run's account was seeded with, by id (AITD-527).
///
/// `scripts/run-tests.sh` mints an account per run (`uitest-account.ts --run <id>`,
/// AWTD-1328) and writes the seeder's `fixtures` document into `UITestSession.plist` next to
/// the cookie. A test that names a task through this — rather than "the first open row" or a
/// title literal — can then ask the server about that exact task (`UITestAPI`).
///
/// Nil on the shared-account path (`ASTRID_UITEST_COOKIE` passed by hand), which has no ids;
/// tests fall back to the shared seeder's names there.
struct UITestFixtures: Decodable {

    struct ListRef: Decodable {
        let id: String
        let name: String
        let projectId: String?
        let role: String?
    }

    struct TaskRef: Decodable {
        let id: String
        let title: String
        let completed: Bool?
        let dueDateTime: String?
        let commentId: String?
    }

    struct Lists: Decodable {
        let main: ListRef
        let board: ListRef?
        let shared: ListRef?
    }

    /// `classic` is an array; every other key is one named task (`dueToday`,
    /// `dailyRepeating`, `withComment`, …). Named ones are kept by key so a new seeder fixture
    /// is usable without a change here.
    struct Tasks: Decodable {
        let classic: [TaskRef]
        let named: [String: TaskRef]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            classic = try container.decodeIfPresent([TaskRef].self, forKey: Key(stringValue: "classic")) ?? []
            var named: [String: TaskRef] = [:]
            for key in container.allKeys where key.stringValue != "classic" {
                if let task = try? container.decode(TaskRef.self, forKey: key) {
                    named[key.stringValue] = task
                }
            }
            self.named = named
        }

        subscript(name: String) -> TaskRef? { named[name] }

        var all: [TaskRef] { classic + named.values.sorted { $0.id < $1.id } }
    }

    struct UserRef: Decodable {
        let id: String
        let email: String?
    }

    let runId: String
    /// The run's own user — absent from fixtures minted before AITD-528 read it.
    let user: UserRef?
    let lists: Lists
    let tasks: Tasks

    /// The seeded task with this exact title, if the run seeded one.
    func task(titled title: String) -> TaskRef? {
        tasks.all.first { $0.title == title }
    }

    /// Names the shared-account seeder uses, for tests that run on either path.
    static let defaultMainListName = "UI Test List"
    static let classicTitlePrefix = "UITEST Fixture"

    static func decode(_ json: String) -> UITestFixtures? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UITestFixtures.self, from: data)
    }
}
