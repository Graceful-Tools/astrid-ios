import CoreData
import Foundation

class CoreDataManager {
    static let shared = CoreDataManager()

    // Track when persistent store is ready
    private var isStoreLoaded = false
    private var storeLoadContinuations: [CheckedContinuation<Void, Never>] = []

    private init() {
        // Register custom value transformers for secure archiving
        StringArrayTransformer.register()
    }

    // MARK: - Core Data Stack

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AstridApp")

        // Enable automatic lightweight migration
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true

        // UI tests share the real app container (same bundle id): use a throwaway store so test
        // data (lists/tasks) can never land in — or later sync out of — the user's real store.
        if UITestSession.isUITesting {
            description?.url = URL(fileURLWithPath: "/dev/null")
            print("🧪 [CoreData] -uiTesting: using ephemeral store")
        }

        print("🔄 [CoreData] Loading persistent store...")
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                // Don't crash - CoreData model may not be created yet
                print("⚠️ Core Data model not available: \(error)")
                print("ℹ️  App will work without CoreData persistence (memory only)")
                print("ℹ️  To enable: Create AstridApp.xcdatamodeld in Xcode")

                // Mark as loaded (even if failed) to unblock waiting tasks
                self?.markStoreAsLoaded()
                return
            }

            print("✅ Core Data loaded from: \(description.url?.absoluteString ?? "unknown")")
            self?.markStoreAsLoaded()
        }

        // Auto-merge changes from parent
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Store Loading Management

    /// Wait for the persistent store to finish loading
    func waitForStoreLoad() async {
        // Trigger lazy loading if not already started
        _ = persistentContainer

        // If already loaded, return immediately
        guard !isStoreLoaded else {
            print("✅ [CoreData] Store already loaded")
            return
        }

        print("⏳ [CoreData] Waiting for store to load...")

        // Wait for store to load
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if isStoreLoaded {
                // Double-check after acquiring lock
                continuation.resume()
            } else {
                storeLoadContinuations.append(continuation)
            }
        }

        print("✅ [CoreData] Store load wait completed")
    }

    private func markStoreAsLoaded() {
        print("🎉 [CoreData] Marking store as loaded, resuming \(storeLoadContinuations.count) waiting tasks")
        isStoreLoaded = true

        // Resume all waiting continuations
        for continuation in storeLoadContinuations {
            continuation.resume()
        }
        storeLoadContinuations.removeAll()
    }
    
    // MARK: - Save
    
    func save(context: NSManagedObjectContext? = nil) throws {
        let context = context ?? viewContext
        
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            print("❌ Failed to save Core Data context: \(error)")
            throw error
        }
    }
    
    func saveInBackground(_ block: @escaping (NSManagedObjectContext) throws -> Void) async throws {
        let context = newBackgroundContext()
        
        try await context.perform {
            try block(context)
            try self.save(context: context)
        }
    }
    
    // MARK: - Fetch
    
    func fetch<T: NSManagedObject>(_ request: NSFetchRequest<T>, context: NSManagedObjectContext? = nil) throws -> [T] {
        let context = context ?? viewContext
        return try context.fetch(request)
    }
    
    // MARK: - Delete
    
    func delete(_ object: NSManagedObject, context: NSManagedObjectContext? = nil) throws {
        let context = context ?? viewContext
        context.delete(object)
        try save(context: context)
    }
    
    // MARK: - Clear All Data

    func clearAll() throws {
        let entities = persistentContainer.managedObjectModel.entities

        for entity in entities {
            guard let entityName = entity.name else { continue }

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            // Return the deleted object IDs so we can merge changes
            deleteRequest.resultType = .resultTypeObjectIDs

            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult

            // CRITICAL: NSBatchDeleteRequest operates directly on the persistent store
            // and does NOT update the in-memory context. We must merge the deletions
            // into all contexts to prevent stale data from showing up.
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            }
        }

        // Reset the context to ensure no stale objects remain in memory
        viewContext.reset()

        print("✅ [CoreDataManager] All data cleared and context reset")
    }
}
