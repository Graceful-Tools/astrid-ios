//  DescriptionReader.swift
//  The full-screen description: when it is offered, how it opens, what closing it saves.
//  (Task AITD-577; opening it to write, AITD-649)
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

    /// How the reader was reached. `expand` is the button beside the label; `write` is tapping
    /// the description itself to add or change it (AITD-649), which opens the reader rather
    /// than a few-line box in the detail sheet.
    enum Entry: String, Identifiable, Equatable {
        case expand
        case write

        var id: String { rawValue }
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
    /// Tapping the description to write it opens the editor whatever it holds — that tap is
    /// asking to write. A task you can only read never opens one.
    static func initialMode(text: String, isReadOnly: Bool, entry: Entry = .expand) -> Mode {
        guard !isReadOnly else { return .reading }
        return (entry == .write || isBlank(text)) ? .editing : .reading
    }

    /// The text closing the reader writes, or nil when nothing changed. Clearing it is a change.
    static func textToSave(edited: String, original: String) -> String? {
        edited == original ? nil : edited
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
