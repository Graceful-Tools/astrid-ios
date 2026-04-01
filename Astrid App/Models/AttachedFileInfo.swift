import Foundation

/// Info about a file attached to a comment or chat message (used for preview before sending)
struct AttachedFileInfo {
    let fileId: String
    let fileName: String
    let fileSize: Int
    let mimeType: String
    let imageData: Data?  // For thumbnail preview (images only)

    var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }
}
