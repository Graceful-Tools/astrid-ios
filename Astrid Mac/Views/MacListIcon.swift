//  MacListIcon.swift
//  Astrid for Mac — list swatch mirroring the iOS ListImageView (Task: Mac UI mapping).
//  Rounded-square image (from the list's image URL) with a colored-circle fallback using the
//  list's displayColor — replaces the generic "list.bullet" icon.

#if os(macOS)
import SwiftUI

struct MacListIcon: View {
    let list: TaskList
    var size: CGFloat = 14

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                if let url = ListImageHelper.getFullImageUrl(list: list) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(hex: list.displayColor) ?? Theme.accent)
                    }
                    .id(url)
                } else {
                    Circle().fill(Color(hex: list.displayColor) ?? Theme.accent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
#endif
