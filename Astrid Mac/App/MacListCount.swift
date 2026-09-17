//  MacListCount.swift
//  Astrid for Mac — the sidebar's per-list count (task 74d6f6aa).
//
//  THE RULE MOVED. This was the only implementation; iOS had a private copy in
//  `ListSidebarView` that counted membership by hydrated `lists` alone and therefore showed 0
//  for every list offline (AITD-414). Rather than fix that copy, the rule was promoted to
//  `Core/Lists/ListTaskCount.swift`, which both platforms compile.
//
//  This stays as the Mac's name for it so the Mac call sites and `MacListCountTests` keep
//  reading naturally — it forwards, it does not re-implement. Add nothing here.

#if os(macOS)
import Foundation

enum MacListCount {
    static func counts(_ tasks: [Task], lists: [TaskList], currentUserId: String?) -> [String: Int] {
        ListTaskCount.counts(tasks, lists: lists, currentUserId: currentUserId)
    }

    static func count(_ tasks: [Task], list: TaskList, currentUserId: String?) -> Int {
        ListTaskCount.count(tasks, list: list, currentUserId: currentUserId)
    }
}
#endif
