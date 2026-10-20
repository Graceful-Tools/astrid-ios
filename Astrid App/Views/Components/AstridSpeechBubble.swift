import SwiftUI

/// Reusable Astrid character with speech bubble
/// Used in EmptyStateView and ReminderView
struct AstridSpeechBubble: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Astrid character (2x size for better visibility in reminders)
            if let character = Brand.characterImage {
                Image(character)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
            }

            // Speech bubble (flexible width)
            ZStack(alignment: .leading) {
                // Bubble content
                Text(message)
                    .font(Theme.Typography.body())
                    .fontWeight(.semibold)
                    .foregroundColor(getTextColor())
                    .padding(Theme.spacing16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(getBubbleBackground())
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(getBubbleBorder(), lineWidth: 2)
                    )

                // Speech bubble pointer (comic-style arrow pointing left to Astrid)
                // Matches web design: layered triangles for border effect
                GeometryReader { geometry in
                    let centerY = geometry.size.height / 2

                    ZStack {
                        // Outer triangle (border) - 16px wide total, extends 3px into bubble
                        Path { path in
                            path.move(to: CGPoint(x: -16, y: centerY))           // Left point (centered)
                            path.addLine(to: CGPoint(x: 3, y: centerY - 12))    // Top right (16px wide + 3px overlap)
                            path.addLine(to: CGPoint(x: 3, y: centerY + 12))    // Bottom right
                            path.closeSubpath()
                        }
                        .fill(getPointerBorderColor())

                        // Inner triangle (fill) - 13px wide total, extends 3px into bubble
                        Path { path in
                            path.move(to: CGPoint(x: -13, y: centerY))           // Left point (3px inset)
                            path.addLine(to: CGPoint(x: 3, y: centerY - 9.5))   // Top right (13px wide + 3px overlap)
                            path.addLine(to: CGPoint(x: 3, y: centerY + 9.5))   // Bottom right
                            path.closeSubpath()
                        }
                        .fill(getBubbleBackground())
                    }
                    .offset(x: 0, y: 0)  // Positioned at bubble edge
                }
            }
        }
    }

    // MARK: - Theme Helpers

    /// Get text color for speech bubble - black on Ocean theme
    private func getTextColor() -> Color {
        if themeMode == "ocean" {
            return Theme.Ocean.textPrimary  // Black text on Ocean theme
        }
        return colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
    }

    /// Get bubble background color - white on all themes
    private func getBubbleBackground() -> Color {
        if themeMode == "ocean" {
            return Theme.Ocean.bgSecondary  // White bubble on cyan background
        }
        return colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary
    }

    /// Get bubble border color - cyan on Ocean theme
    private func getBubbleBorder() -> Color {
        if themeMode == "ocean" {
            return Theme.Ocean.border  // Cyan border on Ocean theme
        }
        return colorScheme == .dark ? Theme.Dark.border : Theme.border
    }

    /// Get pointer border color - cyan on Ocean theme
    private func getPointerBorderColor() -> Color {
        if themeMode == "ocean" {
            return Theme.Ocean.border  // Cyan border on Ocean theme
        }
        return colorScheme == .dark ? (Color(hex: "#4b5563") ?? Color.gray) : (Color(hex: "#d1d5db") ?? Color.gray)
    }
}

#Preview {
    VStack(spacing: 32) {
        AstridSpeechBubble(message: "Hi there! Have a sec? Ready to put this in the past?")
            .padding()

        AstridSpeechBubble(message: "Create a list to organize your tasks and keep everything in order!")
            .padding()
    }
    .background(Theme.bgPrimary)
}

#Preview("Dark Mode") {
    VStack(spacing: 32) {
        AstridSpeechBubble(message: "Time to work! I promise you'll feel better if you finish this!")
            .padding()
    }
    .background(Theme.Dark.bgPrimary)
    .preferredColorScheme(.dark)
}
