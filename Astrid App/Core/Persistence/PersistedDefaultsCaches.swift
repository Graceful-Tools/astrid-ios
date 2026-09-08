//  PersistedDefaultsCaches.swift
//  Small caches that live in memory and use UserDefaults only for persistence (task AITD-342).
//
//  Both of these used to BE their UserDefaults key: a computed property whose getter
//  deserialised the whole value out of the defaults plist and whose setter serialised the whole
//  thing back. The sync services were careful with that — they hoist the dictionary out of their
//  loops, so a pass costs one read and one write rather than one per link — but
//  `TaskService.updateTask` was not able to be: it asks one membership question per update, and
//  paying for a 500-element array's deserialisation and a `Set` construction to answer it was on
//  the hottest write path in the app (every edit, every completion, every board move).
//
//  Loading once and writing through removes the question of which call site is hot enough to
//  matter, which is the real win: nobody has to be careful about it again.
//
//  Both take a `UserDefaults` so tests can drive them against a scratch suite and count the
//  round-trips.
import Foundation

/// A `[String: String]` map persisted under one defaults key.
final class PersistedStringDictionary {
    private let defaults: UserDefaults
    private let key: String
    private var storage: [String: String]

    init(key: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = key
        self.storage = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    var all: [String: String] { storage }

    subscript(id: String) -> String? {
        get { storage[id] }
        set {
            if storage[id] == newValue { return }   // no write for a no-op
            storage[id] = newValue
            flush()
        }
    }

    /// Apply several changes under a single persist — what the sync passes want.
    func merge(_ updates: [String: String]) {
        guard !updates.isEmpty else { return }
        var changed = false
        for (id, value) in updates where storage[id] != value {
            storage[id] = value
            changed = true
        }
        if changed { flush() }
    }

    func removeAll() {
        guard !storage.isEmpty else { return }
        storage = [:]
        flush()
    }

    private func flush() { defaults.set(storage, forKey: key) }
}

/// An ordered, capped ledger of ids, with O(1) membership.
///
/// Ordered rather than a `Set` on purpose, and this is load-bearing: at the cap, eviction must
/// drop the OLDEST ids. A `Set` round-trip evicts arbitrarily and can drop the id just recorded,
/// which is the deleted-task-reappears bug the ledger exists to prevent.
final class PersistedIdRing {
    private let defaults: UserDefaults
    private let key: String
    private let cap: Int
    private var order: [String]
    private var members: Set<String>

    init(key: String, cap: Int, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = key
        self.cap = cap
        self.order = defaults.stringArray(forKey: key) ?? []
        self.members = Set(order)
    }

    /// Membership, with no plist round-trip — the reason this type exists.
    func contains(_ id: String) -> Bool { members.contains(id) }

    var ids: Set<String> { members }

    func record(_ ids: [String]) {
        let updated = PersistedIdRing.appending(order, ids, cap: cap)
        guard updated != order else { return }
        order = updated
        members = Set(updated)
        flush()
    }

    func remove(_ id: String) {
        guard members.contains(id) else { return }
        order.removeAll { $0 == id }
        members.remove(id)
        flush()
    }

    func removeAll() {
        guard !order.isEmpty else { return }
        order = []
        members = []
        defaults.removeObject(forKey: key)
    }

    /// Pure ledger append: idempotent, ordered, oldest-first eviction at the cap.
    ///
    /// Unchanged from `TaskService.appendingDeletedIds`, which it replaces — an id already
    /// present keeps its original position rather than being moved to the end, so re-recording
    /// something does not extend its life at the expense of an older entry.
    static func appending(_ existing: [String], _ ids: [String], cap: Int) -> [String] {
        var result = existing
        for id in ids where !result.contains(id) { result.append(id) }
        if result.count > cap { result.removeFirst(result.count - cap) }
        return result
    }

    private func flush() { defaults.set(order, forKey: key) }
}
