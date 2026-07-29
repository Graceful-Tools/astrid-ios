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

    /// The brand the connected deployment presents itself as.
    ///
    /// One binary can point at several deployments, so the brand cannot be purely a
    /// build-time value any more than the capability set could be. The build's own
    /// `Brand` supplies the defaults — what the app shows before the first fetch, and
    /// what it falls back to for anything the server does not send.
    ///
    /// TEXT ONLY, and every field is validated. This is a string arriving over the
    /// network and rendered into the app's chrome; the DEBUG server picker lets a user
    /// point the app at an arbitrary host, so it is untrusted input in the only threat
    /// model that matters. Blank, overlong and control-character values fall back rather
    /// than render.
    ///
    /// Deliberately NOT here:
    ///   host / agentEmailDomain — trust boundaries. A server claiming a different brand
    ///     domain would be telling the client which cookies to clear and which Universal
    ///     Links belong to it.
    ///   accentColor — Theme resolves colours once at launch (`static let`) so no render
    ///     ever parses a hex string. Server-driven colour would mean an observable theme
    ///     and a cost on every colour read. Text is free to swap; colour is not.
    struct BrandInfo: Codable, Equatable {
        /// Longest value accepted. A name beyond this breaks the sign-in lockup, and an
        /// unbounded one is a cheap way to make the app unusable.
        static let maxValueLength = 64

        var appName: String?
        var wordmark: String?
        var slogan: String?
        var agentName: String?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appName = Self.sanitize(try c.decodeIfPresent(String.self, forKey: .appName))
            wordmark = Self.sanitize(try c.decodeIfPresent(String.self, forKey: .wordmark))
            slogan = Self.sanitize(try c.decodeIfPresent(String.self, forKey: .slogan))
            agentName = Self.sanitize(try c.decodeIfPresent(String.self, forKey: .agentName))
        }

        /// Trim, then reject anything that cannot be a brand value.
        static func sanitize(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= maxValueLength else { return nil }
            // Newlines and control characters would let a server inject extra lines into
            // the sign-in lockup.
            guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            return trimmed
        }

        // The build's value is the fallback for every field.

        var resolvedAppName: String { appName ?? Brand.appName }

        /// Falls back to the lowercased SERVER name, not to the build's wordmark — a
        /// deployment that sent "Acme" and no wordmark means Acme, not astrid.
        var resolvedWordmark: String {
            wordmark ?? appName?.lowercased() ?? Brand.wordmark
        }

        var resolvedSlogan: String { slogan ?? Brand.slogan }

        var resolvedAgentName: String {
            agentName ?? appName ?? Brand.agentName
        }
    }

    /// The brand's VOICE — reminder nags, and captions for the default lists.
    ///
    /// Not identity but personality: Astrid's "I die a little every time you ignore me"
    /// is the kind of line a partner replaces wholesale rather than translates. Native
    /// clients each shipped their own copy of the set, so a partner had to replace it
    /// once per platform with nothing keeping them in step.
    ///
    /// Absent for any deployment that overrides nothing, which is the common case — the
    /// endpoint carries what DIFFERS, so Astrid pays no bytes for this.
    struct BrandCopy: Codable, Equatable {
        struct Reminders: Codable, Equatable {
            var general: [String]?
            var due: [String]?
            var responses: [String]?

            init() {}

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                general = try c.decodeIfPresent([String].self, forKey: .general)
                due = try c.decodeIfPresent([String].self, forKey: .due)
                responses = try c.decodeIfPresent([String].self, forKey: .responses)
            }
        }

        var reminders: Reminders?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reminders = try c.decodeIfPresent(Reminders.self, forKey: .reminders)
        }
    }

    var auth = Auth()
    var sync = Sync()
    var integrations = Integrations()
    var services = Services()
    var brand = BrandInfo()
    var copy: BrandCopy?

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
        brand = try c.decodeIfPresent(BrandInfo.self, forKey: .brand) ?? BrandInfo()
        copy = try c.decodeIfPresent(BrandCopy.self, forKey: .copy)
    }
}
