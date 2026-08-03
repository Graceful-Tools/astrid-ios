//  CommentAttachmentBatch.swift
//  Turning a set of picked files into the comments that will carry them. (Task a72e09ca)
//
//  `POST /api/v1/tasks/[id]/comments` accepts a single `fileId`. Letting one comment hold many
//  files would be a breaking cross-platform API change, so multi-select instead fans out to one
//  comment per file — the same thing iMessage does with a multi-photo send.
//
//  This is where attachments would go missing if the arithmetic were wrong, and losing one is
//  invisible to the user (they watched the thumbnail appear), so it lives here as a pure
//  function with tests rather than inline in the view.

import Foundation

/// One comment that is about to be enqueued: what it says and which file it carries.
struct CommentDraft: Equatable {
    let content: String
    let fileId: String?
    let type: Comment.CommentType
}

enum CommentAttachmentBatch {

    /// How many photos the picker will let you take at once. A ceiling exists because each pick
    /// becomes its own Outbox operation and its own comment; twenty at a time is a wall of
    /// thumbnails, not a message.
    static var maxSelection: Int { 10 }

    /// Split typed text and picked files into the comments to send, in pick order.
    ///
    /// The caption rides the first comment and is not repeated — four photos with the caption
    /// echoed four times reads as a stutter in the thread.
    static func drafts(text: String, fileIds: [String], useMarkdown: Bool) -> [CommentDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !fileIds.isEmpty else {
            // No file: nothing to say means nothing to send.
            guard !trimmed.isEmpty else { return [] }
            return [CommentDraft(content: trimmed,
                                 fileId: nil,
                                 type: useMarkdown ? .MARKDOWN : .TEXT)]
        }

        return fileIds.enumerated().map { index, fileId in
            CommentDraft(content: index == 0 ? trimmed : "",
                         fileId: fileId,
                         type: .ATTACHMENT)
        }
    }
}
