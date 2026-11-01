import SwiftUI
import Combine

/// Manages presenting lists programmatically from anywhere in the app
@MainActor
class ListPresenter: ObservableObject {
    static let shared = ListPresenter()

    /// The list ID to navigate to
    @Published var listIdToShow: String?

    /// Whether we're showing a public/featured list (vs user's own list)
    @Published var isShowingFeaturedList: Bool = false

    /// The featured list data (for public lists)
    @Published var featuredListToShow: TaskList?

    private init() {
        AppLog.debug("🎯 [ListPresenter] Initializing...")
    }

    /// Navigate to a list by ID — a deep link's. One that is not yours opens as a public list,
    /// fetched by id: the sync cache does not hold its tasks (AITD-573).
    func showList(listId: String, yourLists: [TaskList]? = nil) {
        AppLog.debug("🔄 [ListPresenter] Navigating to list: \(listId)")
        self.isShowingFeaturedList = TaskListRows.browsesFromServer(
            listId: listId, yourLists: yourLists ?? ListService.shared.lists)
        self.featuredListToShow = nil
        self.listIdToShow = listId
    }

    /// Navigate to a public list by ID and name (creates minimal TaskList for display)
    func showPublicList(listId: String, name: String) {
        AppLog.debug("🔄 [ListPresenter] Navigating to public list: \(name) (\(listId))")
        // Create a minimal TaskList object for display purposes
        let publicList = TaskList(
            id: listId,
            name: name,
            privacy: .PUBLIC
        )
        self.featuredListToShow = publicList
        self.isShowingFeaturedList = true
        self.listIdToShow = listId
    }

    /// Clear the navigation request (called after navigation completes)
    func clearNavigation() {
        listIdToShow = nil
    }
}
