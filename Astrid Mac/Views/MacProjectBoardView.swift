//  MacProjectBoardView.swift
//  Astrid for Mac — a project's board with its lists as rows (AITD-674, web AWTD-1660).
//
//  The columns are the project's own, answered by astrid-core's `board`. Each row asks the core's
//  `projectBoardRow` for that list's cards under the project's columns (AITD-676, CONTRACTS D67):
//  the list's manual order and Done window arrange them, and a role the project has no column for
//  waits in the Inbox. Which lists are rows is the person's choice, saved on the server through
//  the core (`ProjectBoardRowsService`). Cards drag between columns as on a single-list board,
//  through `TaskService.moveToBoardColumn`.

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
    /// The project's columns: the core's board for the project alone.
    @StateObject private var board = BoardModel()
    @State private var boardWidth: CGFloat = 0
    @State private var isDropTarget = false
    /// New List… from Add list (AITD-681): a list born in this project, then a row here.
    @State private var creatingList = false

    private var columns: [ProjectBoardColumn] { board.columns.map(\.column) }

    private var columnWidth: CGFloat {
        MacLayout.boardColumnWidth(columnCount: columns.count, availableWidth: boardWidth)
    }

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
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: MacLayout.boardColumnSpacing) {
                    columnHeaders
                    if rowLists.isEmpty {
                        Text(NSLocalizedString("project_mode.board_empty", comment: ""))
                            .macFont(.callout).foregroundStyle(Theme.textMuted)
                            .padding(AstridTokens.Space.s16)
                            .accessibilityIdentifier("projectBoard.empty")
                    }
                    ForEach(rowLists) { list in
                        MacProjectBoardRow(projectId: projectId, list: list, columns: columns, columnWidth: columnWidth,
                                           selectedTaskId: selectedTaskId,
                                           onRemove: { remove(list) }, onOpenTask: onOpenTask)
                    }
                }
                .padding(MacLayout.boardPadding)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
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
        .task(id: BoardModel.Query(projectId: projectId)) {
            board.update(BoardModel.Query(projectId: projectId))
        }
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

    private var columnHeaders: some View {
        HStack(spacing: MacLayout.boardColumnSpacing) {
            ForEach(columns) { column in
                Text(column.name).macFont(.headline).foregroundStyle(Theme.textSecondary)
                    .help(column.description)
                    .frame(width: columnWidth, alignment: .leading)
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

/// One list's row: its header and its cards under the project's columns.
private struct MacProjectBoardRow: View {
    let projectId: String
    let list: TaskList
    let columns: [ProjectBoardColumn]
    let columnWidth: CGFloat
    let selectedTaskId: String?
    let onRemove: () -> Void
    let onOpenTask: (String, CGRect?) -> Void

    @StateObject private var taskService = TaskService.shared
    /// This row as the core draws it: the list's cards under the project's columns.
    @StateObject private var board = BoardModel()
    @State private var dropTargetColumnId: String?
    @State private var hoveredCardId: String?

    private var query: BoardModel.Query { BoardModel.Query(listId: list.id, rowOfProjectId: projectId) }

    private var cells: [String: [String]] {
        Dictionary(board.columns.map { ($0.id, $0.ids) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let cells = self.cells
        VStack(alignment: .leading, spacing: AstridTokens.Space.s8) {
            HStack(spacing: AstridTokens.Space.s8) {
                MacListIcon(list: list, size: 14)
                Text(list.name).macFont(.headline).foregroundStyle(Theme.textPrimary)
                Text(verbatim: "\(cells.values.reduce(0) { $0 + $1.count })")
                    .macFont(.caption).foregroundStyle(Theme.textMuted)
                Button(action: onRemove) {
                    Image(systemName: "xmark").macFont(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(format: NSLocalizedString("project_mode.board_remove_row", comment: ""), list.name))
                .accessibilityLabel(String(format: NSLocalizedString("project_mode.board_remove_row", comment: ""), list.name))
                .accessibilityIdentifier("projectBoard.removeRow")
            }
            HStack(alignment: .top, spacing: MacLayout.boardColumnSpacing) {
                ForEach(columns) { column in
                    cell(column, ids: cells[column.id] ?? [])
                }
            }
        }
        .task(id: query) { board.update(query) }
        .accessibilityIdentifier("projectBoard.row.\(list.id)")
    }

    private func cell(_ column: ProjectBoardColumn, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: AstridTokens.Space.s8) {
            ForEach(ids.compactMap { taskService.tasksById[$0] }) { task in card(task) }
        }
        .padding(AstridTokens.Space.s8)
        .frame(width: columnWidth, alignment: .topLeading)
        .frame(minHeight: AstridTokens.Space.s48, alignment: .top)
        .background(RoundedRectangle(cornerRadius: AstridTokens.Radius.md)
            .fill(dropTargetColumnId == column.id ? Theme.bgSelected : Theme.bgTertiary))
        .animation(MacMotion.fast, value: dropTargetColumnId)
        .dropDestination(for: String.self) { payloads, _ in
            guard let taskId = payloads.first, ProjectBoardListDrag.listId(from: taskId) == nil else { return false }
            move(taskId: taskId, to: column)
            return true
        } isTargeted: { dropTargetColumnId = $0 ? column.id : nil }
    }

    private func card(_ task: Task) -> some View {
        VStack(alignment: .leading, spacing: AstridTokens.Space.s2) {
            Text(task.title).foregroundStyle(Theme.textPrimary).strikethrough(task.completed)
            let identifier = TaskIdentifiers.boardCardLabel(for: task)
            if identifier != nil || task.dueDateTime != nil {
                HStack(spacing: AstridTokens.Space.s4) {
                    if let identifier { Text(identifier).lineLimit(1).fixedSize() }
                    if let due = MacDueText.text(for: task.dueDateTime, isAllDay: task.isAllDay) {
                        Text(due).lineLimit(1)
                    }
                }
                .macFont(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(AstridTokens.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacSelectionStyle.fill(isSelected: false, hovering: hoveredCardId == task.id))
        .clipShape(RoundedRectangle(cornerRadius: AstridTokens.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: AstridTokens.Radius.sm)
            .stroke(MacSelectionStyle.borderColor(isSelected: selectedTaskId == task.id,
                                                  hovering: hoveredCardId == task.id),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: selectedTaskId == task.id)))
        .onHover { hovering in
            hoveredCardId = hovering ? task.id : (hoveredCardId == task.id ? nil : hoveredCardId)
        }
        // Opens the pop-out beside the card, as a list row opens it (AITD-679).
        .modifier(MacBoardCardAnchor(isSelected: selectedTaskId == task.id) { onOpenTask(task.id, $0) })
        .draggable(task.id)
        .accessibilityIdentifier("projectBoard.card")
    }

    private func move(taskId: String, to column: ProjectBoardColumn) {
        // The same move a list's board makes, against this row's list (CONTRACTS D45).
        guard let task = taskService.tasksById[taskId] else { return }
        let listId = list.id
        AppActions.perform("Move task") {
            try await WaitingPromptPresenter.shared.move(task) { wait in
                try await TaskService.shared.moveToBoardColumn(taskId: taskId, columnId: column.id,
                                                               listId: listId, wait: wait)
            }
        }
    }
}
#endif
