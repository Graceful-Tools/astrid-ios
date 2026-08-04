//  EditingSession.swift
//  One editor active at a time, with one save rule. (Task 55010e29)
//
//  Astrid has a dozen-plus editors, each carrying its own `isEditing` flag and its own idea of
//  when an edit is saved: some commit on Done, some on resign, some offer Cancel, some
//  auto-save on disappear. Two could be open at once — edit a list, tap the title. Closing the
//  keyboard before opening the priority picker (build 175) was this same rule applied by hand
//  at one call site; the rule already existed, it was just never written down. When one
//  decision lives in two places they drift, which is what the `!showingCustomEditor`
//  regression was.
//
//  THE POLICY, in one line: **resigning saves**. Opening another editor, tapping outside,
//  navigating away and backgrounding all commit. Only an explicit `cancel` reverts.
//
//  This type is the whole policy and it holds no view state, so every transition — including
//  the ordering hazards that a per-editor boolean cannot express — is testable without a view.

import Foundation
import Combine

/// Identifies an editor. A plain String so any view can name itself without a shared enum
/// having to know about every editor in the app.
typealias EditorID = String

@MainActor
final class EditingSession: ObservableObject {

    /// The one editor currently accepting input, if any.
    @Published private(set) var activeEditor: EditorID?

    private let onCommit: (EditorID) -> Void
    private let onCancel: (EditorID) -> Void

    init(onCommit: @escaping (EditorID) -> Void = { _ in },
         onCancel: @escaping (EditorID) -> Void = { _ in }) {
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func isActive(_ id: EditorID) -> Bool { activeEditor == id }

    /// Activate an editor, committing whatever it displaces.
    ///
    /// Re-entrant by design: a view re-render calling `begin` on the already-active editor is a
    /// no-op rather than a displacement, because treating it as one would fire a commit on
    /// every redraw.
    func begin(_ id: EditorID) {
        guard activeEditor != id else { return }
        if let current = activeEditor {
            onCommit(current)          // resigning saves — never discard what was typed
        }
        activeEditor = id
    }

    /// Finish an editor, saving it.
    ///
    /// Ignored unless `id` is the active editor. SwiftUI tears views down asynchronously, so a
    /// dismissed editor's `end` can arrive AFTER another has become active; acting on it would
    /// deactivate a live editor that is still on screen and commit the old one twice.
    func end(_ id: EditorID) {
        guard activeEditor == id else { return }
        activeEditor = nil
        onCommit(id)
    }

    /// Discard an editor's changes. The only path that does not save.
    ///
    /// Same staleness guard as `end`, for the same reason.
    func cancel(_ id: EditorID) {
        guard activeEditor == id else { return }
        activeEditor = nil
        onCancel(id)
    }

    /// Commit whatever is open — navigating away, backgrounding, tapping the background.
    /// Safe when nothing is open, so a view can call it unconditionally on disappear.
    func commitAll() {
        guard let current = activeEditor else { return }
        activeEditor = nil
        onCommit(current)
    }
}
