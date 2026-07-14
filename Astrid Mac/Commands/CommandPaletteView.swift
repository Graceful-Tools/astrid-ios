//  CommandPaletteView.swift
//  Astrid for Mac — ⌘K command palette / quick-open (M2).

#if os(macOS)
import SwiftUI

struct CommandPaletteView: View {
    let registry: CommandRegistry
    @State private var query = ""
    @State private var selection: String?
    @Environment(\.dismiss) private var dismiss

    private var results: [AppCommand] { registry.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command or search tasks & lists…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(16)
                .onSubmit(runSelectedOrFirst)
            Divider()
            List(results, selection: $selection) { cmd in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.title)
                        if let sub = cmd.subtitle {
                            Text(sub).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let s = cmd.shortcut {
                        Text(s).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .tag(cmd.id)
                .contentShape(Rectangle())
                .onTapGesture { run(cmd) }
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 400)
    }

    private func runSelectedOrFirst() {
        if let id = selection, let cmd = results.first(where: { $0.id == id }) { run(cmd) }
        else if let first = results.first { run(first) }
    }

    private func run(_ cmd: AppCommand) {
        cmd.run()
        dismiss()
    }
}
#endif
