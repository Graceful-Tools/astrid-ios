//  AttachmentQueue.swift
//  The files staged on a comment before it is sent. (Task a72e09ca)
//
//  Every comment input needs the same answer to "what happens when you pick a second file",
//  and the first pass got it right in two inputs and wrong in the third — the one the task
//  detail actually renders — so picking a second attachment silently discarded the first.
//  The decision lives here now, in one place all of them call.

import Foundation

enum AttachmentQueue {

    /// Ceiling on staged files. Matches the photo picker's own limit so the two agree.
    static var maxAttachments: Int { CommentAttachmentBatch.maxSelection }

    static func isFull(_ queue: [AttachedFileInfo]) -> Bool {
        queue.count >= maxAttachments
    }

    /// Queue a file behind the ones already staged.
    ///
    /// At the cap this drops the NEW file rather than evicting an old one: the user can see
    /// what is already staged and can remove one deliberately, whereas silently discarding
    /// an earlier pick is exactly the failure this type exists to prevent.
    static func adding(_ file: AttachedFileInfo, to queue: [AttachedFileInfo]) -> [AttachedFileInfo] {
        guard !isFull(queue) else { return queue }
        // A re-fired onChange or a double tap must not post the same file twice.
        guard !queue.contains(where: { $0.fileId == file.fileId }) else { return queue }
        return queue + [file]
    }

    static func removing(fileId: String, from queue: [AttachedFileInfo]) -> [AttachedFileInfo] {
        queue.filter { $0.fileId != fileId }
    }
}
