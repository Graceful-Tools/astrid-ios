import SwiftUI

/// Reusable component for displaying list images with fallback to default icons
/// Replaces the old color dot pattern throughout the app
struct ListImageView: View {
    @Environment(\.colorScheme) var colorScheme

    let list: TaskList
    let size: CGFloat

    @State private var imageLoadFailed = false

    init(list: TaskList, size: CGFloat = 12) {
        self.list = list
        self.size = size
    }

    var body: some View {
        // Use fixed-size container to ensure size is enforced in all contexts (including Pickers)
        Color.clear
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if let imageURL = ListImageHelper.getFullImageUrl(list: list) {
                        CachedAsyncImage(url: imageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color(hex: list.displayColor) ?? Theme.accent)
                        }
                        .id(imageURL) // Force reload when URL changes
                    } else {
                        Circle()
                            .fill(Color(hex: list.displayColor) ?? Theme.accent)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

/// Larger variant for settings and detail views
struct ListImageViewLarge: View {
    let list: TaskList
    let size: CGFloat
    let cornerRadius: CGFloat

    init(list: TaskList, size: CGFloat = 64, cornerRadius: CGFloat = 12) {
        self.list = list
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        // Use fixed-size container to ensure size is enforced in all contexts
        Color.clear
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if let imageURL = ListImageHelper.getFullImageUrl(list: list) {
                        CachedAsyncImage(url: imageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Color(hex: list.displayColor) ?? Theme.accent)
                        }
                        .id(imageURL) // Force reload when URL changes
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(hex: list.displayColor) ?? Theme.accent)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#Preview {
    VStack(spacing: 20) {
        // Small size (for sidebar)
        HStack(spacing: 12) {
            ListImageView(
                list: TaskList(
                    id: "test-1",
                    name: "Test List",
                    color: "#3b82f6"
                ),
                size: 12
            )
            Text("Small (12pt)")
        }

        // Medium size
        HStack(spacing: 12) {
            ListImageView(
                list: TaskList(
                    id: "test-2",
                    name: "Test List",
                    color: "#10b981"
                ),
                size: 24
            )
            Text("Medium (24pt)")
        }

        // Large size
        HStack(spacing: 12) {
            ListImageViewLarge(
                list: TaskList(
                    id: "test-3",
                    name: "Test List",
                    color: "#f59e0b"
                ),
                size: 64
            )
            Text("Large (64pt)")
        }
    }
    .padding()
}
