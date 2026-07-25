//  MacEmptyState.swift
//  Astrid for Mac — branded empty states (Task 1c3562e9): the Astrid character + a friendly
//  speech bubble, replacing generic system ContentUnavailableViews (mirrors iOS EmptyStateView /
//  AstridSpeechBubble, sized for desktop).

#if os(macOS)
import SwiftUI

/// Pure copy per empty context (testable).
enum MacEmptyCopy {
    case noTasks, filteredOut, noListSelected, chatEmpty

    var message: String {
        switch self {
        case .noTasks:        return "All clear! Add a task below to get started."
        case .filteredOut:    return "Nothing matches this list’s filters."
        case .noListSelected: return "Pick a list to see your tasks."
        case .chatEmpty:      return "Start the conversation — say hi or @mention Astrid."
        }
    }
    var detail: String? {
        switch self {
        case .filteredOut: return "Adjust the filters (funnel button) to see more."
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
