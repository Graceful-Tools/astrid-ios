import Foundation

/// Caches user image URLs extracted from list member data
/// This avoids redundant lookups since we already fetch images via lists API
@MainActor
class UserImageCache {
    static let shared = UserImageCache()

    /// Cache: userId -> imageURL
    private var cache: [String: String] = [:]

    private init() {}

    // MARK: - Cache Operations

    /// Get cached image URL for a user
    func getImageURL(userId: String) -> String? {
        return cache[userId]
    }

    /// Store image URL for a user
    func setImageURL(_ imageURL: String?, for userId: String) {
        guard let imageURL = imageURL, !imageURL.isEmpty else {
            return // Don't cache nil/empty URLs
        }
        cache[userId] = imageURL
    }

    /// Update cache from a User object
    func cacheUser(_ user: User) {
        setImageURL(user.image, for: user.id)
    }

    /// Update cache from list member data (called during list sync)
    func cacheFromLists(_ lists: [TaskList]) {
        var count = 0

        for list in lists {
            // Cache owner
            if let owner = list.owner {
                cacheUser(owner)
                count += 1
            }

            // Cache from listMembers — canonical member source (legacy
            // admins/members arrays are no longer populated).
            if let listMembers = list.listMembers {
                for listMember in listMembers {
                    if let user = listMember.user {
                        cacheUser(user)
                        count += 1
                    }
                }
            }
        }

        // Silently cache - no logging needed during normal sync
    }

    /// Update cache from task data (assignee, creator, comment authors)
    func cacheFromTasks(_ tasks: [Task]) {
        for task in tasks {
            if let assignee = task.assignee {
                cacheUser(assignee)
            }
            if let creator = task.creator {
                cacheUser(creator)
            }
            if let comments = task.comments {
                for comment in comments {
                    if let author = comment.author {
                        cacheUser(author)
                    }
                }
            }
        }
    }

    /// Clear all cached user images
    func clearCache() {
        cache.removeAll()
        // Silent clear
    }

    /// Get cache count for debugging
    var count: Int {
        return cache.count
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
