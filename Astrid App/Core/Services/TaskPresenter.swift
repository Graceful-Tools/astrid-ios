import SwiftUI
import Combine

/// Manages presenting task detail views programmatically from anywhere in the app
@MainActor
class TaskPresenter: ObservableObject {
    static let shared = TaskPresenter()

    @Published var taskToShow: Task?
    @Published var isShowingTask = false

    /// iPad: the split container registers this to show tasks in its side
    /// detail panel. When set, presenter-driven opens (subtask rows, parent
    /// links, deep links) route there instead of pushing onto whatever
    /// NavigationStack hosts `withTaskPresentation()` — on iPad that stack is
    /// the LIST column, which is the wrong place for a task detail.
    var panelHandler: ((Task) -> Void)?

    private let taskService = TaskService.shared

    private init() {
        print("🎯 [TaskPresenter] Initializing...")
    }

    /// Show task detail view for a task ID
    func showTask(taskId: String) {
        print("🔄 [TaskPresenter] Fetching task \(taskId)...")
        _Concurrency.Task {
            do {
                let task = try await taskService.fetchTask(id: taskId)
                print("✅ [TaskPresenter] Task fetched: \(task.title)")
                await MainActor.run {
                    self.showTask(task)
                }
            } catch {
                print("❌ [TaskPresenter] Failed to fetch task for navigation: \(error)")
            }
        }
    }

    /// Show task detail view with an existing task object
    func showTask(_ task: Task) {
        print("🎯 [TaskPresenter] Showing task: \(task.title)")
        if let panelHandler {
            panelHandler(task)
            return
        }
        self.taskToShow = task
        self.isShowingTask = true
    }

    /// Dismiss the task detail view
    func dismiss() {
        isShowingTask = false
        taskToShow = nil
    }
}

/// View modifier to add task presentation capability to any view
struct TaskPresentationModifier: ViewModifier {
    @StateObject private var presenter = TaskPresenter.shared

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $presenter.isShowingTask) {
                if let task = presenter.taskToShow {
                    // .id ties the pushed view's identity to the task: presenting a
                    // second task while one is already shown (parent-link taps in
                    // nested subtasks) swaps the content instead of silently
                    // keeping the old @State task.
                    TaskDetailViewNew(task: task)
                        .id(task.id)
                }
            }
    }
}

extension View {
    /// Enable task presentation for this view
    func withTaskPresentation() -> some View {
        modifier(TaskPresentationModifier())
    }
}
