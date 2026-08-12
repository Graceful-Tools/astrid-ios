import Foundation

/// The pastel placeholder images a list can use instead of an uploaded photo (Task 9a9d24bd).
///
/// Shared, and deliberately UI-free. This list used to be a `private let` inside iOS's
/// `ImagePickerView` — a UIKit view — so the Mac had no way to offer the same images without
/// copying them, which is how two platforms end up with different sets of pictures.
///
/// The paths are a cross-platform contract: web serves these files, and both clients store the
/// path string on `TaskList.imageUrl`. A placeholder therefore needs no upload and no list id,
/// which is why it can be chosen while a list is still being created.
enum ListImagePlaceholders {

    struct Placeholder: Identifiable, Equatable {
        /// Stable id — the path, since that is what gets stored and what must not drift.
        var id: String { path }
        let name: String
        /// Swatch colour, for rendering the choice before the image loads.
        let colorHex: String
        /// What lands in `TaskList.imageUrl`.
        let path: String
    }

    /// All 16, in the order both platforms present them.
    static let all: [Placeholder] = [
        Placeholder(name: "Lavender",   colorHex: "#E6E6FA", path: "/images/placeholders/lavender.png"),
        Placeholder(name: "Mint",       colorHex: "#F0FFF0", path: "/images/placeholders/mint.png"),
        Placeholder(name: "Peach",      colorHex: "#FFEAA7", path: "/images/placeholders/peach.png"),
        Placeholder(name: "Coral",      colorHex: "#FFB3BA", path: "/images/placeholders/coral.png"),
        Placeholder(name: "Sky",        colorHex: "#AED6F1", path: "/images/placeholders/sky.png"),
        Placeholder(name: "Sage",       colorHex: "#C8E6C9", path: "/images/placeholders/sage.png"),
        Placeholder(name: "Rose",       colorHex: "#F8BBD9", path: "/images/placeholders/rose.png"),
        Placeholder(name: "Butter",     colorHex: "#FFF9C4", path: "/images/placeholders/butter.png"),
        Placeholder(name: "Periwinkle", colorHex: "#CCCCFF", path: "/images/placeholders/periwinkle.png"),
        Placeholder(name: "Seafoam",    colorHex: "#B2DFDB", path: "/images/placeholders/seafoam.png"),
        Placeholder(name: "Apricot",    colorHex: "#FFE0B2", path: "/images/placeholders/apricot.png"),
        Placeholder(name: "Lilac",      colorHex: "#E1BEE7", path: "/images/placeholders/lilac.png"),
        Placeholder(name: "Blush",      colorHex: "#FFB7C5", path: "/images/placeholders/blush.png"),
        Placeholder(name: "Powder",     colorHex: "#B0E0E6", path: "/images/placeholders/powder.png"),
        Placeholder(name: "Cream",      colorHex: "#F5F5DC", path: "/images/placeholders/cream.png"),
        Placeholder(name: "Pearl",      colorHex: "#F0F0F0", path: "/images/placeholders/pearl.png"),
    ]

    /// Is this stored `imageUrl` one of ours? Distinguishes a placeholder from an upload, which
    /// matters because an upload can be deleted server-side and a placeholder cannot.
    static func isPlaceholder(_ imageUrl: String?) -> Bool {
        guard let imageUrl else { return false }
        return all.contains { $0.path == imageUrl }
    }
}
