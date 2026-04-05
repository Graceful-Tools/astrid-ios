import SwiftUI
import EventKit

/**
 * AppleRemindersSettingsView
 *
 * Settings view for managing Apple Reminders sync:
 * - Request Reminders permission
 * - Link/unlink Astrid lists to Reminders calendars
 * - Choose sync direction (export/import/bidirectional)
 * - Manual sync controls
 */
struct AppleRemindersSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var remindersService = AppleRemindersService.shared
    @StateObject private var listService = ListService.shared

    @State private var showingLinkSheet = false
    @State private var selectedListForLink: TaskList?
    @State private var showingImportSheet = false
    @State private var selectedCalendarForImport: EKCalendar?

    var body: some View {
        ZStack {
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FloatingTextHeader(NSLocalizedString("apple_reminders", comment: ""), icon: "checklist", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                List {
                    // Authorization Section
                    authorizationSection

                    // Sync Status Section (if authorized)
                    if remindersService.hasPermission {
                        syncStatusSection
                    }

                    // Your Lists Section (if authorized)
                    if remindersService.hasPermission {
                        yourListsSection
                    }

                    // Import from Reminders Section (if authorized)
                    if remindersService.hasPermission {
                        importFromRemindersSection
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                remindersService.checkAuthorizationStatus()
            }
        }
        .sheet(isPresented: $showingLinkSheet) {
            if let list = selectedListForLink {
                LinkListSheet(list: list, onDismiss: { showingLinkSheet = false })
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            if let calendar = selectedCalendarForImport {
                ImportCalendarSheet(calendar: calendar, onDismiss: { showingImportSheet = false })
            }
        }
    }

    // MARK: - Authorization Section

    private var authorizationSection: some View {
        Section {
            if remindersService.hasPermission {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("reminders.access_granted", comment: ""))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
            } else if remindersService.authorizationStatus == .denied {
                Button {
                    openSettings()
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("reminders.access_denied", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("reminders.tap_to_open_settings", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    requestAccess()
                } label: {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundColor(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("reminders.enable_sync", comment: ""))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            Text(NSLocalizedString("reminders.sync_description", comment: ""))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(NSLocalizedString("reminders.access_header", comment: ""))
        } footer: {
            Text(NSLocalizedString("reminders.access_footer", comment: ""))
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
        }
    }

    // MARK: - Sync Status Section

    private var syncStatusSection: some View {
        Section(NSLocalizedString("reminders.sync_status", comment: "")) {
            HStack {
                Label(NSLocalizedString("reminders.last_sync", comment: ""), systemImage: "clock")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                if let lastSync = remindersService.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                } else {
                    Text(NSLocalizedString("never", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }

            HStack {
                Label(NSLocalizedString("reminders.linked_lists", comment: ""), systemImage: "list.bullet")
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Spacer()
                Text("\(remindersService.linkedListCount)")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            // Prominent Sync All Button
            Button {
                syncAll()
            } label: {
                HStack {
                    Spacer()
                    if remindersService.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("reminders.syncing", comment: ""))
                            .font(Theme.Typography.body())
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(NSLocalizedString("reminders.sync_all_lists", comment: ""))
                            .font(Theme.Typography.body())
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(remindersService.linkedListCount == 0 ? Color.gray : Theme.accent)
                )
            }
            .disabled(remindersService.isSyncing || remindersService.linkedListCount == 0)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Your Lists Section

    private var yourListsSection: some View {
        Section {
            ForEach(listService.lists.filter { !($0.isVirtual ?? false) }) { list in
                ListSyncRow(list: list, onTap: {
                    if remindersService.isListLinked(list.id) {
                        // Show unlink confirmation or sync options
                    } else {
                        selectedListForLink = list
                        showingLinkSheet = true
                    }
                })
            }
        } header: {
            Text(NSLocalizedString("reminders.your_lists", comment: ""))
        } footer: {
            Text(NSLocalizedString("reminders.your_lists_footer", comment: ""))
                .font(Theme.Typography.caption2())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
        }
    }

    // MARK: - Import from Reminders Section

    private var importFromRemindersSection: some View {
        let unlinkedCalendars = remindersService.getUnlinkedRemindersCalendars()

        return Group {
            if !unlinkedCalendars.isEmpty {
                Section {
                    ForEach(unlinkedCalendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            selectedCalendarForImport = calendar
                            showingImportSheet = true
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor ?? CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(Theme.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(NSLocalizedString("reminders.import_from_reminders", comment: ""))
                } footer: {
                    Text(NSLocalizedString("reminders.import_footer", comment: ""))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func requestAccess() {
        _Concurrency.Task {
            await remindersService.requestAccess()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func syncAll() {
        _Concurrency.Task {
            try? await remindersService.syncAllLinkedLists()
        }
    }
}

// MARK: - List Sync Row

struct ListSyncRow: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var remindersService = AppleRemindersService.shared

    let list: TaskList
    let onTap: () -> Void

    var isLinked: Bool {
        remindersService.isListLinked(list.id)
    }

    var link: ReminderListLink? {
        remindersService.linkedLists[list.id]
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Circle()
                    .fill(Color(hex: list.displayColor) ?? Color.blue)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    if let link = link {
                        Text(link.syncDirection.displayName)
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                }

                Spacer()

                if isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "link")
                        .foregroundColor(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isLinked {
                Button(role: .destructive) {
                    remindersService.unlinkList(list.id)
                } label: {
                    Label(NSLocalizedString("reminders.unlink", comment: ""), systemImage: "link.badge.minus")
                }

                Button {
                    _Concurrency.Task {
                        try? await remindersService.syncList(list.id)
                    }
                } label: {
                    Label(NSLocalizedString("sync", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Theme.accent)
            }
        }
    }
}

// MARK: - Link List Sheet

struct LinkListSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var remindersService = AppleRemindersService.shared

    let list: TaskList
    let onDismiss: () -> Void

    @State private var selectedDirection: SyncDirection = .export
    @State private var selectedCalendar: EKCalendar?
    @State private var includeCompletedTasks: Bool = true
    @State private var isLinking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.themedBackgroundPrimary()
                    .ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Circle()
                                .fill(Color(hex: list.displayColor) ?? Color.blue)
                                .frame(width: 16, height: 16)
                            Text(list.name)
                                .font(Theme.Typography.headline())
                        }
                    } header: {
                        Text(NSLocalizedString("reminders.astrid_list", comment: ""))
                    }

                    Section {
                        ForEach(SyncDirection.allCases, id: \.self) { direction in
                            Button {
                                selectedDirection = direction
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(direction.displayName)
                                            .font(Theme.Typography.body())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Text(direction.description)
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    }
                                    Spacer()
                                    if selectedDirection == direction {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(NSLocalizedString("reminders.sync_direction", comment: ""))
                    }

                    if selectedDirection == .import_ || selectedDirection == .bidirectional {
                        Section {
                            let calendars = remindersService.getRemindersCalendars()
                            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                Button {
                                    selectedCalendar = calendar
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color(cgColor: calendar.cgColor))
                                            .frame(width: 12, height: 12)
                                        Text(calendar.title)
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                        Spacer()
                                        if selectedCalendar?.calendarIdentifier == calendar.calendarIdentifier {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                selectedCalendar = nil
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(Theme.accent)
                                    Text(NSLocalizedString("reminders.create_new_list", comment: ""))
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if selectedCalendar == nil && selectedDirection != .export {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } header: {
                            Text(NSLocalizedString("reminders.link_to_reminders_list", comment: ""))
                        } footer: {
                            Text(String(format: NSLocalizedString("reminders.link_footer", comment: ""), list.name))
                                .font(Theme.Typography.caption2())
                        }
                    }

                    Section {
                        Toggle(isOn: $includeCompletedTasks) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("reminders.include_completed", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(NSLocalizedString("reminders.include_completed_desc", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                    } header: {
                        Text(NSLocalizedString("reminders.options", comment: ""))
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(Theme.Typography.caption1())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(NSLocalizedString("reminders.link_list", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("reminders.link", comment: "")) {
                        linkList()
                    }
                    .disabled(isLinking)
                }
            }
        }
    }

    private func linkList() {
        isLinking = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                try await remindersService.linkList(
                    list.id,
                    toCalendar: selectedCalendar,
                    direction: selectedDirection,
                    includeCompletedTasks: includeCompletedTasks
                )
                await MainActor.run {
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLinking = false
                }
            }
        }
    }
}

// MARK: - Import Calendar Sheet

struct ImportCalendarSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var remindersService = AppleRemindersService.shared
    @StateObject private var listService = ListService.shared

    let calendar: EKCalendar
    let onDismiss: () -> Void

    @State private var selectedList: TaskList?
    @State private var createNewList = true
    @State private var includeCompletedTasks: Bool = true
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.themedBackgroundPrimary()
                    .ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 16, height: 16)
                            Text(calendar.title)
                                .font(Theme.Typography.headline())
                        }
                    } header: {
                        Text(NSLocalizedString("reminders.reminders_list", comment: ""))
                    }

                    Section {
                        Button {
                            createNewList = true
                            selectedList = nil
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Theme.accent)
                                Text(NSLocalizedString("reminders.create_new_astrid_list", comment: ""))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Spacer()
                                if createNewList {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(listService.lists.filter { !($0.isVirtual ?? false) && !remindersService.isListLinked($0.id) }) { list in
                            Button {
                                createNewList = false
                                selectedList = list
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: list.displayColor) ?? Color.blue)
                                        .frame(width: 12, height: 12)
                                    Text(list.name)
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if !createNewList && selectedList?.id == list.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(NSLocalizedString("reminders.import_into", comment: ""))
                    } footer: {
                        Text(String(format: NSLocalizedString("reminders.import_into_footer", comment: ""), calendar.title))
                            .font(Theme.Typography.caption2())
                    }

                    Section {
                        Toggle(isOn: $includeCompletedTasks) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("reminders.include_completed", comment: ""))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                Text(NSLocalizedString("reminders.import_completed_desc", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        .tint(Theme.accent)
                    } header: {
                        Text(NSLocalizedString("reminders.options", comment: ""))
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(Theme.Typography.caption1())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(NSLocalizedString("reminders.import_reminders", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("reminders.import", comment: "")) {
                        importCalendar()
                    }
                    .disabled(isImporting)
                }
            }
        }
    }

    private func importCalendar() {
        isImporting = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                if createNewList {
                    // Create new Astrid list first
                    let newList = try await listService.createList(name: calendar.title, privacy: "PRIVATE")

                    // Then link it
                    try await remindersService.linkList(
                        newList.id,
                        toCalendar: calendar,
                        direction: .import_,
                        includeCompletedTasks: includeCompletedTasks
                    )
                } else if let existingList = selectedList {
                    try await remindersService.linkList(
                        existingList.id,
                        toCalendar: calendar,
                        direction: .import_,
                        includeCompletedTasks: includeCompletedTasks
                    )
                }

                await MainActor.run {
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

#Preview {
    AppleRemindersSettingsView()
}
