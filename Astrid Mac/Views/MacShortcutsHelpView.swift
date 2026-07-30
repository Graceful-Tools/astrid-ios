//  MacShortcutsHelpView.swift
//  Astrid for Mac — Help → Keyboard Shortcuts (Task cdfbd79f).
//
//  Renders the canonical shared bare-key scheme (KeyboardShortcuts.all) that mirrors web,
//  so the Help menu / `?` key surface the real bindings rather than a dead stub.

#if os(macOS)
import SwiftUI

struct MacShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder private func row(_ title: String, keys: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("mac.keyboard_shortcuts", comment: "")).font(.title2.bold())
            Text(Brand.localized("mac.shortcuts_note"))
                .font(.callout).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(KeyboardShortcuts.all.enumerated()), id: \.offset) { _, binding in
                        row(MacShortcutTitle.localized(for: binding.action), keys: binding.keys)
                    }

                    // The ⌘ menu equivalents, from the same table the menus bind (e0412a64) —
                    // this sheet used to advertise only the bare keys.
                    Text(NSLocalizedString("mac.menu_commands", comment: ""))
                        .font(.callout.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12).padding(.bottom, 4)
                    ForEach(MacShortcutsHelpModel.menuRows, id: \.command) { binding in
                        row(binding.title, keys: [MacMenuShortcuts.display(for: binding.command)])
                    }
                }
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
    }
}
#endif
