//  AttachmentPreviewSet.swift
//  Which files a tap on a comment's attachment prepares for Quick Look (task AITD-481).
//
//  A tap pages through every file on the task, so the bubble hands over a task-wide gallery
//  rather than its own files. That gallery is read from `CommentService`'s cache while the bubble
//  draws from the thread on screen, and the two can disagree — a task still on its temporary id,
//  a comment the cache has not been told about. The tapped photo was then in neither the prepared
//  set nor the result, nothing was presented, and the tap did nothing at all.
//
//  Pure so the rule can be tested without a view: the tapped bubble's files are always prepared.

import Foundation

enum AttachmentPreviewSet {

    /// The files to prepare, in the order Quick Look pages through them.
    ///
    /// - Parameters:
    ///   - bubble: the files of the comment that was tapped.
    ///   - gallery: every file the task is known to carry.
    ///   - realId: the uploaded id of a file still shown under its temporary one, when known.
    static func files(bubble: [SecureFile], gallery: [SecureFile],
                      realId: (String) -> String?) -> [SecureFile] {
        var known = Set(gallery.map(\.id))
        var files = gallery
        for file in bubble {
            // Already there under its own id, or under the id its upload was given — the same
            // picture must not page past twice.
            if known.contains(file.id) { continue }
            if let real = realId(file.id), known.contains(real) { continue }
            known.insert(file.id)
            files.append(file)
        }
        return files
    }

    /// Where the tapped file sits among the prepared ones.
    static func index(of tappedId: String, in preparedIds: [String],
                      realId: (String) -> String?) -> Int? {
        if let index = preparedIds.firstIndex(of: tappedId) { return index }
        guard let real = realId(tappedId) else { return nil }
        return preparedIds.firstIndex(of: real)
    }
}
