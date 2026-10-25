import Foundation
import XCTest

/// Reads what the server persisted, so a journey asserts state rather than pixels (AITD-527).
///
/// A row that shows a tick proves the app drew one. Whether the completion reached the
/// server — through `TaskService.completeTask`, the Outbox and the core — is a separate claim,
/// and until this helper only one test made it, by reopening the task and reading the chip
/// (`TaskDueDateClearUITests`). This asks `/api/v1` directly with the run's own session cookie.
///
/// Every path here is in `docs/API_ENDPOINTS.md`. It talks to the same host as the app under
/// test (`UITestLaunch.baseURL`), so a `-uiTestBaseURL` staging run checks staging.
enum UITestAPI {

    struct Task {
        let id: String
        let title: String
        let completed: Bool
        let dueDateTime: String?
        let listIds: [String]
        let description: String
        let priority: Int
        let statusRole: String?
        let repeating: String?

        init?(_ json: [String: Any]) {
            guard let id = json["id"] as? String else { return nil }
            self.id = id
            title = json["title"] as? String ?? ""
            completed = json["completed"] as? Bool ?? false
            dueDateTime = json["dueDateTime"] as? String
            description = json["description"] as? String ?? ""
            priority = json["priority"] as? Int ?? 0
            statusRole = json["statusRole"] as? String
            repeating = json["repeating"] as? String
            if let ids = json["listIds"] as? [String] {
                listIds = ids
            } else {
                listIds = (json["lists"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            }
        }
    }

    struct List {
        let id: String
        let name: String
        /// This user's role on it, from `listMembers` — nil when they are not a member row
        /// (an owner is the list's `ownerId`, not a member).
        let memberRole: String?
        let ownerId: String?

        init?(_ json: [String: Any], userId: String?) {
            guard let id = json["id"] as? String else { return nil }
            self.id = id
            name = json["name"] as? String ?? ""
            ownerId = json["ownerId"] as? String
            let members = json["listMembers"] as? [[String: Any]] ?? []
            memberRole = members.first { member in
                let memberUser = member["userId"] as? String
                    ?? (member["user"] as? [String: Any])?["id"] as? String
                return userId != nil && memberUser == userId
            }?["role"] as? String
        }
    }

    /// Nil without a session — there is nothing to ask the server as.
    static var isAvailable: Bool { UITestLaunch.sessionCookie != nil }

    static func task(id: String) throws -> Task? {
        let json = try get("/api/v1/tasks/\(id)")
        return (json?["task"] as? [String: Any]).flatMap(Task.init)
    }

    static func tasks(inList listId: String) throws -> [Task] {
        let json = try get("/api/v1/tasks?listId=\(listId)&limit=1000")
        return (json?["tasks"] as? [[String: Any]] ?? []).compactMap(Task.init)
    }

    /// Every task this account can see — its own lists, no list, and the public lists it has.
    static func allTasks() throws -> [Task] {
        let json = try get("/api/v1/tasks?limit=1000")
        return (json?["tasks"] as? [[String: Any]] ?? []).compactMap(Task.init)
    }

    static func lists(userId: String? = nil) throws -> [List] {
        let json = try get("/api/v1/lists")
        return (json?["lists"] as? [[String: Any]] ?? []).compactMap { List($0, userId: userId) }
    }

    static func comments(taskId: String) throws -> [[String: Any]] {
        let json = try get("/api/v1/tasks/\(taskId)/comments")
        return json?["comments"] as? [[String: Any]] ?? []
    }

    /// Polls until the server's copy of the task satisfies `condition`, and returns it.
    ///
    /// A poll, not a single read: the app writes through the Outbox, so the server catches up a
    /// moment after the screen does. The failure names what was last seen, so "never synced"
    /// and "synced the wrong value" read differently.
    @discardableResult
    static func waitForTask(id: String,
                            timeout: TimeInterval = 20,
                            _ what: String,
                            until condition: (Task) -> Bool) throws -> Task {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Task?
        repeat {
            last = try task(id: id)
            if let task = last, condition(task) { return task }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        let seen = last.map { "completed=\($0.completed) due=\($0.dueDateTime ?? "nil") lists=\($0.listIds)" }
            ?? "no task"
        throw UITestFailure("Server never showed \(what) for task \(id) within \(Int(timeout))s — last saw \(seen)")
    }

    /// Polls until a task with exactly this title exists and satisfies `condition` — for a task
    /// the journey created, whose id only the server knows.
    @discardableResult
    static func waitForTask(titled title: String,
                            timeout: TimeInterval = 20,
                            _ what: String = "the task",
                            until condition: (Task) -> Bool = { _ in true }) throws -> Task {
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [Task] = []
        repeat {
            seen = try allTasks().filter { $0.title == title }
            if let task = seen.first(where: condition) { return task }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        let last = seen.map { "completed=\($0.completed) lists=\($0.listIds)" }.joined(separator: "; ")
        throw UITestFailure("Server never showed \(what) titled \"\(title)\" within \(Int(timeout))s — "
                            + (seen.isEmpty ? "no task with that title" : "last saw \(last)"))
    }

    /// The same poll for a list, by name.
    @discardableResult
    static func waitForList(named name: String, timeout: TimeInterval = 20) throws -> List {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let list = try lists().first(where: { $0.name == name }) { return list }
            Thread.sleep(forTimeInterval: 1)
        } while Date() < deadline
        throw UITestFailure("Server never showed a list named \"\(name)\" within \(Int(timeout))s")
    }

    // MARK: - Transport

    private static func get(_ path: String) throws -> [String: Any]? {
        guard let cookie = UITestLaunch.sessionCookie else {
            throw UITestFailure("UITestAPI needs a session — run `npm run test:ui`, which mints one")
        }
        guard let url = URL(string: UITestLaunch.baseURL + path) else {
            throw UITestFailure("Bad API URL: \(UITestLaunch.baseURL + path)")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let done = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?)
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            result = (data, response, error)
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 20) == .success else {
            throw UITestFailure("GET \(path) timed out")
        }
        if let error = result.2 { throw UITestFailure("GET \(path) failed: \(error.localizedDescription)") }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status), let data = result.0 else {
            throw UITestFailure("GET \(path) answered \(status)")
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
