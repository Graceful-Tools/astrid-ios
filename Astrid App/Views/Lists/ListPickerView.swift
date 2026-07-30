import SwiftUI


struct ListPickerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var listService = ListService.shared
    @Binding var selectedList: TaskList?
    
    var body: some View {
        NavigationStack {
            List {
                // All tasks option
                Button {
                    selectedList = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(NSLocalizedString("lists.all_tasks", comment: "All Tasks"))
                        Spacer()
                        if selectedList == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                // Lists
                Section("Lists") {
                    ForEach(listService.lists) { list in
                        Button {
                            selectedList = list
                            dismiss()
                        } label: {
                            HStack {
                                ListImageView(list: list, size: 12)
                                Text(list.name)
                                Spacer()
                                if selectedList?.id == list.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("filters.filter_by_list", comment: "Filter by List"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
