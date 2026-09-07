//  MacCommentPaste.swift
//  Astrid for Mac — attaching what is on the clipboard to the comment being written (AITD-306).
//
//  The paperclip's NSOpenPanel was the only route a file had into a comment on the Mac. Nothing
//  read the pasteboard, so ⌘V with a screenshot on the board did nothing at all: the comment
//  field found no string to type, and no one else was looking.
//
//  This adds a SOURCE, not a second pipeline. Everything downstream of the picker already works
//  and is shared — AttachmentService.saveLocallyAndUploadAsync (offline-first, returns a temp id
//  immediately) → AttachmentQueue (the cap and the duplicate rule) → CommentAttachmentBatch (one
//  comment per file) → the Outbox. Paste feeds the same queue the paperclip fills.
//
//  The rules live here, pure, so "which of the four things on this pasteboard did the user mean"
//  is testable without a clipboard or a window.

#if os(macOS)
import Foundation
import UniformTypeIdentifiers

enum MacCommentPaste {

    /// One file the clipboard is offering, with its bytes already in hand.
    struct Candidate: Equatable {
        let name: String
        let mimeType: String
        let data: Data

        var isImage: Bool { mimeType.lowercased().hasPrefix("image/") }
    }

    /// What the caller found on the pasteboard. Reading it is AppKit's job; deciding what it
    /// MEANS is this file's, which is why the two are split.
    struct Snapshot {
        /// Files the board names on disk, in the order it lists them.
        var files: [Candidate] = []
        /// A raw image rendition with no file behind it — a screenshot, or a copied region.
        var imageData: Data?
        /// That rendition's extension ("png", "tiff", …).
        var imageExtension: String?

        init(files: [Candidate] = [], imageData: Data? = nil, imageExtension: String? = nil) {
            self.files = files
            self.imageData = imageData
            self.imageExtension = imageExtension
        }
    }

    /// Build a candidate from a name and its bytes, taking the mime from the extension.
    ///
    /// An unknown extension attaches as `application/octet-stream` rather than being dropped —
    /// the server stores the bytes either way, and refusing to paste a file because macOS has no
    /// UTI for it would be a worse answer than an unspecific type.
    static func file(named name: String, data: Data) -> Candidate {
        let ext = (name as NSString).pathExtension
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        return Candidate(name: name, mimeType: mime, data: data)
    }

    /// The name a nameless rendition gets. Two pastes a minute apart must not collide in the
    /// staged strip, so it carries the moment it was pasted — the same shape Finder and Messages
    /// give a pasted image.
    static func pastedImageName(at date: Date, ext: String) -> String {
        let stamp = DateFormatter.pastedImageStamp.string(from: date)
        return "Pasted Image \(stamp).\(ext.isEmpty ? "png" : ext)"
    }

    /// What this paste should stage.
    ///
    /// Files win over the rendition. Copying a PNG in Finder puts BOTH on the board; staging both
    /// would attach the same picture twice, and the file is the copy that keeps the real name and
    /// the original bytes rather than an AppKit re-encode.
    static func candidates(from snapshot: Snapshot, now: Date) -> [Candidate] {
        if !snapshot.files.isEmpty { return snapshot.files }
        guard let data = snapshot.imageData, !data.isEmpty else { return [] }
        let ext = snapshot.imageExtension ?? "png"
        return [file(named: pastedImageName(at: now, ext: ext), data: data)]
    }

    /// Whether ⌘V means "attach" rather than "type".
    ///
    /// A text-only clipboard is NEVER intercepted — that is the most common paste in the app, and
    /// breaking it to serve the rarest one would be a bad trade. With something attachable on the
    /// board it goes to the comment when the comment field has focus, or when nothing is being
    /// typed into at all; pasting into the title or the notes stays a text paste.
    static func handlesPaste(hasAttachableContent: Bool, commentFieldFocused: Bool,
                             otherEditorFocused: Bool) -> Bool {
        guard hasAttachableContent else { return false }
        return commentFieldFocused || !otherEditorFocused
    }

    /// Fold pasted candidates onto the files already staged, through the SHARED queue.
    ///
    /// `register` starts the upload and hands back the file id. The cap is asked BEFORE it is
    /// called: `AttachmentQueue.adding` drops a file at the cap, and registering first would send
    /// the bytes for something that can never post.
    static func staged(_ candidates: [Candidate], onto queue: [AttachedFileInfo],
                       register: (Candidate) -> String) -> [AttachedFileInfo] {
        var result = queue
        for candidate in candidates {
            guard !AttachmentQueue.isFull(result) else { break }
            result = AttachmentQueue.adding(
                AttachedFileInfo(fileId: register(candidate), fileName: candidate.name,
                                 fileSize: candidate.data.count, mimeType: candidate.mimeType,
                                 imageData: candidate.isImage ? candidate.data : nil),
                to: result)
        }
        return result
    }
}

private extension DateFormatter {
    /// Fixed locale/timezone-free formatting: this names a file, so it must not reorder itself
    /// per region or the staged strip sorts differently on different Macs.
    static let pastedImageStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
#endif
