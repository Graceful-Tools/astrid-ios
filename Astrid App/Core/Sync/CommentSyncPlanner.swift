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
        }
        return (pullCreates, pushCreates)
    }

    /// Flat codec so the mapping fits the [String: String] link metadata.
    static func encodeMapping(_ m: [String: String]) -> String {
        m.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    static func decodeMapping(_ s: String?) -> [String: String] {
        guard let s, !s.isEmpty else { return [:] }
        var out: [String: String] = [:]
        for pair in s.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }

    /// Attribution wrapper for comments mirrored INTO Astrid.
    static func pulledContent(author: String, body: String) -> String {
        "**\(author)** (GitHub):\n\n\(body)"
    }
}
