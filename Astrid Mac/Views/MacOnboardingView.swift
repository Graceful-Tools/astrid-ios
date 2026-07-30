//  MacOnboardingView.swift
//  Astrid for Mac — first-run onboarding (Task 0eeac7e8). Shown once; points at the key
//  Mac affordances (Quick Add hotkey, command palette, keyboard shortcuts).

#if os(macOS)
import SwiftUI

struct MacOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Feature: Identifiable {
        let id = UUID(); let icon: String; let title: String; let detail: String
    }

    private let features = [
        Feature(icon: "bolt.fill",
                title: NSLocalizedString("mac.onboard.quickadd.title", comment: ""),
                detail: NSLocalizedString("mac.onboard.quickadd.detail", comment: "")),
        Feature(icon: "command",
                title: NSLocalizedString("mac.onboard.palette.title", comment: ""),
                detail: NSLocalizedString("mac.onboard.palette.detail", comment: "")),
        Feature(icon: "keyboard",
                title: NSLocalizedString("mac.onboard.keyboard.title", comment: ""),
                detail: Brand.localized("mac.onboard.keyboard.detail")),
        Feature(icon: "arrow.triangle.2.circlepath",
                title: NSLocalizedString("mac.onboard.offline.title", comment: ""),
                detail: NSLocalizedString("mac.onboard.offline.detail", comment: "")),
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(Theme.accent)
                Text(Brand.localized("mac.welcome")).font(.title2.bold())
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(features) { f in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: f.icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.headline)
                            Text(f.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button(NSLocalizedString("mac.get_started", comment: "")) { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.getStarted")
        }
        .padding(28)
        .frame(width: 440)
        .background(Theme.bgPrimary)
    }
}
#endif
