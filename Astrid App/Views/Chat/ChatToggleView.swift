import SwiftUI

/// Single icon button that toggles between task list and chat views
struct ChatToggleButton: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var showChat: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChat.toggle()
            }
        } label: {
            Image(systemName: showChat ? "checklist" : "bubble.left.and.bubble.right")
                .font(Theme.Typography.headline())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}
