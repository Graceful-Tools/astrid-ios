import SwiftUI

/// Reusable empty state view showing Astrid character with speech bubble
struct EmptyStateView: View {
    @Environment(\.colorScheme) var colorScheme

    let message: String
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    /// Hi-fi art to show instead of the brand character (ADEV-127); nil keeps the character.
    let character: PlatformImage?

    /// Create an empty state view with Astrid character
    /// - Parameters:
    ///   - message: The message to display in the speech bubble
    ///   - buttonTitle: Optional button title (nil to hide button)
    ///   - buttonAction: Optional button action
    init(
        message: String,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil,
        character: PlatformImage? = nil
    ) {
        self.character = character
        self.message = message
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    var body: some View {
        VStack(spacing: Theme.spacing24) {
            Spacer()

            VStack(spacing: Theme.spacing24) {
                // Astrid with speech bubble (reusable component)
                AstridSpeechBubble(message: message, character: character)
                    .padding(.horizontal, Theme.spacing24)

                // Optional action button
                if let buttonTitle = buttonTitle, let buttonAction = buttonAction {
                    Button {
                        buttonAction()
                    } label: {
                        HStack(spacing: Theme.spacing8) {
                            Image(systemName: "plus.circle.fill")
                                .font(Theme.Typography.headline())
                            Text(buttonTitle)
                                .font(Theme.Typography.headline())
                        }
                        .padding(.horizontal, Theme.spacing24)
                        .padding(.vertical, Theme.spacing12)
                        .background(Theme.accent)
                        .foregroundColor(Theme.accentText)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                    }
                    .padding(.top, Theme.spacing8)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }
}

#Preview("With Button") {
    EmptyStateView(
        message: "Ready to capture your thoughts? Create your first task to get started!",
        buttonTitle: "Create Task",
        buttonAction: {}
    )
}

#Preview("Without Button") {
    EmptyStateView(
        message: "You're all caught up! No tasks assigned to you right now. Time to relax!"
    )
}

#Preview("Dark Mode") {
    EmptyStateView(
        message: "Create a list to organize your tasks and keep everything in order!",
        buttonTitle: "Create List",
        buttonAction: {}
    )
    .preferredColorScheme(.dark)
}
