import SwiftUI

/// The completed date under a Done card's title, after a check ("✓ on Nov 19", `CompletedOnLabel`), drawn as the shared `AstridPill`
/// (ADEV-166) like the board-status pill a list row shows, in Done's tint. The font comes from the card (`.font` on iOS, `.macFont`
/// on Mac), so it matches the metadata beside it.
struct CompletedOnPill: View {
    let text: String

    var body: some View {
        AstridPill(text: CompletedOnLabel.pillText(text), tint: TaskBoardStatusPill.tint(for: .done))
            .accessibilityLabel(CompletedOnLabel.accessibilityLabel(text))
            .accessibilityIdentifier("board.card.completedOn")
    }
}
