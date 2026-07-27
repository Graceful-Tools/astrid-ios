//  MacDataStrings.swift
//  Astrid for Mac — localized labels for English text that lives in DATA (Task 29b673c0).
//
//  The localization passes caught string literals sitting in view builders. These are the ones
//  they could not see: repeat units and member roles rendered with `.capitalized`, command-palette
//  entries, copy destinations, onboarding copy, and the ⌘/ sheet's shortcut titles — which come
//  from the cross-platform table in KeyboardShortcuts.swift and stay English there on purpose
//  (that `title` is the contract's documentation, shared with web), so the Mac looks them up here.

#if os(macOS)
import Foundation

/// "days" → "Days" / "Tage" / "日". Reuses the iOS repeating.* keys so the two apps agree.
enum MacRepeatUnitLabel {
    static func title(for unit: String) -> String {
        switch unit {
        case "days":   return NSLocalizedString("repeating.days", comment: "")
        case "weeks":  return NSLocalizedString("repeating.weeks", comment: "")
        case "months": return NSLocalizedString("repeating.months", comment: "")
        case "years":  return NSLocalizedString("repeating.years", comment: "")
        default:       return unit.capitalized
        }
    }
}

/// "member" → "Member" / "Mitglied". Reuses the iOS list-role keys.
enum MacMemberRoleLabel {
    static func title(for role: String) -> String {
        switch role {
        case "member": return NSLocalizedString("lists.member_role", comment: "")
        case "admin":  return NSLocalizedString("lists.admin", comment: "")
        case "owner":  return NSLocalizedString("lists.owner", comment: "")
        default:       return role.capitalized
        }
    }
}

/// The ⌘/ sheet's row titles. The shared table keeps its English `title` (it mirrors web's
/// handler names and is part of the contract); the sheet shows the translation.
enum MacShortcutTitle {
    static func localized(for action: ShortcutAction) -> String {
        NSLocalizedString("mac.shortcut.\(action.rawValue)", comment: "")
    }
}
#endif
