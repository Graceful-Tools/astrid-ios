import Foundation

/// Caches user image URLs extracted from list member data
/// This avoids redundant lookups since we already fetch images via lists API
@MainActor
class UserImageCache {
    static let shared = UserImageCache()

    private static let persistedURLsKey = "UserImageCache.persistedURLs.v1"

    /// Cache: userId -> imageURL
    private var cache: [String: String]
    private let defaults: UserDefaults

    /// Internal so the cold-launch behavior can be tested with an isolated defaults suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cache = defaults.dictionary(forKey: Self.persistedURLsKey) as? [String: String] ?? [:]
    }

    // MARK: - Cache Operations

    /// Get cached image URL for a user
    func getImageURL(userId: String) -> String? {
        return cache[userId]
    }

    /// Store image URL for a user
    func setImageURL(_ imageURL: String?, for userId: String) {
        if store(imageURL, for: userId) { persist() }
    }

    /// Update cache from a User object
    func cacheUser(_ user: User) {
        setImageURL(user.image, for: user.id)
    }

    /// Update the in-memory cache only; says whether anything changed. The batch entry points
    /// call this per user and persist once — a sync used to write the whole dictionary to
    /// UserDefaults once per assignee, creator and comment author, on the main actor.
    @discardableResult
    private func store(_ imageURL: String?, for userId: String) -> Bool {
        guard let imageURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imageURL.isEmpty else {
            return cache.removeValue(forKey: userId) != nil
        }
        guard cache[userId] != imageURL else { return false }
        cache[userId] = imageURL
        return true
    }

    private func store(_ user: User) -> Bool {
        store(user.image, for: user.id)
    }

    /// Prepare the locally restored session user's avatar before cached task rows render.
    ///
    /// The URL lookup survives launch here; image bytes remain keyed by that absolute URL in
    /// `ImageCache`. Reading a warm disk entry into memory now avoids a visible initials-to-photo
    /// transition on the first My Tasks frame (AITD-283).
    func prepareForLaunch(_ user: User) {
        cacheUser(user)
        guard let imageURL = user.cachedImageURL,
              let url = URL(string: imageURL) else { return }
        _ = ImageCache.shared.get(url: url)
    }

    /// Update cache from list member data (called during list sync)
    func cacheFromLists(_ lists: [TaskList]) {
        var changed = false
        for list in lists {
            if let owner = list.owner {
                changed = store(owner) || changed
            }
            // listMembers is the canonical member source (legacy admins/members arrays are no
            // longer populated).
            for user in (list.listMembers ?? []).compactMap(\.user) {
                changed = store(user) || changed
            }
        }
        if changed { persist() }
    }

    /// Update cache from task data (assignee, creator, comment authors)
    func cacheFromTasks(_ tasks: [Task]) {
        var changed = false
        for task in tasks {
            if let assignee = task.assignee {
                changed = store(assignee) || changed
            }
            if let creator = task.creator {
                changed = store(creator) || changed
            }
            for author in (task.comments ?? []).compactMap(\.author) {
                changed = store(author) || changed
            }
        }
        if changed { persist() }
    }

    /// Clear all cached user images
    func clearCache() {
        cache.removeAll()
        defaults.removeObject(forKey: Self.persistedURLsKey)
        // Silent clear
    }

    /// Get cache count for debugging
    var count: Int {
        return cache.count
    }

    private func persist() {
        defaults.set(cache, forKey: Self.persistedURLsKey)
    }
}

// MARK: - User Extension for Cached Image URL

extension User {
    /// Get the user's image URL, falling back to UserImageCache if nil.
    /// Resolves relative paths against the API base URL and converts SVGs to PNGs for iOS compatibility.
    var cachedImageURL: String? {
        var url = self.image
        // Fall back to cached image URL
        if url == nil || url?.isEmpty == true {
            url = UserImageCache.shared.getImageURL(userId: self.id)
        }
        // An agent row can arrive with no image at all — `muse@astrid.cc` and `openclaw@astrid.cc`
        // both do — and without a URL there is nothing for `AgentAvatarAsset` to resolve, so every
        // avatar on both platforms fell through to its placeholder (AITD-428). The icon proxy is
        // keyed by mailbox and is the canonical source for these marks, so name it and let the
        // usual resolution take over: bundled asset first, network only if we do not ship one.
        if url == nil || url?.isEmpty == true, let mailbox = agentMailbox {
            url = "/api/v1/agent-icon/\(mailbox)"
        }
        guard var path = url, !path.isEmpty else { return nil }

        // iOS can't render SVG via AsyncImage — use PNG version instead
        if path.hasSuffix(".svg") {
            path = path.replacingOccurrences(of: ".svg", with: ".png")
        }
        // Resolve relative paths against API base URL
        if !path.hasPrefix("http") {
            let baseURL = Constants.API.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path = baseURL + path
        }
        return path
    }
}
