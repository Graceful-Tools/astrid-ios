import SwiftUI

/// Custom hamburger menu icon with 2 horizontal lines at 80% width
struct HamburgerMenuIcon: View {
    @ThemedPalette private var palette

    var body: some View {
        VStack(spacing: 5) {
            // Top line
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.textPrimary)
                .frame(width: 19.2, height: 2) // 80% of 24pt (standard icon size)

            // Bottom line
            RoundedRectangle(cornerRadius: 1.5)
                .fill(palette.textPrimary)
                .frame(width: 19.2, height: 2)
        }
        .frame(width: 24, height: 24) // Match standard SF Symbol size
    }
}

#Preview("Light Mode") {
    HamburgerMenuIcon()
        .padding()
        .background(Color.white)
}

#Preview("Dark Mode") {
    HamburgerMenuIcon()
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("In Navigation Bar") {
    NavigationStack {
        Text("Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {}) {
                        HamburgerMenuIcon()
                    }
                }
            }
    }
}
