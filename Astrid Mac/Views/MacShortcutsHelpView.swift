//  MacShortcutsHelpView.swift
//  Astrid for Mac — Help → Keyboard Shortcuts (Task cdfbd79f).
//
//  Renders the canonical shared bare-key scheme (KeyboardShortcuts.all) that mirrors web,
//  so the Help menu / `?` key surface the real bindings rather than a dead stub.

#if os(macOS)
import SwiftUI

struct MacShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts").font(.title2.bold())
            Text("These match the Astrid web shortcuts. They’re ignored while you’re typing.")
                .font(.callout).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(KeyboardShortcuts.all.enumerated()), id: \.offset) { _, binding in
                        HStack(alignment: .firstTextBaseline) {
                            Text(binding.title).frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 4) {
                                ForEach(binding.keys, id: \.self) { key in
                                    Text(key)
                                        .font(.system(.callout, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
                                }
                            }
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}
#endif
