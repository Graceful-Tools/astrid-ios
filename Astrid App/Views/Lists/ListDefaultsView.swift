import SwiftUI

struct ListDefaultsView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    @ObservedObject private var memberService = ListMemberService.shared

    let list: TaskList

    @State private var defaultAssigneeId: String?
    @State private var defaultPriority: Int
    @State private var defaultRepeating: String
    @State private var defaultIsPrivate: Bool
    @State private var defaultDueDate: String
    @State private var defaultDueTime: Date?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaveSuccess = false

    init(list: TaskList) {
        self.list = list
        _defaultAssigneeId = State(initialValue: list.defaultAssigneeId)
        _defaultPriority = State(initialValue: list.defaultPriority ?? 0)
        _defaultRepeating = State(initialValue: list.defaultRepeating ?? "never")
        _defaultIsPrivate = State(initialValue: list.defaultIsPrivate ?? true)
        _defaultDueDate = State(initialValue: list.defaultDueDate ?? "none")
        _defaultDueTime = State(initialValue: Self.parseTime(list.defaultDueTime))
    }

    var body: some View {
        Form {
            Section {
                Text(NSLocalizedString("list.defaults_description", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
            }

            // Default Assignee - Hidden for local users
            if !AuthManager.shared.isLocalOnlyMode {
                Section(NSLocalizedString("tasks.assignee", comment: "")) {
                    Picker(NSLocalizedString("filters.who", comment: ""), selection: $defaultAssigneeId) {
                        Text(NSLocalizedString("list.task_creator", comment: "")).tag(nil as String?)
                        Text(NSLocalizedString("filters.unassigned", comment: "")).tag("unassigned" as String?)

                        if !memberService.members.isEmpty {
                            Divider()
                            ForEach(memberService.members) { member in
                                Text(member.displayName).tag(member.id as String?)
                            }
                        }
                    }
                    .onChange(of: defaultAssigneeId) { saveDefaults() }
                }
            }

            // Default Priority
            Section(NSLocalizedString("tasks.priority", comment: "")) {
                Picker(NSLocalizedString("tasks.priority", comment: ""), selection: $defaultPriority) {
                    Text(NSLocalizedString("filters.low_priority", comment: "")).tag(0)
                    Text(NSLocalizedString("filters.medium_priority", comment: "")).tag(1)
                    Text(NSLocalizedString("filters.high_priority", comment: "")).tag(2)
                    Text(NSLocalizedString("filters.highest_priority", comment: "")).tag(3)
                }
                .pickerStyle(.segmented)
                .onChange(of: defaultPriority) { saveDefaults() }
            }

            // Default Repeating
            Section(NSLocalizedString("lists.repeating", comment: "")) {
                Picker(NSLocalizedString("lists.repeating", comment: ""), selection: $defaultRepeating) {
                    Text(NSLocalizedString("lists.never", comment: "")).tag("never")
                    Text(NSLocalizedString("lists.daily", comment: "")).tag("daily")
                    Text(NSLocalizedString("lists.weekly", comment: "")).tag("weekly")
                    Text(NSLocalizedString("lists.monthly", comment: "")).tag("monthly")
                    Text(NSLocalizedString("lists.yearly", comment: "")).tag("yearly")
                }
                .onChange(of: defaultRepeating) { saveDefaults() }
            }

            // Default Due Date
            Section(NSLocalizedString("tasks.due_date", comment: "")) {
                Picker(NSLocalizedString("tasks.due_date", comment: ""), selection: $defaultDueDate) {
                    Text(NSLocalizedString("lists.none", comment: "")).tag("none")
                    Text(NSLocalizedString("time.today", comment: "")).tag("today")
                    Text(NSLocalizedString("lists.tomorrow", comment: "")).tag("tomorrow")
                    Text(NSLocalizedString("lists.next_week", comment: "")).tag("next_week")
                }
                .onChange(of: defaultDueDate) { _, newValue in
                    if newValue == "none" {
                        defaultDueTime = nil
                    }
                    saveDefaults()
                }

                if defaultDueDate != "none" {
                    DatePicker(
                        NSLocalizedString("tasks.due_time", comment: ""),
                        selection: Binding(
                            get: { defaultDueTime ?? Date() },
                            set: { defaultDueTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .onChange(of: defaultDueTime) { saveDefaults() }
                }
            }

            // Default Privacy
            Section(NSLocalizedString("lists.list_privacy", comment: "")) {
                Toggle(NSLocalizedString("lists.private_description", comment: ""), isOn: $defaultIsPrivate)
                    .onChange(of: defaultIsPrivate) { saveDefaults() }

                if defaultIsPrivate {
                    Text(NSLocalizedString("lists.private_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
            }

            // List ID for API/OAuth integration
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("lists.list", comment: "") + " ID")
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                    HStack {
                        Text(list.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .textSelection(.enabled)

                        Spacer()

                        Button(action: {
                            UIPasteboard.general.string = list.id
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(NSLocalizedString("list.oauth_hint", comment: "Use this ID for OAuth API integrations and coding agents"))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
            }

            if isSaving {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("messages.saving", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        Spacer()
                    }
                }
            }

            if showSaveSuccess {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("messages.saved", comment: ""))
                            .font(Theme.Typography.caption1())
                    }
                }
            }

            if let error = saveError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("list.task_defaults", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMembers()
        }
    }

    private func loadMembers() async {
        do {
            try await memberService.fetchMembers(listId: list.id)
        } catch {
            print("Failed to load members: \(error)")
        }
    }

    private func saveDefaults() {
        guard !isSaving else { return }

        isSaving = true
        saveError = nil

        // Show success immediately (optimistic update)
        showSaveSuccess = true

        _Concurrency.Task {
            let defaults = ListDefaults(
                defaultAssigneeId: defaultAssigneeId,
                defaultPriority: defaultPriority,
                defaultRepeating: defaultRepeating,
                defaultIsPrivate: defaultIsPrivate,
                defaultDueDate: defaultDueDate,
                defaultDueTime: formatTime(defaultDueTime)
            )

            print("[ListDefaults] Saving defaults for list '\(list.name)':")
            print("  - defaultPriority: \(defaultPriority)")
            print("  - defaultDueDate: \(defaultDueDate)")
            print("  - defaultDueTime: \(formatTime(defaultDueTime) ?? "nil")")
            print("  - defaultIsPrivate: \(defaultIsPrivate)")
            print("  - defaultRepeating: \(defaultRepeating)")
            print("  - defaultAssigneeId: \(defaultAssigneeId ?? "nil")")

            do {
                // Sync to server in background (non-blocking)
                let updatedList = try await listService.updateListAdvanced(
                    listId: list.id,
                    updates: defaults.toDictionary()
                )
                print("[ListDefaults] List defaults synced to server")
                print("[ListDefaults] Server returned updated list:")
                print("  - defaultPriority: \(updatedList.defaultPriority ?? -1)")
                print("  - defaultDueDate: \(updatedList.defaultDueDate ?? "nil")")
                print("  - defaultDueTime: \(updatedList.defaultDueTime ?? "nil")")

                await MainActor.run {
                    isSaving = false
                    // Hide success message after 1 second
                    _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                        await MainActor.run {
                            showSaveSuccess = false
                        }
                    }
                }
            } catch {
                print("[Optimistic] Failed to sync defaults to server: \(error)")

                await MainActor.run {
                    isSaving = false
                    showSaveSuccess = false
                    saveError = "Sync issue: \(error.localizedDescription). Changes saved locally."

                    // Hide error after 3 seconds
                    _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            saveError = nil
                        }
                    }
                }
            }
        }
    }

    private static func parseTime(_ timeString: String?) -> Date? {
        guard let timeString = timeString else { return nil }

        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        return Calendar.current.date(from: dateComponents)
    }

    private func formatTime(_ date: Date?) -> String? {
        guard let date = date else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
