import Foundation

/// What the connected deployment actually offers.
///
/// Task 97208a72. Capabilities belong to the SERVER, not to this build: one binary can
/// point at different deployments (the DEBUG server picker does exactly that), so the
/// app cannot know at compile time whether Google Tasks sync exists. It asks
/// `GET /api/v1/capabilities`.
///
/// This is presentation only. Every capability is enforced server-side on its own
/// routes, so a stale or missing response costs the user a 404, never access they
/// should not have had.
///
/// Every field decodes with `decodeIfPresent ?? default`, not the synthesized decoder:
/// Swift's synthesized `init(from:)` THROWS on a missing key even when the property has
/// a default value, so a server that omits a section — an older deployment, or a newer
/// one that has reorganised — would fail the whole decode and blank out every capability.
struct ServerCapabilities: Codable, Equatable {

    struct Auth: Codable, Equatable {
        var google = true
        var apple = true
        var passkey = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            google = try c.decodeIfPresent(Bool.self, forKey: .google) ?? true
            apple = try c.decodeIfPresent(Bool.self, forKey: .apple) ?? true
            passkey = try c.decodeIfPresent(Bool.self, forKey: .passkey) ?? true
        }
    }

    struct Sync: Codable, Equatable {
        var googleTasks = true
        var githubIssues = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            googleTasks = try c.decodeIfPresent(Bool.self, forKey: .googleTasks) ?? true
            githubIssues = try c.decodeIfPresent(Bool.self, forKey: .githubIssues) ?? true
        }
    }

    struct Integrations: Codable, Equatable {
        var mcp = true
        var openclaw = true
        var chatgptActions = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mcp = try c.decodeIfPresent(Bool.self, forKey: .mcp) ?? true
            openclaw = try c.decodeIfPresent(Bool.self, forKey: .openclaw) ?? true
            chatgptActions = try c.decodeIfPresent(Bool.self, forKey: .chatgptActions) ?? true
        }
    }

    struct Services: Codable, Equatable {
        var emailToTask = true
        var calendarFeed = true

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            emailToTask = try c.decodeIfPresent(Bool.self, forKey: .emailToTask) ?? true
            calendarFeed = try c.decodeIfPresent(Bool.self, forKey: .calendarFeed) ?? true
        }
    }

    var auth = Auth()
    var sync = Sync()
    var integrations = Integrations()
    var services = Services()

    /// Assume everything is available.
    ///
    /// Used before the first fetch and when the request fails — including against an
    /// older server that has no such endpoint. Failing OPEN is deliberate: hiding a
    /// feature the server does support is a worse outcome than showing an entry point
    /// that answers 404, and the server is the real boundary either way.
    static let permissive = ServerCapabilities()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auth = try c.decodeIfPresent(Auth.self, forKey: .auth) ?? Auth()
        sync = try c.decodeIfPresent(Sync.self, forKey: .sync) ?? Sync()
        integrations = try c.decodeIfPresent(Integrations.self, forKey: .integrations) ?? Integrations()
        services = try c.decodeIfPresent(Services.self, forKey: .services) ?? Services()
    }
}
