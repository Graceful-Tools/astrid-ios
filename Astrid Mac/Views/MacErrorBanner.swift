//  MacErrorBanner.swift
//  Astrid for Mac — transient error banner driven by MacErrorCenter (Task 8a5f3066).

#if os(macOS)
import SwiftUI

struct MacErrorBanner: View {
    @StateObject private var center = MacErrorCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let banner = center.current {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                    Text(banner.text).foregroundStyle(.white).lineLimit(2)
                    Spacer()
                    Button { center.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.8))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.error))
                .shadow(radius: 6)
                .padding(16)
                .frame(maxWidth: 520)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("error.banner")
            }
        }
        .animation(.spring(duration: 0.3), value: center.current)
        .allowsHitTesting(center.current != nil)
    }
}
#endif
