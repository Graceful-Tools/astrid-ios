//  MacEmptyState.swift
//  Astrid for Mac — branded empty states (Task 1c3562e9): the Astrid character + a friendly
//  speech bubble, replacing generic system ContentUnavailableViews. Since ADEV-166 it IS iOS's
//  `AstridSpeechBubble`, at the compact density.

#if os(macOS)
import SwiftUI

/// Pure copy per empty context (testable).
enum MacEmptyCopy {
    case noTasks, filteredOut, noListSelected, chatEmpty, searchPrompt, searchNoResults

    // Astrid's own voice is part of the product, so these are localized like every other string
    // (task 2eb3a080) — they were the last hardcoded English left on Mac.
    var message: String {
        switch self {
        case .noTasks:        return NSLocalizedString("mac.empty.no_tasks", comment: "")
        case .filteredOut:    return NSLocalizedString("mac.empty.filtered_out", comment: "")
        case .noListSelected: return NSLocalizedString("mac.empty.no_list_selected", comment: "")
        case .chatEmpty:      return Brand.localized("mac.empty.chat")
        case .searchPrompt:   return NSLocalizedString("mac.empty.search_prompt", comment: "")
        case .searchNoResults: return NSLocalizedString("mac.empty.search_none", comment: "")
        }
    }
    var detail: String? {
        switch self {
        case .filteredOut: return NSLocalizedString("mac.empty.filtered_out_detail", comment: "")
        case .searchPrompt: return NSLocalizedString("mac.search_hint", comment: "")
        default: return nil
        }
    }
}

/// The shared empty state (ADEV-166) at the Mac's density: the same Astrid-and-speech-bubble iOS
/// draws, with smaller art.
struct MacEmptyState: View {
    let copy: MacEmptyCopy

    var body: some View {
        AstridSpeechBubble(message: copy.message, detail: copy.detail, density: .compact,
                           // Which empty state, for the UI suite — the copy is localized (AITD-526).
                           messageIdentifier: "emptyState.\(copy)")
            .padding(.horizontal, Theme.spacing24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
