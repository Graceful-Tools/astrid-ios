import SwiftUI

/// Single icon button that toggles between task list and chat views
struct ChatToggleButton: View {
    @ThemedPalette private var palette
    @Binding var showChat: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: AstridTokens.Motion.mediumDuration)) {
                showChat.toggle()
            }
        } label: {
            Image(systemName: showChat ? "checklist" : "bubble.left.and.bubble.right")
                .font(Theme.Typography.headline())
                .foregroundColor(palette.textPrimary)
        }
        .buttonStyle(.plain)
    }
}
