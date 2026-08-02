import Foundation

/// How the repeat picker shows its editor (Task 42013da7).
///
/// When the trigger became a compact chip, the PRESET list was moved into a sheet — but the
/// CUSTOM pattern editor was left rendering inline, and the sheet's condition explicitly excluded
/// it. So the custom editor laid itself out inside a chip-width column, wrapping "Repeat from
/// completion date" mid-word.
///
/// Both editors are full-screen work. Deciding it here, once, is what stops the two paths
/// drifting apart again.
enum RepeatEditorPresentation: Equatable {
    /// Shown in place, replacing the trigger — the original behaviour, kept for full-width callers.
    case inline
    /// Presented over the whole screen, for a chip-sized trigger with no room of its own.
    case sheet
    /// Not editing: show the trigger.
    case trigger

    static func of(compact: Bool, isEditing: Bool, showingCustom: Bool) -> RepeatEditorPresentation {
        guard isEditing || showingCustom else { return .trigger }
        return compact ? .sheet : .inline
    }

    /// The custom editor outranks the preset list: opening custom FROM the presets leaves both
    /// flags set for a moment, and the preset list must not draw over the custom editor.
    static func showsCustomEditor(isEditing: Bool, showingCustom: Bool) -> Bool {
        showingCustom
    }
}
