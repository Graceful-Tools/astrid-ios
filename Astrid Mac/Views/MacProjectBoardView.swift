//  MacProjectBoardView.swift
//  Astrid for Mac — a project's board with its lists as rows (AITD-674, web AWTD-1660).
//
//  The columns are the project's own, answered by astrid-core's `board`. Each row asks the core's
//  `projectBoardRow` for that list's cards under the project's columns (AITD-676, CONTRACTS D67):
//  the list's manual order and Done window arrange them, and a role the project has no column for
//  waits in the Inbox. Which lists are rows is the person's choice, saved on the server through
//  the core (`ProjectBoardRowsService`). Cards drag between columns as on a single-list board,
//  through `TaskService.moveToBoardColumn`.
//
//  Each row IS the list's board (ADEV-59): `MacBoardView` asked for the list's row of the project,
//  at a fixed height — column panels with their names and counts, three or four cards that scroll
//  inside each column, and Add a task at the bottom of every column.

#if os(macOS)
import SwiftUI

struct MacProjectBoardView: View {
    let projectId: String
    /// The task whose details pop-out is open, for the card's selection outline.
    var selectedTaskId: String?
    /// Open a card's task in the detail pop-out, beside the card (its global frame, AITD-679).
    let onOpenTask: (String, CGRect?) -> Void

    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false
    @StateObject private var listService = ListService.shared
    @StateObject private var rows = ProjectBoardRowsService.shared
    @State private var isDropTarget = false
    /// New List… from Add list (AITD-681): a list born in this project, then a row here.
    @State private var creatingList = false

    private var listsById: [String: TaskList] {
        Dictionary(listService.lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var rowLists: [TaskList] {
        let byId = listsById
        return rows.rowIds(projectId: projectId).compactMap { byId[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            // Rows stack and scroll down; each row's columns scroll across on their own, as the
            // list's board does, and its cards scroll inside the fixed-height column (ADEV-59).
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if rowLists.isEmpty {
                        Text(NSLocalizedString("project_mode.board_empty", comment: ""))
                            .macFont(.callout).foregroundStyle(Theme.textMuted)
                            .padding(AstridTokens.Space.s16)
                            .accessibilityIdentifier("projectBoard.empty")
                    }
                    ForEach(rowLists) { list in
                        MacProjectBoardRow(projectId: projectId, list: list, selectedTaskId: selectedTaskId,
                                           onRemove: { remove(list) }, onOpenTask: onOpenTask)
                    }
                }
            }
            .macScrollBars(showScrollBars)
            .scrollContentBackground(.hidden)
        }
        .background(isDropTarget ? Theme.bgTertiary : Theme.bgPrimary)
        // A list dragged from the sidebar becomes a row (web `PROJECT_BOARD_LIST_DRAG_TYPE`).
        .dropDestination(for: String.self) { payloads, _ in
            let listIds = payloads.compactMap(ProjectBoardListDrag.listId(from:))
            guard !listIds.isEmpty else { return false }
            for listId in listIds { add(listId) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .task(id: projectId) { await rows.load(projectId: projectId) }
        .accessibilityIdentifier("projectBoard")
    }

    private var toolbar: some View {
        HStack(spacing: AstridTokens.Space.s12) {
            Spacer()
            if rows.saveFailed == projectId {
                Text(NSLocalizedString("project_mode.board_save_failed", comment: ""))
                    .macFont(.caption).foregroundStyle(Theme.errorInk)
            }
            addListMenu
        }
        .padding(.horizontal, MacLayout.boardPadding)
        .padding(.top, AstridTokens.Space.s8)
    }

    private var addListMenu: some View {
        let byId = listsById
        let candidates = rows.candidateIds(projectId: projectId).compactMap { byId[$0] }
        return Menu {
            if candidates.isEmpty {
                Text(NSLocalizedString("project_mode.board_no_candidates", comment: ""))
            }
            ForEach(candidates) { list in
                Button(list.name) { add(list.id) }
            }
            if MacListProjectControl.offersNewList(in: projectId, moves: listService.projectMoves(listId: nil)) {
                Divider()
                Button(NSLocalizedString("projects.new_list", comment: "")) { creatingList = true }
                    .accessibilityIdentifier("projectBoard.newList")
            }
        } label: {
            Label(NSLocalizedString("project_mode.board_add_list", comment: ""), systemImage: "plus")
        }
        .fixedSize()
        .disabled(!rows.canAddRow(projectId: projectId))
        .accessibilityIdentifier("projectBoard.addList")
        .sheet(isPresented: $creatingList) {
            if let project = ProjectService.shared.project(id: projectId) {
                MacNewListInProjectSheet(project: project) { list in
                    _Concurrency.Task {
                        await rows.load(projectId: projectId)
                        await rows.addRow(projectId: projectId, listId: list.id)
                    }
                }
            }
        }
    }

    private func add(_ listId: String) {
        _Concurrency.Task { await rows.addRow(projectId: projectId, listId: listId) }
    }

    private func remove(_ list: TaskList) {
        _Concurrency.Task { await rows.removeRow(projectId: projectId, listId: list.id) }
    }
}

/// One list's row: its header, then the list's own board under the project's columns (ADEV-59).
private struct MacProjectBoardRow: View {
    let projectId: String
    let list: TaskList
    let selectedTaskId: String?
    let onRemove: () -> Void
    let onOpenTask: (String, CGRect?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AstridTokens.Space.s8) {
                MacListIcon(list: list, size: 14)
                Text(list.name).macFont(.headline).foregroundStyle(Theme.textPrimary)
                Button(action: onRemove) {
                    Image(systemName: "xmark").macFont(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(format: NSLocalizedString("project_mode.board_remove_row", comment: ""), list.name))
                .accessibilityLabel(String(format: NSLocalizedString("project_mode.board_remove_row", comment: ""), list.name))
                .accessibilityIdentifier("projectBoard.removeRow")
            }
            .padding(.horizontal, MacLayout.boardPadding)
            .padding(.top, MacLayout.boardPadding)
            MacBoardView(listId: list.id, selectedTaskId: selectedTaskId, onOpenCard: onOpenTask,
                         rowOfProjectId: projectId, columnHeight: MacLayout.projectBoardRowHeight)
        }
        .accessibilityIdentifier("projectBoard.row.\(list.id)")
    }
}
#endif
