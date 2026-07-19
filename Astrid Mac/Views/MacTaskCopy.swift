//  MacTaskCopy.swift
//  Astrid for Mac — pure copy-target model for the task detail Copy menu (Task 1171030d).

#if os(macOS)
import Foundation

struct MacCopyTarget: Equatable, Identifiable {
    let listId: String?   // nil = "My Tasks only" (no list)
    let label: String
    var id: String { listId ?? "__mytasks__" }
}

enum MacTaskCopy {
    /// Copy destinations: "My Tasks only" first, then every real (non-virtual) list.
    static func targets(lists: [TaskList]) -> [MacCopyTarget] {
        [MacCopyTarget(listId: nil, label: "My Tasks only")]
            + lists.filter { $0.isVirtual != true }.map { MacCopyTarget(listId: $0.id, label: $0.name) }
    }
}
#endif
