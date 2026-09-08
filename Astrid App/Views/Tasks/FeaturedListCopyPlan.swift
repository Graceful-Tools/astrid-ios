//  FeaturedListCopyPlan.swift
//  Whether a tap on the featured-list "Copy List" button should start a copy.
//
//  Pulled out of the view so the rule can be tested without SwiftUI (task AITD-348), the same way
//  `PasskeySignInPlan` holds the sign-in fallback rule. The re-entry guard is the part worth
//  pinning: the spinner is the only sign a copy is running, and it is small, so an impatient
//  second tap would otherwise file the list twice.
import Foundation

enum FeaturedListCopyPlan: Equatable {
    case copy(listId: String)
    case ignore

    static func decide(selectedListId: String?, isCopying: Bool) -> FeaturedListCopyPlan {
        guard let selectedListId, !isCopying else { return .ignore }
        return .copy(listId: selectedListId)
    }
}
