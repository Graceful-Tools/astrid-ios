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

    // MARK: - Title (AITD-647)

    /// The header's words around the task id. A board task used to show its id in a row of its
    /// own; now the header reads "<id> Details" and the id is the part that copies. The words
    /// either side come from one localized sentence, so each language keeps its own word order.
    struct Title: Equatable {
        let prefix: String
        /// Nil when there is no id to show — the title is then just "Task Details".
        let identifier: String?
        let suffix: String
    }

    /// `identifier` should already have passed `TaskIdentifiers.shows(_:lists:on: .details)`.
    static func title(identifier: String?) -> Title {
        guard let identifier, !identifier.isEmpty else {
            return Title(prefix: NSLocalizedString("tasks.task_details", comment: ""), identifier: nil, suffix: "")
        }
        return splitTitle(format: NSLocalizedString("tasks.task_details_for_id", comment: ""), identifier: identifier)
    }

    /// Splits a `%@` sentence around the id. A translation that lost its placeholder still shows
    /// the id, ahead of the words.
    static func splitTitle(format: String, identifier: String) -> Title {
        guard let range = format.range(of: "%@") else {
            return Title(prefix: "", identifier: identifier, suffix: " " + format)
        }
        return Title(prefix: String(format[..<range.lowerBound]), identifier: identifier,
                     suffix: String(format[range.upperBound...]))
    }
}
