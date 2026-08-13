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
                    // This used to carry an `.id(url)`, because CachedAsyncImage captured its URL
                    // once and a new identity was the only way to make it refetch. The component
                    // follows its url itself now (16f39f36), so forcing a full rebuild of the row
                    // icon on every image change is no longer needed.
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(hex: list.displayColor) ?? Theme.accent)
                    }
                } else {
                    Circle().fill(Color(hex: list.displayColor) ?? Theme.accent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
#endif
