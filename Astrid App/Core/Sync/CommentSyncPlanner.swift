import Foundation

/// Pure planning for two-way comment sync on a linked task (GitHub issue
/// comments ↔ Astrid comments). Developed red-green; the spec lives in
/// `CommentSyncPlannerTests`.
///
/// The mapping (remote comment id → astrid comment id) is the loop breaker:
/// a pulled comment is recorded so it never pulls twice, and its Astrid twin
/// (a mapping VALUE) never pushes back. It persists in the task link's
/// metadata under `commentMap` via the flat codec below.
enum CommentSyncPlanner {
    struct RemoteComment: Equatable {
        let id: String
        let body: String
        let author: String
    }

    struct LocalComment: Equatable {
        let id: String
        let content: String
        let isSystem: Bool
        var attachmentNames: [String] = []
    }

    /// A synced comment pair with the direction that created it: pushed
    /// ('p', Astrid canonical) or pulled ('l', GitHub canonical). Direction
    /// decides which side wins when a mapped comment is EDITED.
    struct MapEntry: Equatable {
        let remoteId: String
        let localId: String
        let pushed: Bool
    }

    static func plan(
        remote: [RemoteComment],
        local: [LocalComment],
        mapping: [String: String]
    ) -> (pullCreates: [RemoteComment], pushCreates: [LocalComment]) {
        let mirroredLocalIds = Set(mapping.values)
        let pullCreates = remote.filter { mapping[$0.id] == nil }
        let pushCreates = local.filter {
            !$0.isSystem
                && !$0.id.hasPrefix("temp_")   // offline comment — wait for reconcile
                && !mirroredLocalIds.contains($0.id)
                && isPushable($0)              // attachment-only OK; truly empty isn't
        }
        return (pullCreates, pushCreates)
    }

    /// Edits on mapped pairs: converge the non-canonical side.
    static func editPlan(
        remote: [RemoteComment],
        local: [LocalComment],
        entries: [MapEntry]
    ) -> (pullUpdates: [(localId: String, content: String)], pushUpdates: [(remoteId: String, body: String)]) {
        let remoteById = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var pullUpdates: [(localId: String, content: String)] = []
        var pushUpdates: [(remoteId: String, body: String)] = []
        for entry in entries {
            guard let r = remoteById[entry.remoteId], let l = localById[entry.localId] else { continue }
            if entry.pushed {
                // Astrid canonical: converge GitHub to the local content.
                let expected = pushBody(content: l.content, attachmentNames: l.attachmentNames)
                if r.body != expected, !expected.isEmpty {
                    pushUpdates.append((entry.remoteId, expected))
                }
            } else {
                // GitHub canonical: converge the local twin to the remote body.
                let expected = pulledContent(author: r.author, body: r.body)
                if l.content != expected {
                    pullUpdates.append((entry.localId, expected))
                }
            }
        }
        return (pullUpdates, pushUpdates)
    }

    /// Deletions on mapped pairs: the canonical side's absence deletes the
    /// mirror; the mirror's absence alone never deletes the original (a re-push
    /// or re-pull recreates it instead). Dead entries drop from the map.
    static func deletePlan(
        remoteIds: Set<String>,
        localIds: Set<String>,
        entries: [MapEntry]
    ) -> (deleteLocalIds: [String], deleteRemoteIds: [String], survivingEntries: [MapEntry]) {
        var deleteLocal: [String] = []
        var deleteRemote: [String] = []
        var surviving: [MapEntry] = []
        for entry in entries {
            let remoteGone = !remoteIds.contains(entry.remoteId)
            let localGone = !localIds.contains(entry.localId)
            if entry.pushed, localGone {
                if !remoteGone { deleteRemote.append(entry.remoteId) }
                continue
            }
            if !entry.pushed, remoteGone {
                if !localGone { deleteLocal.append(entry.localId) }
                continue
            }
            surviving.append(entry)
        }
        return (deleteLocal, deleteRemote, surviving)
    }

    /// Flat directional codec for the link metadata. Legacy direction-less
    /// entries ("gh=local") decode as pushed.
    static func encodeEntries(_ e: [MapEntry]) -> String {
        e.sorted { $0.remoteId < $1.remoteId }
            .map { "\($0.remoteId)=\($0.localId):\($0.pushed ? "p" : "l")" }
            .joined(separator: ",")
    }

    static func decodeEntries(_ s: String?) -> [MapEntry] {
        guard let s, !s.isEmpty else { return [] }
        return s.split(separator: ",").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { return nil }
            let vd = kv[1].split(separator: ":", maxSplits: 1)
            let pushed = vd.count < 2 || vd[1] == "p"
            return MapEntry(remoteId: String(kv[0]), localId: String(vd[0]), pushed: pushed)
        }
    }

    /// Legacy codec kept for the create-plan mapping input.
    static func encodeMapping(_ m: [String: String]) -> String {
        m.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    static func decodeMapping(_ s: String?) -> [String: String] {
        guard let s, !s.isEmpty else { return [:] }
        var out: [String: String] = [:]
        for pair in s.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1].split(separator: ":", maxSplits: 1)[0]) }
        }
        return out
    }

    /// Outbound body: comment text plus a line per attachment (GitHub can't
    /// host the file — name it so the mirror isn't silently empty).
    static func pushBody(content: String, attachmentNames: [String]) -> String {
        let attachmentLines = attachmentNames.map { "📎 \($0) *(attachment in Astrid)*" }
        let parts = ([content.trimmingCharacters(in: .whitespacesAndNewlines)] + attachmentLines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: "\n\n")
    }

    static func isPushable(_ c: LocalComment) -> Bool {
        !pushBody(content: c.content, attachmentNames: c.attachmentNames).isEmpty
    }

    /// Attribution wrapper for comments mirrored INTO Astrid.
    static func pulledContent(author: String, body: String) -> String {
        "**\(author)** (GitHub):\n\n\(body)"
    }
}
