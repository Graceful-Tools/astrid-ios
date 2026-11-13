//  DetailPanelChrome.swift
//  How the task details panel attaches to the selected row (AITD-607, register DS7 in astrid-core
//  `design/README.md`; spec: astrid-web `docs/specs/DESIGN_SYSTEM.md` → Task details panel).
//
//  On the Mac and web the panel wears the same selection outline as the selected row, an arrow on
//  its leading edge points at that row and follows it, and it opens over `motion.panel`. The
//  numbers live here so the iPad panel, the row and the Mac's pop-out read the same values, and a
//  test can reach them. Built into iOS and the Mac.

import Combine
import SwiftUI

enum DetailPanelChrome {
    /// `size.comfortable.selection-outline`. The selected iPad row strokes the same width.
    static let selectionOutlineWidth: CGFloat = 2.5

    /// `motion.panel` — the panel opening out of the row, and closing back into it.
    static let panelDuration: Double = 0.30
    /// `motion.fast` — the arrow following the row as the list scrolls or the selection moves.
    static let arrowFollowDuration: Double = 0.15

    static var panelAnimation: Animation { .easeOut(duration: panelDuration) }
    static var arrowFollowAnimation: Animation { .easeOut(duration: arrowFollowDuration) }

    /// The arrow's notch, as the Mac draws it.
    static let arrowWidth: CGFloat = 12
    static let arrowHeight: CGFloat = 24
    /// How far the arrow overlaps the card, so its base merges into the card face.
    static let arrowOverlap: CGFloat = 1
    /// How far from the panel's top and bottom the arrow stays, so it always touches the card.
    static let arrowInset: CGFloat = 28

    /// Arrow centre, clamped inside a panel of `panelHeight`, for a row at `rowMidY` in the panel's
    /// own coordinates.
    static func arrowY(rowMidY: CGFloat, panelHeight: CGFloat, inset: CGFloat = arrowInset) -> CGFloat {
        guard panelHeight > inset * 2 else { return panelHeight / 2 }
        return min(max(rowMidY, inset), panelHeight - inset)
    }

    /// What the arrow is filled with: the details face itself, so its base merges into the card
    /// in every theme (AITD-627). Not the panel's base colour, which Ocean washes over.
    static func arrowFill(theme: ThemeMode) -> TaskDetailsSurface {
        TaskDetailsSurface(theme: theme)
    }

    /// Arrow centre in the panel's own coordinates, given the row's midY and the panel's origin in
    /// one shared (global) space. No measured row — it scrolled away — centres the arrow.
    static func arrowLocalY(rowMidY: CGFloat?, panelOriginY: CGFloat, panelHeight: CGFloat,
                            inset: CGFloat = arrowInset) -> CGFloat {
        guard let rowMidY else { return panelHeight / 2 }
        return arrowY(rowMidY: rowMidY - panelOriginY, panelHeight: panelHeight, inset: inset)
    }

    /// Whether the iPad panel opens out of the selected row with an arrow aimed at it (AITD-647).
    /// Only a list has that row: the row reports its position, a board card does not, so on a
    /// board the arrow pointed at nothing. A board opens the plain side panel from the trailing
    /// edge, as before AITD-607.
    static func pointsAtRow(viewMode: HeaderToggleSegment) -> Bool {
        viewMode != .board
    }

    // MARK: - The iPad panel's full-screen flag — AITD-648

    /// Jon: "iPad full screen task details should reset after each task." Full screen belongs to
    /// the task that was expanded, not to the iPad: closing the panel ends it, so the next task
    /// opens as the side panel. Moving to another task without closing (a subtask or parent link,
    /// a board card's full-screen button) keeps what was asked for.
    static func fullScreen(_ current: Bool, afterSelectionChangeTo newTaskId: String?) -> Bool {
        newTaskId == nil ? false : current
    }

    /// No task is open at launch, so nothing is full screen either.
    static let fullScreenAtLaunch = false

    // MARK: - Full-screen details (iPhone, forced push) — AITD-609

    /// A row tap that pushes the details full screen has no row beside them to outline or point
    /// at, so DS7 is carried by the motion: the details zoom out of the tapped row. The split
    /// layout's side panel keeps its own treatment above.
    static func zoomsFromRow(usesSplitLayout: Bool, forcePushNavigation: Bool) -> Bool {
        !usesSplitLayout || forcePushNavigation
    }

    /// How long the row the details closed back into wears the selection outline — one
    /// `motion.panel`, the beat the iPad panel opens over.
    static let returnFlashDuration: Double = panelDuration

    /// Whether a list row wears the selection outline: it is the iPad panel's task, or the
    /// full-screen details just closed back into it.
    static func rowIsOutlined(taskId: String, panelSelectionId: String?, returningTaskId: String?) -> Bool {
        taskId == panelSelectionId || taskId == returningTaskId
    }
}

/// Where the selected row sits on screen, so the details panel can aim its arrow at it.
///
/// A reference handed down the environment rather than a preference: the list lives inside its own
/// NavigationStack, which does not pass preferences out to the panel beside it.
@MainActor
final class SelectedRowReporter: ObservableObject {
    @Published private(set) var midY: CGFloat?
    private var taskId: String?

    func report(taskId: String, midY: CGFloat) {
        self.taskId = taskId
        if self.midY != midY { self.midY = midY }
    }

    /// Forget the row — only if it is still the one held, so a row disappearing after the next one
    /// was selected does not erase the new row's position.
    func clear(taskId: String) {
        guard self.taskId == taskId else { return }
        self.taskId = nil
        midY = nil
    }
}

private struct SelectedRowReporterKey: EnvironmentKey {
    static let defaultValue: SelectedRowReporter? = nil
}

extension EnvironmentValues {
    /// Set by the split layout; nil everywhere else, where no panel sits beside the list.
    var selectedRowReporter: SelectedRowReporter? {
        get { self[SelectedRowReporterKey.self] }
        set { self[SelectedRowReporterKey.self] = newValue }
    }
}

/// The arrow's filled notch, pointing left at the row.
struct DetailPanelArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The notch's two outer edges as an open path, which carries the outline around it without
/// drawing a line across its base.
struct DetailPanelArrowEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}
