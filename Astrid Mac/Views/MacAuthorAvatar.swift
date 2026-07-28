//  MacAuthorAvatar.swift
//  Astrid for Mac — an author's photo, with initials as the placeholder (Task 283a03df).
//  Comment and chat surfaces drew initials only, so nobody ever had a picture — including you.

#if os(macOS)
import SwiftUI

struct MacAuthorAvatar: View {
    let display: MacAuthorDisplay
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let s = display.imageURL, let url = URL(string: s) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .help(display.name)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Theme.accent)
            Text(display.initials)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
#endif
