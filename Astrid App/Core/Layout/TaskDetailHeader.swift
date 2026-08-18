import Foundation

/// How anything outside the view knows the task detail is open (task b86c97c5).
///
/// The UI suite waited on `app.staticTexts["Task Details"]`, which could never match: the
/// header is a BUTTON — tapping it scrolls the panel back to the top — so its label belongs to
/// the button, not to a static text. Nine tests reported "task detail did not appear" when it
/// had appeared, which sent three investigations after the tap instead of after the marker.
///
/// An identifier rather than a label, for two reasons: it names WHICH element rather than
/// hoping for an element type, and it does not change when the app is running in French.
enum TaskDetailHeader {
    static let accessibilityIdentifier = "taskDetail.header"
}
