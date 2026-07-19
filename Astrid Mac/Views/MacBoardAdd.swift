//  MacBoardAdd.swift
//  Astrid for Mac — pure mapping for adding a card into a board column (Task db8aacda).
//
//  A new card is created in the board's domain list, then placed into the target column by
//  reusing the SAME MacBoardMove.plan the drag path uses. This turns that plan into the
//  concrete (listIds, shouldComplete) to apply to the freshly-created task. Pure + testable.

#if os(macOS)
import Foundation

enum MacBoardAdd {
    static func apply(_ plan: MacBoardMove.Plan) -> (listIds: [String]?, complete: Bool) {
        switch plan {
        case .none:                        return (nil, false)
        case .setLists(let ids):           return (ids, false)
        case .uncomplete(let ids):         return (ids, false)   // a new task is already incomplete
        case .complete(let ids):           return (ids, true)
        }
    }
}
#endif
