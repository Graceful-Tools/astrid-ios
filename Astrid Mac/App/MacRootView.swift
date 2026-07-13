//  MacRootView.swift
//  Astrid for Mac — three-column shell skeleton (M1)
//
//  NavigationSplitView driven by the SAME navigation model the iOS app uses. This file owns
//  layout only; the sidebar rows, the task list, and the detail pane are the existing shared
//  feature views. No task/list/sync logic here — route everything through the shared services.

#if os(macOS)
import SwiftUI

struct MacRootView: View {
    // TODO(M1): bind to the shared selection/navigation model (same source as iOS),
    // not Mac-only @State. These are placeholders to make the skeleton compile.
    @State private var selectedListID: String?
    @State private var selectedTaskID: String?

    var body: some View {
        NavigationSplitView {
            // SIDEBAR — lists / favorites / My Tasks / filters / sync sources.
            List(selection: $selectedListID) {
                Section("Lists") {
                    Text("TODO(M1): reuse existing sidebar rows / list view models")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            // CONTENT — task list for the selection (Table for power view, List for compact — M2).
            Text("TODO(M1): reuse the existing task list view for \(selectedListID ?? "—")")
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            // DETAIL — reuse the existing task-detail feature view.
            if let selectedTaskID {
                Text("TODO(M1): reuse TaskDetail feature view for \(selectedTaskID)")
            } else {
                Text("Select a task").foregroundStyle(.secondary)
            }
        }
    }
}
#endif
