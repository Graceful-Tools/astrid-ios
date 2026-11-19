import SwiftUI

/// The completed date under a Done card's title (`CompletedOnLabel`), drawn like the board-status
/// pill a list row shows, in Done's tint. The font comes from the card (`.font` on iOS, `.macFont`
/// on Mac), so it matches the metadata beside it.
struct CompletedOnPill: View {
    let text: String

    var body: some View {
        let tint = TaskBoardStatusPill.tint(for: .done)
        Text(verbatim: text)
            .foregroundColor(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(CompletedOnLabel.accessibilityLabel(text))
            .accessibilityIdentifier("board.card.completedOn")
    }
}
