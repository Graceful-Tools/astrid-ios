//  MacEmptyState.swift
//  Astrid for Mac — branded empty states (Task 1c3562e9): the Astrid character + a friendly
//  speech bubble, replacing generic system ContentUnavailableViews (mirrors iOS EmptyStateView /
//  AstridSpeechBubble, sized for desktop).

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

struct MacEmptyState: View {
    let copy: MacEmptyCopy

    var body: some View {
        VStack(spacing: 14) {
            Image("AstridCharacter")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 4) {
                Text(copy.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let d = copy.detail {
                    Text(d).font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}
#endif
