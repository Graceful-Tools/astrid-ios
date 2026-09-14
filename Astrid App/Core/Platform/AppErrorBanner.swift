//  AppErrorBanner.swift
//  Astrid — the transient error banner driven by `AppErrorCenter` (task 8a5f3066, AITD-400).
//
//  Shared so adopting it is a one-line change rather than a second implementation. Both roots
//  place it now: `MacAuthGateView` and `AstridApp` (AITD-406).

import SwiftUI

struct AppErrorBanner: View {
    @StateObject private var center = AppErrorCenter.shared

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
