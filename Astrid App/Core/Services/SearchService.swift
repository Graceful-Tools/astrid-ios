import Foundation
import CoreData
import Combine

/// Provides hybrid search capability - uses server search when online, CoreData when offline
@MainActor
class SearchService: ObservableObject {
    static let shared = SearchService()

    @Published var searchResults: [Task] = []
    @Published var isSearching = false
    @Published var isOfflineSearch = false  // True if results came from offline search
    @Published var errorMessage: String?

    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared

    /// Minimum characters before search triggers
    static let minimumQueryLength = 2

    /// Debounce delay for search input
    static let debounceDelay: TimeInterval = 0.3

    private var searchTask: _Concurrency.Task<Void, Never>?

    private init() {}

    // MARK: - Search API

    /// Perform a hybrid search - online if connected, offline otherwise
    func search(query: String, listId: String? = nil, includeCompleted: Bool = true) {
        // Cancel previous search
        searchTask?.cancel()

        // Clear results for empty query
        guard query.count >= Self.minimumQueryLength else {
            searchResults = []
            isSearching = false
            isOfflineSearch = false
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = _Concurrency.Task {
            // Debounce
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(Self.debounceDelay * 1_000_000_000))

            guard !_Concurrency.Task.isCancelled else { return }

            if networkMonitor.isConnected {
                // Online search via cached tasks (API doesn't have search endpoint)
                await searchOnline(query: query, listId: listId, includeCompleted: includeCompleted)
            } else {
                // Offline search via CoreData
                await searchOffline(query: query, listId: listId, includeCompleted: includeCompleted)
            }
        }
    }

    /// Clear search results
    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        isSearching = false
        isOfflineSearch = false
        errorMessage = nil
    }

    // MARK: - Private Implementation

    private func searchOnline(query: String, listId: String?, includeCompleted: Bool) async {
        AppLog.debug("🔍 [SearchService] Online search: \"\(query)\"")

        // Use cached tasks from TaskService
        let allTasks = TaskService.shared.tasks
        let lowercaseQuery = query.lowercased()

        let results = allTasks.filter { task in
            let matchesQuery = task.title.lowercased().contains(lowercaseQuery) ||
                              task.description.lowercased().contains(lowercaseQuery)

            let matchesList = listId == nil || (task.listIds?.contains(listId!) ?? false)
            let matchesCompleted = includeCompleted || !task.completed

            return matchesQuery && matchesList && matchesCompleted
        }

        guard !_Concurrency.Task.isCancelled else { return }

        searchResults = results
        isOfflineSearch = false
        isSearching = false

        AppLog.debug("✅ [SearchService] Online search found \(results.count) results")
    }

    private func searchOffline(query: String, listId: String?, includeCompleted: Bool) async {
        AppLog.debug("🔍 [SearchService] Offline search: \"\(query)\"")

        do {
            let cdTasks = try await performCoreDataSearch(
                query: query,
                listId: listId,
                includeCompleted: includeCompleted
            )

            guard !_Concurrency.Task.isCancelled else { return }

            // Convert to domain models
            let tasks = cdTasks.map { $0.toDomainModel() }

            searchResults = tasks
            isOfflineSearch = true
            isSearching = false

            AppLog.debug("✅ [SearchService] Offline search found \(tasks.count) results")
        } catch {
            AppLog.debug("❌ [SearchService] Offline search failed: \(error)")
            errorMessage = "Search failed: \(error.localizedDescription)"
            searchResults = []
            isSearching = false
        }
    }

    private func performCoreDataSearch(
        query: String,
        listId: String?,
        includeCompleted: Bool
    ) async throws -> [CDTask] {
        return try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let results = try CDTask.search(
                        query: query,
                        listId: listId,
                        includeCompleted: includeCompleted,
                        context: context
                    )
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Search Index Management

    /// Rebuild search index for all tasks (run after migration or data repair)
    func rebuildSearchIndex() async {
        AppLog.debug("🔧 [SearchService] Rebuilding search index...")

        do {
            try await coreDataManager.saveInBackground { context in
                try CDTask.rebuildSearchIndex(context: context)
            }
            AppLog.debug("✅ [SearchService] Search index rebuilt")
        } catch {
            AppLog.debug("❌ [SearchService] Failed to rebuild search index: \(error)")
        }
    }
}

// MARK: - Search Result Highlighting

extension SearchService {
    /// Returns ranges to highlight in the given text for the query
    static func highlightRanges(in text: String, for query: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()

        var searchStart = lowercaseText.startIndex
        while let range = lowercaseText.range(of: lowercaseQuery, range: searchStart..<lowercaseText.endIndex) {
            // Convert to original text range
            let originalRange = text.index(text.startIndex, offsetBy: lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound))
            ranges.append(originalRange)
            searchStart = range.upperBound
        }

        return ranges
    }
}
