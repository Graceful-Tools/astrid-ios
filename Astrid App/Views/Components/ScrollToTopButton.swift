import SwiftUI

/// A floating scroll-to-top button that appears when scrolling down
struct ScrollToTopButton: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let action: () -> Void

    var body: some View {
        Button(action: {
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

            action()
        }) {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(buttonBackgroundColor)
                        .shadow(
                            color: Color.black.opacity(0.15),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var buttonBackgroundColor: Color {
        // Use theme accent color for consistency
        if themeMode == "ocean" {
            return Theme.Ocean.accent
        } else if colorScheme == .dark {
            return Theme.Dark.accent
        } else {
            return Theme.accent
        }
    }
}

#Preview {
    ScrollToTopButton {
        AppLog.debug("Scroll to top tapped")
    }
}
