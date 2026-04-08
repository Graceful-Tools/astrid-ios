import SwiftUI

/// Profile avatar button that replaces the hamburger menu icon.
/// Shows the user's profile photo (or initials fallback) as a small circle.
/// Tapping opens the sidebar (same as the hamburger menu).
struct ProfileMenuButton: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        if authManager.isLocalOnlyMode {
            // Show generic person icon for local-only users
            Circle()
                .fill(Theme.accent.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.accent)
                }
        } else if let user = authManager.currentUser,
                  let imageUrl = user.image,
                  let url = URL(string: imageUrl) {
            CachedAsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Theme.accent)
                    .overlay {
                        Text(user.initials)
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .semibold))
                    }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay {
                    if let user = authManager.currentUser {
                        Text(user.initials)
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
        }
    }
}
