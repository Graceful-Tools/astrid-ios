//  CommandRegistry.swift
//  Astrid for Mac — single source mapping commands -> shared-service actions (M2).
//
//  The menu bar, the bare-key handler, and the ⌘K palette all resolve through this one
//  registry, so every command routes through the shared services (never the API directly).

import Foundation

struct AppCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let shortcut: String?
    let run: () -> Void

    static func == (l: AppCommand, r: AppCommand) -> Bool { l.id == r.id }
}

final class CommandRegistry {
    private(set) var commands: [AppCommand] = []

    init(commands: [AppCommand] = []) { self.commands = commands }

    func register(_ command: AppCommand) { commands.append(command) }

    /// Fuzzy-ranked commands for a query (empty query returns all, registration order).
    func search(_ query: String) -> [AppCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }
        return commands
            .compactMap { cmd -> (AppCommand, Int)? in
                FuzzyMatch.score(trimmed, cmd.title).map { (cmd, $0) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.count < $1.0.title.count }
            .map { $0.0 }
    }
}
