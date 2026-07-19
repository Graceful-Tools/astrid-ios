//  MacFilterSheet.swift
//  Astrid for Mac — native filter editor for a list (Task a2bf6ccb).
//
//  Previously Mac filters were READ-ONLY (the empty state told users to "adjust filters on iOS or
//  the web"). This writes the list's saved filter fields through the canonical service
//  (ListService.updateListAdvanced → optimistic + offline + server), and the SHARED
//  filterTasksForList immediately reflects them in the task list — same result as iOS/web.

#if os(macOS)
import SwiftUI

struct MacFilterSheet: View {
    let list: TaskList
    @Environment(\.dismiss) private var dismiss

    @State private var completion: String
    @State private var priority: String
    @State private var dueDate: String
    @State private var assignee: String
    @State private var showingSave = false
    @State private var smartListName = ""

    init(list: TaskList) {
        self.list = list
        _completion = State(initialValue: list.filterCompletion ?? "default")
        _priority   = State(initialValue: list.filterPriority ?? "all")
        _dueDate    = State(initialValue: list.filterDueDate ?? "all")
        _assignee   = State(initialValue: list.filterAssignee ?? "all")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filter “\(list.name)”").font(.headline).foregroundStyle(Theme.textPrimary)

            Form {
                filterPicker("Show", selection: $completion, options: MacListFilter.completion)
                filterPicker("Priority", selection: $priority, options: MacListFilter.priority)
                filterPicker("Due", selection: $dueDate, options: MacListFilter.dueDate)
                filterPicker("Assignee", selection: $assignee, options: MacListFilter.assignee)
            }
            .formStyle(.grouped)
            .frame(height: 190)

            // Save the current filters as a reusable Smart List (virtual list), like iOS/web.
            if showingSave {
                HStack {
                    TextField("Smart List name", text: $smartListName).textFieldStyle(.roundedBorder)
                    Button("Create") { saveSmartList() }
                        .buttonStyle(.borderedProminent)
                        .disabled(smartListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    smartListName = list.name; showingSave = true
                } label: { Label("Save as Smart List…", systemImage: "star") }
                .buttonStyle(.link)
                .disabled(MacListFilter.activeCount(completion: completion, priority: priority,
                                                    dueDate: dueDate, assignee: assignee) == 0)
            }

            HStack {
                Button("Clear filters") {
                    completion = "default"; priority = "all"; dueDate = "all"; assignee = "all"
                    save()
                }
                .disabled(MacListFilter.activeCount(completion: completion, priority: priority,
                                                    dueDate: dueDate, assignee: assignee) == 0)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    /// Create a saved-filter (Smart) list from the current filters — mirrors iOS SaveFilterDialog.
    private func saveSmartList() {
        let name = smartListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let updates = MacListFilter.smartListUpdates(completion: completion, priority: priority,
                                                     dueDate: dueDate, assignee: assignee,
                                                     sortBy: list.sortBy ?? "auto")
        dismiss()
        MacActions.perform("Save Smart List") {
            let newList = try await ListService.shared.createList(name: name, description: "Smart List", privacy: "PRIVATE")
            _ = try await ListService.shared.updateListAdvanced(listId: newList.id, updates: updates)
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [MacListFilter.Option]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { Text($0.label).tag($0.value) }
        }
        .onChange(of: selection.wrappedValue) { save() }
    }

    /// Persist all four filter fields through the canonical service (offline-first + server).
    private func save() {
        let updates: [String: Any] = [
            "filterCompletion": completion,
            "filterPriority": priority,
            "filterDueDate": dueDate,
            "filterAssignee": assignee,
        ]
        MacActions.perform("Update filters") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: updates)
        }
    }
}
#endif
