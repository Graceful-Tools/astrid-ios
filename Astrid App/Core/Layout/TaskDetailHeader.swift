import CoreGraphics
import Foundation

/// What the back control at the leading edge of task details does (AITD-425).
///
/// Named rather than inferred from reading the call sites, the same way
/// `UserProfileView.backAction(isRootDestination:)` is: the two presentations need two
/// different gestures, and the one that needs `onClose` is also the one where `dismiss()`
/// silently does nothing.
enum TaskDetailBackAction: Equatable {
    /// The iPad side panel. It is the ROOT of its own NavigationStack, so there is nothing to
    /// pop — closing it means clearing the container's `selectedTask`, which is what the
    /// `onClose` the panel supplies does.
    case closePanel
    /// Pushed onto a navigation stack: the iPhone detail, and task references opened from
    /// inside an open detail. Back pops.
    case dismissStack
}

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

    /// The back chevron, for the same reason the title has one.
    static let backAccessibilityIdentifier = "taskDetail.back"

    /// Apple's HIG minimum tap target. The back chevron used to have none of its own: a 17pt
    /// `chevron.left` under `.buttonStyle(.plain)` is hittable only across the glyph, about
    /// 11×17pt. Its neighbour the "..." menu had the identical defect fixed in 23da286 and
    /// this constant is what keeps the two from drifting apart again.
    ///
    /// It surfaced as an iPad bug because of what a MISSED tap costs on each platform. On
    /// iPhone the detail is pushed and `.enableInteractivePopGesture()` restores swipe-back, so
    /// a miss is rescued by a gesture people already use. On iPad it is a side panel whose only
    /// other exit is a 20pt rightward drag, so a miss is just nothing happening.
    static let minimumTapTarget: CGFloat = 44

    /// Which of the two things back does. `hasPanelClose` is "the container handed us an
    /// `onClose`", which only the iPad panel does.
    static func backAction(hasPanelClose: Bool) -> TaskDetailBackAction {
        hasPanelClose ? .closePanel : .dismissStack
    }
}
