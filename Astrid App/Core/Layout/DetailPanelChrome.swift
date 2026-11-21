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
    static let selectionOutlineWidth: CGFloat = AstridTokens.Size.Comfortable.selectionOutline
    /// `state.selection-outline-opacity` — the outline is the accent at 55%, not solid (DS5, ADEV-163).
    static let selectionOutlineOpacity: Double = AstridTokens.State.selectionOutlineOpacity
    /// What the selected row and the panel stroke.
    static var selectionOutlineColor: Color { Color.accentColor.opacity(selectionOutlineOpacity) }

    /// `motion.panel` — the panel opening out of the row, and closing back into it.
    static let panelDuration: Double = AstridTokens.Motion.panelDuration
    /// `motion.fast` — the arrow following the row as the list scrolls or the selection moves.
    static let arrowFollowDuration: Double = AstridTokens.Motion.fastDuration

    static var panelAnimation: Animation { .easeOut(duration: panelDuration) }
    static var arrowFollowAnimation: Animation { .easeOut(duration: arrowFollowDuration) }

    /// The arrow's notch, as the Mac draws it.
    static let arrowWidth: CGFloat = 12
    static let arrowHeight: CGFloat = 24
    /// How far the arrow overlaps the card, so its base merges into the card face.
    static let arrowOverlap: CGFloat = 1
    /// What the arrow is filled with: the details face itself, so its base merges into the card
    /// in every theme (AITD-627). Not the panel's base colour, which Ocean washes over.
    static func arrowFill(theme: ThemeMode) -> TaskDetailsSurface {
        TaskDetailsSurface(theme: theme)
    }

    /// Arrow centre in the panel's own coordinates, given the row's midY and the panel's origin in
    /// one shared (global) space. No measured row — it scrolled away — centres the arrow.
    ///
    /// The clamp off the corners is astrid-core's callout placement (`rows::callout`, AITD-678),
    /// the same call a board card's arrow makes: a list row reports only its middle, so it is
    /// asked as a zero-height anchor there. The app keeps no margin of its own.
    static func arrowLocalY(rowMidY: CGFloat?, panelOriginY: CGFloat, panelHeight: CGFloat) -> CGFloat {
        guard let rowMidY else { return panelHeight / 2 }
        return BoardCardCallout.arrowY(card: CGRect(x: 0, y: rowMidY, width: 0, height: 0),
                                       panel: CGRect(x: 0, y: panelOriginY, width: 0, height: panelHeight))
    }

    // MARK: - The iPad panel's full-screen flag — AITD-648

    /// Jon: "iPad full screen task details should reset after each task." Full screen belongs to
    /// the task that was expanded, not to the iPad: closing the panel ends it, so the next task
    /// opens as the side panel. Moving to another task without closing (a subtask or parent link,
    /// another board card) keeps what was asked for.
    static func fullScreen(_ current: Bool, afterSelectionChangeTo newTaskId: String?) -> Bool {
        newTaskId == nil ? false : current
    }

    /// No task is open at launch, so nothing is full screen either.
    static let fullScreenAtLaunch = false

    // MARK: - Full-screen details (iPhone, forced push) — AITD-609, AITD-664

    /// Does a row tap that pushes the details full screen zoom out of the row? No (AITD-664, Jon:
    /// "iPhone open task rows to task details should open same way as board Tasks. See old way of
    /// opened"). AITD-609 zoomed them; a board card on iPhone pushes with the ordinary slide
    /// (`BoardCardCallout.route`, AITD-642), and every one-pane view now opens its
    /// details that one way. DS7 is not a phone's single pane (astrid-core `design/README.md`).
    /// Kept as the named rule so the list's push and the board's cannot drift apart again.
    static func zoomsFromRow(usesSplitLayout: Bool, forcePushNavigation: Bool) -> Bool {
        false
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
    /// The selected board card's frame in the global space, as it moves (AITD-679). A list row
    /// reports only its middle; a card reports its whole extent, which the core's callout rule
    /// takes to aim the arrow.
    @Published private(set) var cardFrame: CGRect?
    /// The card a tap opened the panel from, and where it was at that moment. Which side the
    /// panel docks on is decided from this once, not from the live frame: a panel that changed
    /// sides as the board scrolled under it would be chasing the card (AITD-679).
    @Published private(set) var openedCard: OpenedCard?
    private var taskId: String?

    struct OpenedCard: Equatable {
        let taskId: String
        let frame: CGRect
    }

    func report(taskId: String, midY: CGFloat) {
        self.taskId = taskId
        source = nil
        if cardFrame != nil { cardFrame = nil }
        if self.midY != midY { self.midY = midY }
    }

    /// Which card view holds the position — a task's card is a NEW view in the column it moves
    /// to, and the one it left disappears after the new one has reported (ADEV-175).
    private var source: String?

    /// A board card's frame, while it is the panel's task. `source` names the card view reporting.
    func reportCard(taskId: String, frame: CGRect, source: String? = nil) {
        self.taskId = taskId
        self.source = source
        if cardFrame != frame { cardFrame = frame }
        if midY != frame.midY { midY = frame.midY }
    }

    /// A tap on a board card, just before it opens the panel.
    func openCard(taskId: String, frame: CGRect, source: String? = nil) {
        openedCard = OpenedCard(taskId: taskId, frame: frame)
        reportCard(taskId: taskId, frame: frame, source: source)
    }

    /// The open card moved to another column and the board has scrolled it into view: dock the
    /// panel beside it there, its side decided again from where it is now (ADEV-175). Scrolling
    /// alone never does this — the panel would chase the card (AITD-679).
    func reanchorOpenedCard(taskId: String) {
        guard openedCard?.taskId == taskId, self.taskId == taskId, let cardFrame else { return }
        openedCard = OpenedCard(taskId: taskId, frame: cardFrame)
    }

    /// The panel closed: the next task it opens may come from somewhere other than a card.
    func forgetOpenedCard() {
        if openedCard != nil { openedCard = nil }
    }

    /// Forget the row — only if it is still the one held, so a row disappearing after the next one
    /// was selected does not erase the new row's position.
    /// A card view passes its `source`: the card a task moved OUT of a column must not erase the
    /// card it moved into, which reported first (ADEV-175).
    func clear(taskId: String, source: String? = nil) {
        guard self.taskId == taskId else { return }
        if let source, let held = self.source, held != source { return }
        self.taskId = nil
        self.source = nil
        midY = nil
        cardFrame = nil
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
