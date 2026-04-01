import SwiftUI

/// Bouncing dots typing indicator shown when an AI agent is processing
struct AgentTypingIndicator: View {
    let agentName: String
    @Environment(\.colorScheme) var colorScheme

    @State private var dot1 = false
    @State private var dot2 = false
    @State private var dot3 = false

    var body: some View {
        HStack(spacing: Theme.spacing8) {
            // Bouncing dots
            HStack(spacing: 3) {
                Circle()
                    .fill(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .frame(width: 6, height: 6)
                    .offset(y: dot1 ? -4 : 0)
                Circle()
                    .fill(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .frame(width: 6, height: 6)
                    .offset(y: dot2 ? -4 : 0)
                Circle()
                    .fill(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .frame(width: 6, height: 6)
                    .offset(y: dot3 ? -4 : 0)
            }
            .frame(height: 16)

            Text("\(agentName) is thinking...")
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
        }
        .padding(.horizontal, Theme.spacing12)
        .padding(.vertical, Theme.spacing8)
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { dot1 = true }
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(0.15)) { dot2 = true }
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(0.3)) { dot3 = true }
    }
}
