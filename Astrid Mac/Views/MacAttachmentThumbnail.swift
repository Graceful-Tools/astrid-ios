//  MacAttachmentThumbnail.swift
//  Astrid for Mac — where a comment attachment's picture comes from, and whether it has to wait
//  for it (AITD-308).
//
//  The bubble drew its files (AITD-304) but every draw started from nothing: it went straight to
//  an `await` and showed a grey placeholder in the meantime, even for a file whose bytes were
//  already on this machine. Awaiting is only honest for the one case that genuinely has to fetch;
//  for the other two the answer is sitting in memory or on disk and can be read synchronously.
//
//  Pure so "does this render show a placeholder" is testable without a view or a network.

#if os(macOS)
import Foundation

enum MacAttachmentThumbnail {

    /// Where the picture is coming from on THIS render.
    enum Source: Equatable {
        /// Already decoded in memory — draw it now.
        case cachedImage
        /// Downloaded before; the bytes are on disk and read synchronously.
        case cachedBytes
        /// Not here yet: the local copy of a staged file, or a download from the server.
        case mustFetch
        /// A document, a video, an audio file — a chip, never an image load. `NSImage` would
        /// happily return nil for a .mov and trade the chip for a grey box.
        case notAnImage

        /// Only a real fetch earns a placeholder. Showing one for bytes already in hand is the
        /// flicker this task is about.
        var showsPlaceholder: Bool { self == .mustFetch }
    }

    static func source(mimeType: String, hasCachedImage: Bool, hasCachedBytes: Bool) -> Source {
        guard MacCommentBubble.rendersInline(mimeType: mimeType) else { return .notAnImage }
        if hasCachedImage { return .cachedImage }
        if hasCachedBytes { return .cachedBytes }
        return .mustFetch
    }
}
#endif
