import SwiftUI

/// Handles taps on astrid:// reference links (@mentions, #lists, !tasks)
/// by pushing the destination onto the current NavigationStack.
/// This gives proper back-navigation instead of replacing the main view.
struct ReferenceNavigationModifier: ViewModifier {
    @State private var navigateToTask: Task?
    @State private var navigateToListId: String?
    @State private var navigateToUserId: String?
    @StateObject private var taskService = TaskService.shared

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "astrid", let host = url.host else {
                    return .systemAction
                }
                let id = url.lastPathComponent
                guard !id.isEmpty && id != host else { return .handled }

                // Dismiss keyboard before navigating
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                switch host {
                case "tasks":
                    // Fetch task and push via navigationDestination
                    _Concurrency.Task {
                        if let task = taskService.tasks.first(where: { $0.id == id }) {
                            await MainActor.run { navigateToTask = task }
                        } else if let task = try? await taskService.fetchTask(id: id) {
                            await MainActor.run { navigateToTask = task }
                        }
                    }
                case "lists":
                    navigateToListId = id
                case "users":
                    navigateToUserId = id
                default:
                    return .systemAction
                }
                return .handled
            })
            .navigationDestination(item: $navigateToTask) { task in
                TaskDetailViewNew(task: task)
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToListId != nil },
                set: { if !$0 { navigateToListId = nil } }
            )) {
                if let listId = navigateToListId {
                    TaskListView(
                        selectedListId: .constant(listId),
                        isViewingFromFeatured: .constant(false)
                    )
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigateToUserId != nil },
                set: { if !$0 { navigateToUserId = nil } }
            )) {
                if let userId = navigateToUserId {
                    UserProfileView(userId: userId)
                }
            }
    }
}

extension View {
    /// Adds in-stack navigation for @mention, #list, and !task reference links.
    /// Pushes destinations onto the current NavigationStack so back-navigation works.
    func withReferenceNavigation() -> some View {
        modifier(ReferenceNavigationModifier())
    }
}
