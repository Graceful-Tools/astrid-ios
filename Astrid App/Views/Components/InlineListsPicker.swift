import SwiftUI

/// Inline multi-list picker with search (matching mobile web)
struct InlineListsPicker: View {
    @Environment(\.colorScheme) var colorScheme

    let label: String
    @Binding var selectedListIds: [String]
    let availableLists: [TaskList]
    let onSave: (() async -> Void)?
    var showLabel: Bool = true

    @State private var isEditing = false
    @State private var tempSelection: Set<String> = []
    @State private var searchText = ""
    @State private var isSaving = false
    @State private var wasCancelled = false

    var filteredLists: [TaskList] {
        // Filter out virtual lists (saved filters) - users can't add tasks to these
        let realLists = availableLists.filter { $0.isVirtual != true }

        if searchText.isEmpty {
            return realLists
        }
        return realLists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedLists: [TaskList] {
        availableLists.filter { selectedListIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            if showLabel {
                Text(label)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            if isEditing {
                VStack(spacing: Theme.spacing12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        TextField("Search lists...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(Theme.spacing8)
                    .background(colorScheme == .dark ? Theme.Dark.inputBg : Theme.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder, lineWidth: 1)
                    )

                    // List selection
                    ScrollView {
                        VStack(spacing: Theme.spacing4) {
                            if filteredLists.isEmpty {
                                Text(NSLocalizedString("picker.no_lists", comment: "No lists found"))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.spacing24)
                            } else {
                                ForEach(filteredLists) { list in
                                    ListSelectionRow(
                                        list: list,
                                        isSelected: tempSelection.contains(list.id),
                                        colorScheme: colorScheme
                                    ) {
                                        toggleListSelection(list.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    // Selected count
                    if !tempSelection.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.success)
                            Text("\(tempSelection.count) list\(tempSelection.count == 1 ? "" : "s") selected")
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.spacing8)
                    }

                    // Actions
                    HStack(spacing: Theme.spacing12) {
                        Button("Cancel") {
                            wasCancelled = true
                            isEditing = false
                        }
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing8)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                        Button("Close") {
                            saveLists()
                        }
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing8)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .disabled(isSaving)
                        .opacity(isSaving ? 0.6 : 1.0)
                    }
                }
                .padding(Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else {
                Button {
                    tempSelection = Set(selectedListIds)
                    isEditing = true
                } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        if selectedLists.isEmpty {
                            HStack {
                                Text(NSLocalizedString("picker.add_to_lists", comment: "Add to lists"))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        } else {
                            // Show selected lists as badges
                            FlowLayout(spacing: Theme.spacing8) {
                                ForEach(selectedLists) { list in
                                    ListBadge(list: list, colorScheme: colorScheme)
                                }
                            }
                        }
                    }
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isEditing) { wasEditing, nowEditing in
            // Auto-save when picker closes (unless cancelled)
            if wasEditing && !nowEditing && !wasCancelled && !isSaving {
                // Check if selection changed
                if Set(selectedListIds) != tempSelection {
                    saveLists()
                }
            }
            // Reset cancelled flag when opening
            if nowEditing {
                wasCancelled = false
            }
        }
        .onDisappear {
            // Auto-save if view disappears while still editing (e.g., parent dismissed)
            if isEditing && !wasCancelled && !isSaving {
                if Set(selectedListIds) != tempSelection {
                    saveLists()
                }
            }
        }
    }

    private func toggleListSelection(_ listId: String) {
        if tempSelection.contains(listId) {
            tempSelection.remove(listId)
        } else {
            tempSelection.insert(listId)
        }
    }

    private func saveLists() {
        isSaving = true
        _Concurrency.Task {
            selectedListIds = Array(tempSelection)
            if let onSave = onSave {
                await onSave()
            }
            isSaving = false
            isEditing = false
        }
    }
}

// MARK: - List Selection Row

struct ListSelectionRow: View {
    let list: TaskList
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                ListImageView(list: list, size: 12)

                Text(list.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
            }
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, Theme.spacing8)
            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - List Badge

struct ListBadge: View {
    let list: TaskList
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: Theme.spacing4) {
            ListImageView(list: list, size: 8)
            Text(list.name)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
        }
        .padding(.horizontal, Theme.spacing8)
        .padding(.vertical, Theme.spacing4)
        .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

#Preview {
    let sampleLists = [
        TaskList(
            id: "1",
            name: "Personal",
            color: "#3b82f6",
            privacy: .PRIVATE,
            isVirtual: false
        ),
        TaskList(
            id: "2",
            name: "Work",
            color: "#ef4444",
            privacy: .PRIVATE,
            isVirtual: false
        ),
        TaskList(
            id: "3",
            name: "Shopping",
            color: "#10b981",
            privacy: .PRIVATE,
            isVirtual: false
        )
    ]

    VStack(spacing: 24) {
        InlineListsPicker(
            label: "Lists",
            selectedListIds: .constant([]),
            availableLists: sampleLists,
            onSave: nil
        )
        .padding()

        InlineListsPicker(
            label: "Lists",
            selectedListIds: .constant(["1", "2"]),
            availableLists: sampleLists,
            onSave: nil
        )
        .padding()
    }
    .background(Theme.bgPrimary)
}
