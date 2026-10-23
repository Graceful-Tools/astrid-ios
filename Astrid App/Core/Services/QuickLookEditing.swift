//  QuickLookEditing.swift
//  Which attachments Quick Look may mark up, and what type the edited copy goes back as. (AITD-538)
//
//  These lived inside QuickLookController and its tests carried their own copies, so the tests
//  could not notice the two lists disagreeing — and they did: TIFF and BMP were editable, but an
//  edited one was uploaded as `application/octet-stream`.

import Foundation

enum QuickLookEditing {

    /// The file types Markup can edit: images and PDFs.
    static let editableExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp", "pdf"
    ]

    /// Only a file the server already has can be edited. A `temp_` id is still in the Outbox and an
    /// `unknown-` id was never resolved, so there is nothing to save an edited copy over.
    static func canEdit(fileId: String) -> Bool {
        !fileId.hasPrefix("unknown-") && !fileId.hasPrefix("temp_")
    }

    static func isEditable(fileId: String, fileExtension: String) -> Bool {
        canEdit(fileId: fileId) && editableExtensions.contains(fileExtension.lowercased())
    }

    /// The MIME type an edited copy is uploaded with. Every editable extension has its own.
    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
