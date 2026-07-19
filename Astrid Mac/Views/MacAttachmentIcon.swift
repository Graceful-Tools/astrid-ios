//  MacAttachmentIcon.swift
//  Astrid for Mac — pure mapping from an attachment's mime/type/name to an SF Symbol + human size
//  (Task 6a25494a). Pure so it's unit-testable without a view.

#if os(macOS)
import Foundation

enum MacAttachmentIcon {
    /// SF Symbol for an attachment, chosen from its mime type (preferred) or filename extension.
    static func symbol(type: String?, name: String) -> String {
        let t = (type ?? "").lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        if t.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(ext) {
            return "photo"
        }
        if t.hasPrefix("video/") || ["mov", "mp4", "m4v", "avi"].contains(ext) { return "film" }
        if t.hasPrefix("audio/") || ["mp3", "m4a", "wav", "aac"].contains(ext) { return "waveform" }
        if t == "application/pdf" || ext == "pdf" { return "doc.richtext" }
        if ["zip", "gz", "tar", "rar", "7z"].contains(ext) { return "doc.zipper" }
        if ["txt", "md", "rtf"].contains(ext) { return "doc.text" }
        return "paperclip"
    }

    /// Human-readable byte size ("2.4 MB"). 0/negative → empty (unknown size).
    static func humanSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
        return unit == 0 ? "\(Int(value)) B" : String(format: "%.1f %@", value, units[unit])
    }
}
#endif
