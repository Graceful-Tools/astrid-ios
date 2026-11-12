import AstridCore
import Foundation
import Contacts
import Combine

/**
 * ContactsService
 *
 * Manages device contacts integration for Astrid:
 * - Requests and checks Contacts permission
 * - Fetches contacts with email addresses from device
 * - Syncs contacts to Astrid server for collaborator suggestions
 * - Searches contacts for autocomplete when adding list members
 * - Gets recommended collaborators based on mutual address book presence
 *
 * The synced count and the upload go through astrid-core (AITD-620), which also does the
 * batching; autocomplete and recommendations have no core command yet and stay on the client.
 */
class ContactsService: ObservableObject {
    static let shared = ContactsService()

    private let store = CNContactStore()
    private let apiClient = AstridAPIClient.shared
    private var core: CoreSession { AppCore.shared.session }

    // UserDefaults key for persisting last sync date
    private let lastSyncDateKey = "ContactsService.lastSyncDate"

    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var isSyncing = false
    @Published var lastSyncDate: Date? {
        didSet {
            // Persist to UserDefaults when changed
            if let date = lastSyncDate {
                UserDefaults.standard.set(date, forKey: lastSyncDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSyncDateKey)
            }
        }
    }
    @Published var contactCount: Int = 0

    private init() {
        // Load persisted last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date

        checkAuthorizationStatus()

        // If authorized (or limited on iOS 18+), fetch current contact count from server
        if hasPermission {
            _Concurrency.Task {
                await fetchContactStatus()
            }
        }
    }

    /// Fetch current contact status from server (count of synced contacts)
    func fetchContactStatus() async {
        do {
            let status = try await core.run(ContactCommands.status(), as: ContactStatus.self)
            await MainActor.run {
                contactCount = status.total
            }
        } catch {
            // Don't reset contactCount on error - keep any cached value
        }
    }

    // MARK: - Authorization

    /// Check current Contacts authorization status
    func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Request access to Contacts
    /// - Returns: True if access was granted
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            await MainActor.run {
                checkAuthorizationStatus()
            }
            return granted
        } catch {
            AppLog.debug("❌ [ContactsService] Error requesting access: \(error)")
            return false
        }
    }

    /// Check if we have Contacts permission (includes .limited for iOS 18+)
    var hasPermission: Bool {
        #if os(iOS)
        return authorizationStatus == .authorized || authorizationStatus == .limited
        #else
        return authorizationStatus == .authorized
        #endif
    }

    // MARK: - Fetch Device Contacts

    /// Enumerate contacts from a CNContactStore — safe to call off main thread
    private nonisolated static func enumerateContacts(store: CNContactStore) throws -> [DeviceContact] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        var contacts: [DeviceContact] = []
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)

        try store.enumerateContacts(with: request) { cnContact, _ in
            guard !cnContact.emailAddresses.isEmpty else { return }

            let name = [cnContact.givenName, cnContact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            for email in cnContact.emailAddresses {
                let emailString = email.value as String
                let phoneNumber = cnContact.phoneNumbers.first?.value.stringValue

                contacts.append(DeviceContact(
                    email: emailString.lowercased(),
                    name: name.isEmpty ? nil : name,
                    phoneNumber: phoneNumber
                ))
            }
        }

        AppLog.debug("📇 [ContactsService] Fetched \(contacts.count) contacts with emails")
        return contacts
    }

    // MARK: - Sync Contacts to Server

    /// Sync device contacts to the Astrid server
    /// - Returns: The last batch's stats; `total` is the account's whole count
    @discardableResult
    func syncContacts() async throws -> ContactSyncStats {
        guard hasPermission else {
            throw ContactsError.notAuthorized
        }

        await MainActor.run {
            isSyncing = true
        }

        defer {
            _Concurrency.Task { @MainActor in
                self.isSyncing = false
            }
        }

        // Fetch contacts from device (off main thread — CNContactStore enumeration is expensive)
        let contactStore = store
        let deviceContacts = try await _Concurrency.Task.detached {
            try Self.enumerateContacts(store: contactStore)
        }.value

        // One command for the whole book: the core uploads it in batches, the first replacing
        // what the server had, and an empty book still clears the server's copy.
        let result = try await core.run(ContactCommands.upload(deviceContacts), as: ContactSyncStats.self)

        await MainActor.run {
            lastSyncDate = Date()
            contactCount = result.total
        }

        return result
    }

    // MARK: - Search Contacts

    /// Search contacts for autocomplete when adding list members
    /// - Parameters:
    ///   - query: Search query (min 2 characters)
    ///   - excludeListId: Optional list ID to exclude existing members
    /// - Returns: Array of matching contacts
    func searchContacts(query: String, excludeListId: String? = nil) async throws -> [ContactSearchResult] {
        return try await apiClient.searchContacts(query: query, excludeListId: excludeListId)
    }

    // MARK: - Recommended Collaborators

    /// Get recommended collaborators based on mutual address book presence
    /// - Parameter excludeListId: Optional list ID to exclude existing members
    /// - Returns: Array of recommended collaborators
    func getRecommendedCollaborators(excludeListId: String? = nil) async throws -> [RecommendedCollaborator] {
        return try await apiClient.getRecommendedCollaborators(excludeListId: excludeListId)
    }
}

// MARK: - Models

/// Contact from the device address book
nonisolated struct DeviceContact: Codable, Sendable {
    let email: String
    let name: String?
    let phoneNumber: String?
}

/// The server's stats for a contact sync, as the core passes them back from the last batch.
/// Only `total` is read; the rest are optional so a server that trims them still syncs.
nonisolated struct ContactSyncStats: Codable, Sendable {
    let received: Int?
    let valid: Int?
    let created: Int?
    let updated: Int?
    let total: Int
    let errors: Int?
}

/// Contact search result for autocomplete
struct ContactSearchResult: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let phoneNumber: String?
    let isAstridUser: Bool
    let astridUserName: String?
    let astridUserImage: String?

    /// Display name (prefer Astrid name, then contact name, then email)
    var displayName: String {
        astridUserName ?? name ?? email
    }
}

/// Recommended collaborator based on mutual contacts
struct RecommendedCollaborator: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
    let image: String?
    let contactName: String?
    let isMutual: Bool

    /// Display name (prefer user name, then contact name, then email)
    var displayName: String {
        name ?? contactName ?? email
    }
}

// MARK: - Errors

enum ContactsError: LocalizedError {
    case notAuthorized
    case fetchFailed(Error)
    case syncFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Contacts access not authorized. Please enable in Settings."
        case .fetchFailed(let error):
            return "Failed to fetch contacts: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Failed to sync contacts: \(error.localizedDescription)"
        }
    }
}
