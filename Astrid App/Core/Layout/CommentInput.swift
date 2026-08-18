import Foundation

/// How anything outside the view finds the comment box (task 91a7e180).
///
/// The UI suite asked for `app.textFields` with a `placeholderValue` containing "comment".
/// That could never match, for two independent reasons: the control is a `TextEditor`, which
/// XCUITest exposes as a text VIEW rather than a text field, and its placeholder is a separate
/// `Text` drawn behind it, so `placeholderValue` is empty. Four tests reported "Comment input
/// field not found" — a sentence about the app that was really about the query.
///
/// This is the same wrong shape that once hid the quick-add field, which is why the fix is the
/// same: name the element, and let the test ask for it by name.
///
/// Stamped on `RichTextInput`, which is what the task detail actually mounts through
/// `.safeAreaInset(edge: .bottom)`. Two older TextEditors — one in `TaskDetailViewNew`, one in
/// `CommentSectionViewEnhanced` — read like the comment input and are not the one on screen.
/// That cost an hour: marking each placeholder and reading back which one the accessibility
/// tree showed is what settled it.
enum CommentInput {
    static let accessibilityIdentifier = "comment.field"
}
