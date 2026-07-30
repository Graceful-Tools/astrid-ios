import Foundation

/// Locally cached brand voice — the reminder nags this deployment wants used.
///
/// Task 97208a72. Mirrors `lib/brand/copy.ts` on the web, and is fed from the `copy`
/// block of `GET /api/v1/capabilities`.
///
/// CACHED, not read live, for two reasons:
///
///   The nags render in `ReminderView` the moment it appears — before any capabilities
///   fetch has necessarily completed, and while offline. Reading through the network
///   service would show a partner's users Astrid's nags whenever the last fetch had not
///   landed, which is a visible wrong-brand bug rather than a missing feature.
///
///   `ServerCapabilityService` is `@MainActor`; a plain `UserDefaults`-backed store is
///   readable from anywhere, so this does not constrain where the copy can be used.
///
/// SCOPE, stated plainly because an earlier version of this comment got it wrong: these
/// nags reach the IN-APP reminder view only. Scheduled `UNNotification` bodies are the
/// task's own title with a fixed "Task Due Soon" heading (`NotificationManager`) and do
/// not read this at all. Localising and branding that heading is separate work.
///
/// Everything here is untrusted input from an unauthenticated endpoint, so it is
/// sanitized on the way IN — once, at store time, rather than on every read.
final class BrandCopyStore {

    /// Which set of nags. Mirrors `BrandReminderCopy` on the web.
    enum ReminderKind: String, CaseIterable {
        case general, due, responses
    }

    /// Most nags accepted per set. Unbounded storage handed to us by an unauthenticated
    /// endpoint is a denial-of-service, not a brand voice.
    static let maxSetSize = 200

    /// Longest single nag. A notification body far beyond this is truncated by the
    /// system anyway, so accepting it only wastes storage.
    static let maxNagLength = 300

    static let shared = BrandCopyStore(defaults: .standard)

    private let defaults: UserDefaults
    private let storageKey = "brand.copy.reminders"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Reading

    /// The brand's nags for this kind, or nil to use the app's built-in set.
    ///
    /// nil rather than an empty array on purpose: "no override" and "an override that is
    /// empty" must not be confused, or a malformed brand profile would fire blank
    /// notifications instead of falling back.
    func reminders(_ kind: ReminderKind) -> [String]? {
        guard let stored = defaults.dictionary(forKey: storageKey) as? [String: [String]],
              let set = stored[kind.rawValue],
              !set.isEmpty else { return nil }
        return set
    }

    // MARK: - Writing

    /// Replace the cached voice with what the server just sent.
    ///
    /// Passing nil (or a block with no reminders) CLEARS the cache. A deployment that
    /// drops its override must revert the app to the built-in voice rather than leave
    /// the previous brand's nags cached indefinitely.
    func store(_ copy: ServerCapabilities.BrandCopy?) {
        var sanitized: [String: [String]] = [:]

        if let reminders = copy?.reminders {
            let sets: [(ReminderKind, [String]?)] = [
                (.general, reminders.general),
                (.due, reminders.due),
                (.responses, reminders.responses),
            ]
            for (kind, raw) in sets {
                if let cleaned = Self.sanitize(raw) {
                    sanitized[kind.rawValue] = cleaned
                }
            }
        }

        if sanitized.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(sanitized, forKey: storageKey)
        }
    }

    /// Drop blanks and absurd lengths, and cap the count.
    ///
    /// Returns nil when nothing usable survives. An empty set is treated as "not
    /// supplied", matching the web: a brand that wants no nags at all should turn
    /// reminders off, not ship an empty set that fires a blank notification.
    static func sanitize(_ raw: [String]?) -> [String]? {
        guard let raw, !raw.isEmpty else { return nil }
        let cleaned = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= maxNagLength }
            .prefix(maxSetSize)
        return cleaned.isEmpty ? nil : Array(cleaned)
    }

    // MARK: - Testing

    /// Set the general nags directly. Tests only — the wiring from ReminderConstants
    /// through to a notification body is the thing worth pinning, and driving it through
    /// a live fetch would test the network instead.
    func replaceForTesting(general: [String]?) {
        if let general {
            defaults.set([ReminderKind.general.rawValue: general], forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}
