//  MacAttachmentsSection.swift
//  Astrid for Mac — when attachments are worth a section (Task cb2702a9).
//
//  Attachments reach a task through comments, so the section was empty on nearly every task —
//  a header and an Add-file button and nothing else. It now appears only when the task actually
//  carries something, counting BOTH sources: URL-backed attachments and the secure files that
//  come in through comments.

#if os(macOS)
import Foundation

enum MacAttachmentsSection {
    static func isVisible(attachments: Int, secureFiles: Int) -> Bool {
        attachments + secureFiles > 0
    }

    /// Attaching stays reachable when there is nothing to show yet — the ⋮ menu carries it, the
    /// same way it carries Start Timer.
    static func offersAddInMenu(attachments: Int, secureFiles: Int) -> Bool {
        !isVisible(attachments: attachments, secureFiles: secureFiles)
    }
}
#endif
