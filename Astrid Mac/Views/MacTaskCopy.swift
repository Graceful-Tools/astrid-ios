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
    /// Copy destinations: "My Tasks only" first, then every real (non-virtual) list — never a tag
    /// (label, milestone, sprint), which is a chip rather than a place (AITD-506).
    static func targets(lists: [TaskList]) -> [MacCopyTarget] {
        [MacCopyTarget(listId: nil, label: NSLocalizedString("mac.my_tasks_only", comment: ""))]
            + lists.filter { $0.isVirtual != true && !$0.isTagList }.map { MacCopyTarget(listId: $0.id, label: $0.name) }
    }
}
#endif
