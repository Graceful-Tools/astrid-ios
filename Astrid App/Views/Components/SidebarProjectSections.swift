//  SidebarProjectSections.swift
//  The sidebar's Projects sections (ADEV-170), on iOS and the Mac. Each project is its own section,
//  headed by its name, its lists the section's rows, hidden while the project is collapsed
//  (ADEV-47/51/57). The sections, the header's name and its chevron are drawn here once; what a
//  header DOES — open the board on the Mac, the context menu, sheets, drops — stays with each
//  platform's `SidebarProjectsSection` / `MacProjectsSidebarSection`.

import SwiftUI

/// One `Section` per project entry (the core's `SidebarProjects` rule), its visible lists as rows.
struct SidebarProjectSections<Header: View, ListRow: View>: View {
    let entries: [SidebarProjectEntry]
    @ObservedObject var collapse: SidebarProjectCollapse
    @ViewBuilder let header: (Project, String) -> Header
    @ViewBuilder let listRow: (TaskList) -> ListRow

    var body: some View {
        ForEach(entries) { entry in
            Section {
                ForEach(collapse.visibleLists(entry.lists, in: entry.project.id)) { list in
                    listRow(list)
                }
            } header: {
                header(entry.project, entry.name)
            }
        }
    }
}

/// A project header's name: one line, pushed to the leading edge.
struct SidebarProjectHeaderTitle: View {
    let name: String

    var body: some View {
        HStack {
            Text(verbatim: name).lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Hide or show a project's lists (ADEV-57): the chevron, pointing down while expanded.
struct SidebarProjectCollapseToggle: View {
    let projectId: String
    let name: String
    @ObservedObject var collapse: SidebarProjectCollapse
    @ThemedPalette private var palette

    var body: some View {
        let expanded = !collapse.isCollapsed(projectId)
        Button {
            withAnimation { collapse.toggle(projectId) }
        } label: {
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(palette.textSecondary)
                .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        .help(collapse.toggleLabel(for: projectId, name: name))
        #else
        .buttonStyle(.borderless)
        #endif
        .accessibilityLabel(collapse.toggleLabel(for: projectId, name: name))
        .accessibilityIdentifier("sidebar.project.toggle.\(projectId)")
    }
}
