//  DescriptionReader.swift
//  The full-screen description: when it is offered, how it opens, what closing it saves.
//  (Task AITD-577)
//
//  A description has grown into the place an agent writes its plan and a person writes a
//  spec, and the detail sheet gives it a box a few lines tall. The reader is the whole screen
//  for it. These are the decisions behind it, pure so they can be pinned without a view.

import Foundation

enum DescriptionReader {
    enum Mode: Equatable {
        case reading
        case editing
    }

    /// Is the expand button shown beside the Description label?
    ///
    /// Always when you can edit — writing a long description is what the room is for — and,
    /// on a task you can only read, only when there is something to read.
    static func offersFullScreen(text: String, isReadOnly: Bool) -> Bool {
        !isReadOnly || !isBlank(text)
    }

    /// Opening onto an empty page you cannot type on would be a dead end, and opening a
    /// written description straight into an editor puts a keyboard over what you came to read.
    static func initialMode(text: String, isReadOnly: Bool) -> Mode {
        (!isReadOnly && isBlank(text)) ? .editing : .reading
    }

    /// The text closing the reader writes, or nil when nothing changed. Clearing it is a change.
    static func textToSave(edited: String, original: String) -> String? {
        edited == original ? nil : edited
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
