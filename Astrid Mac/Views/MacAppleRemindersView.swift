//  MacAppleRemindersView.swift
//  Astrid for Mac — Apple Reminders (EventKit) connect + list linking (Task 33d648f2).
//
//  macOS has EventKit + the Reminders app, so this is a first-class desktop integration — not
//  iOS-only. Mirrors iOS AppleRemindersSettingsView over the SAME shared AppleRemindersService:
//  request access, link Astrid lists ↔ Reminders calendars, pick a sync direction, and sync.

#if os(macOS)
import SwiftUI
import EventKit

/// Pure status mapping (testable without EventKit state).
enum MacRemindersStatus {
    static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    static func label(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Not connected"
        case .denied, .restricted: return "Denied — enable in System Settings › Privacy"
        default: return isGranted(status) ? "Connected" : "Limited access"
        }
    }
}

struct MacAppleRemindersView: View {
    @StateObject private var apple = AppleRemindersService.shared
    @StateObject private var listService = ListService.shared
    @Environment(\.dismiss) private var dismiss

    private var realLists: [TaskList] { listService.lists.filter { $0.isVirtual != true } }
    private var granted: Bool { MacRemindersStatus.isGranted(apple.authorizationStatus) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apple Reminders").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.return)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)

            Form {
                Section("Access") {
                    HStack {
                        Circle().fill(granted ? Theme.success : Theme.textMuted).frame(width: 8, height: 8)
                        Text(MacRemindersStatus.label(apple.authorizationStatus)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if !granted {
                            Button("Enable Access") { _Concurrency.Task { _ = await apple.requestAccess() } }
                        }
                    }
                }

                if granted {
                    Section("Linked Lists") {
                        ForEach(realLists) { list in linkRow(list) }
                        if realLists.isEmpty { Text("No lists to link").foregroundStyle(Theme.textMuted) }
                    }
                    Section {
                        Button {
                            _Concurrency.Task { try? await apple.syncAllLinkedLists() }
                        } label: {
                            HStack { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                if apple.isSyncing { Spacer(); ProgressView().controlSize(.small) } }
                        }
                        .disabled(apple.isSyncing || apple.linkedListCount == 0)
                        if let d = apple.lastSyncDate { LabeledContent("Last sync") { Text(d, style: .relative) } }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 460)
        .task { apple.checkAuthorizationStatus() }
    }

    @ViewBuilder private func linkRow(_ list: TaskList) -> some View {
        HStack {
            Text(list.name).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let link = apple.linkedLists[list.id] {
                Menu(link.reminderCalendarTitle) {
                    Picker("Direction", selection: Binding(
                        get: { link.syncDirection },
                        set: { apple.updateLinkSettings(list.id, syncDirection: $0) }
                    )) {
                        ForEach(SyncDirection.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Include completed", isOn: Binding(
                        get: { link.includeCompletedTasks },
                        set: { apple.updateLinkSettings(list.id, includeCompletedTasks: $0) }
                    ))
                    Divider()
                    Button("Unlink", role: .destructive) { apple.unlinkList(list.id) }
                }
                .fixedSize()
            } else {
                Menu("Link…") {
                    ForEach(apple.getRemindersCalendars(), id: \.calendarIdentifier) { cal in
                        Button(cal.title) { link(list, to: cal) }
                    }
                    Divider()
                    Button("Create Reminders List") { createAndLink(list) }
                }
                .fixedSize()
            }
        }
    }

    private func link(_ list: TaskList, to calendar: EKCalendar) {
        MacActions.perform("Link Reminders") {
            try await apple.linkList(list.id, toCalendar: calendar, direction: .bidirectional)
        }
    }

    private func createAndLink(_ list: TaskList) {
        MacActions.perform("Create Reminders list") {
            let cal = try apple.getOrCreateRemindersCalendar(for: list)
            try await apple.linkList(list.id, toCalendar: cal, direction: .bidirectional)
        }
    }
}
#endif
