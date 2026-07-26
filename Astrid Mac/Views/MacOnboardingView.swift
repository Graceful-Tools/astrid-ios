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
        Feature(icon: "bolt.fill", title: "Quick Add anywhere",
                detail: "Press ⌥Space to capture a task from any app — with natural-language dates, #lists and priorities."),
        Feature(icon: "command", title: "Command palette",
                detail: "⌘K to search tasks and lists and run actions without leaving the keyboard."),
        Feature(icon: "keyboard", title: "Keyboard-first",
                detail: "The same shortcuts as Astrid on the web. Press ? any time to see them."),
        Feature(icon: "arrow.triangle.2.circlepath", title: "Works offline",
                detail: "Everything you do is saved locally and syncs when you’re back online."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(Theme.accent)
                Text(NSLocalizedString("mac.welcome", comment: "")).font(.title2.bold())
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
