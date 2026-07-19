//  MacListImage.swift
//  Astrid for Mac — pure helpers for list-image upload (Task 383b96af).

#if os(macOS)
import UniformTypeIdentifiers

enum MacListImage {
    static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp"]
    static let contentTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .image]

    /// Whether a chosen file looks like a supported image (by extension).
    static func isSupported(filename: String) -> Bool {
        allowedExtensions.contains((filename as NSString).pathExtension.lowercased())
    }
}
#endif
