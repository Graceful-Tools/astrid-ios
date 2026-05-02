import Foundation

/// Helper for managing list images with fallback to default icons
/// Swift equivalent of lib/default-images.ts
struct DefaultListImage {
    let name: String
    let filename: String
    let theme: String
    let color: String
    let description: String
}

struct ListImageHelper {
    /// Default list images matching web app (/icons/default_list_0-3.png)
    static let defaultImages: [DefaultListImage] = [
        DefaultListImage(
            name: "Default List 0",
            filename: "/icons/default_list_0.png",
            theme: "default",
            color: "#3b82f6",
            description: "Default list icon"
        ),
        DefaultListImage(
            name: "Default List 1",
            filename: "/icons/default_list_1.png",
            theme: "default",
            color: "#10b981",
            description: "Default list icon"
        ),
        DefaultListImage(
            name: "Default List 2",
            filename: "/icons/default_list_2.png",
            theme: "default",
            color: "#f59e0b",
            description: "Default list icon"
        ),
        DefaultListImage(
            name: "Default List 3",
            filename: "/icons/default_list_3.png",
            theme: "default",
            color: "#8b5cf6",
            description: "Default list icon"
        )
    ]

    /// Get a random default image
    static func getRandomDefaultImage() -> DefaultListImage {
        return defaultImages.randomElement() ?? defaultImages[0]
    }

    /// Simple hash function to convert string to number
    private static func simpleHash(_ string: String) -> Int {
        var hash = 0
        for char in string.unicodeScalars {
            hash = ((hash << 5) &- hash) &+ Int(char.value)
            hash = hash & hash // Convert to 32-bit integer
        }
        return abs(hash)
    }

    /// Get a consistent default image for a list based on its ID
    /// Uses hash of list ID to ensure same list always gets same default image
    static func getConsistentDefaultImage(listId: String) -> DefaultListImage {
        guard !listId.isEmpty else {
            return defaultImages[0]
        }

        let hash = simpleHash(listId)
        let index = hash % defaultImages.count
        return defaultImages[index]
    }

    /// Get the image URL for a list with fallback logic
    /// Priority: imageUrl -> coverImageUrl -> consistent default image
    static func getListImageUrl(list: TaskList) -> String {
        if let imageUrl = list.imageUrl, !imageUrl.isEmpty {
            return imageUrl
        }

        if let coverImageUrl = list.coverImageUrl, !coverImageUrl.isEmpty {
            return coverImageUrl
        }

        return getConsistentDefaultImage(listId: list.id).filename
    }

    /// Get the full URL for a list image (handling relative paths)
    static func getFullImageUrl(list: TaskList, baseURL: String = Constants.API.baseURL) -> URL? {
        let imageUrl = getListImageUrl(list: list)

        // If it's already a full URL, return it
        if imageUrl.hasPrefix("http://") || imageUrl.hasPrefix("https://") {
            return URL(string: imageUrl)
        }

        // Handle API secure file paths — accepts both /api/v1/secure-files/...
        // (current) and legacy /api/secure-files/... (older URLs persisted server-side).
        if imageUrl.hasPrefix("/api/") {
            return URL(string: baseURL + imageUrl)
        }

        // Handle relative paths (/icons/...)
        if imageUrl.hasPrefix("/") {
            return URL(string: baseURL + imageUrl)
        }

        // Fallback - treat as relative path
        return URL(string: baseURL + "/" + imageUrl)
    }
}
