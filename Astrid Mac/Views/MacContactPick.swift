//  MacContactPick.swift
//  Astrid for Mac — pure display helper for contact-invite suggestions (Task 3753a521).

#if os(macOS)
import Foundation

enum MacContactPick {
    /// Suggestion label: "Name — email", or just the email when there's no name.
    static func display(name: String?, email: String) -> String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return "\(n) — \(email)" }
        return email
    }
}
#endif
