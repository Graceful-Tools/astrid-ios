import SwiftUI

// MARK: - Shared Types (used by ChatInputView, CommentSection, QuickAddTaskView, InlineTextAreaEditor)

/// Unified autocomplete item for @mentions, #lists, and !tasks
struct AutocompleteItem: Identifiable {
    let id: String
    let type: AutocompleteType
    let label: String
    let secondaryLabel: String?
    let image: String?
    let isAIAgent: Bool
    let isShared: Bool
    let privacy: String?
    let completed: Bool

    enum AutocompleteType {
        case mention, list, task
    }

    var triggerChar: String {
        switch type {
        case .mention: return "@"
        case .list: return "#"
        case .task: return "!"
        }
    }

    var icon: String {
        switch type {
        case .mention: return isAIAgent ? "sparkles" : "person.circle"
        case .list: return "list.bullet"
        case .task: return completed ? "checkmark.circle.fill" : "circle"
        }
    }

    var iconColor: Color {
        switch type {
        case .mention: return isAIAgent ? .purple : Theme.accent
        case .list: return .green
        case .task: return completed ? .green : Theme.textMuted
        }
    }
}

/// Tracks inserted references so we can reconstruct @[Name](id) on send
struct InsertedReference {
    let id: String
    let type: AutocompleteItem.AutocompleteType
    let displayText: String  // e.g. "@Astrid", "#Career", "!Buy milk"
}

// MARK: - Trigger Detection

/// Detect @, #, or ! triggers in text. Returns (type, position, searchQuery) or nil.
func detectAutocompleteTrigger(in text: String) -> (type: AutocompleteItem.AutocompleteType, position: String.Index, search: String)? {
    let triggerChars: [(Character, AutocompleteItem.AutocompleteType)] = [
        ("@", .mention), ("#", .list), ("!", .task),
    ]

    var bestTrigger: AutocompleteItem.AutocompleteType?
    var bestPos: String.Index?
    var bestSearch: String = ""

    for (char, type) in triggerChars {
        guard let idx = text.lastIndex(of: char) else { continue }
        if idx != text.startIndex {
            let charBefore = text[text.index(before: idx)]
            if !charBefore.isWhitespace && charBefore != "\n" { continue }
        }
        let afterTrigger = String(text[text.index(after: idx)...])
        if afterTrigger.contains(" ") || afterTrigger.contains("\n") { continue }
        if bestPos == nil || idx > bestPos! {
            bestTrigger = type
            bestPos = idx
            bestSearch = afterTrigger
        }
    }

    if let trigger = bestTrigger, let pos = bestPos {
        return (trigger, pos, bestSearch)
    }
    return nil
}

// MARK: - Filtering

/// Filter @mentions from users list
func filterMentionItems(users: [User], search: String) -> [AutocompleteItem] {
    let currentUserId = AuthManager.shared.userId
    var seen = Set<String>()
    var unique: [User] = []
    for user in users {
        if user.id != currentUserId && !seen.contains(user.id) {
            seen.insert(user.id)
            unique.append(user)
        }
    }
    let lowered = search.lowercased()
    let filtered = lowered.isEmpty ? unique : unique.filter {
        $0.displayName.lowercased().contains(lowered) ||
        ($0.email?.lowercased().contains(lowered) ?? false)
    }
    return filtered.map { user in
        AutocompleteItem(
            id: user.id, type: .mention, label: user.displayName,
            secondaryLabel: user.email, image: user.image,
            isAIAgent: user.isAIAgent == true, isShared: false, privacy: nil, completed: false
        )
    }
}

/// Filter #lists
func filterListItems(search: String) -> [AutocompleteItem] {
    let lists = ListService.shared.lists.filter { $0.isVirtual != true }
    let lowered = search.lowercased()
    let filtered = lowered.isEmpty ? lists : lists.filter { $0.name.lowercased().contains(lowered) }
    return Array(filtered.prefix(10)).map { list in
        let isShared = list.privacy == .SHARED || list.privacy == .PUBLIC
        return AutocompleteItem(
            id: list.id, type: .list, label: list.name,
            secondaryLabel: list.privacy?.rawValue.capitalized, image: list.imageUrl,
            isAIAgent: false, isShared: isShared, privacy: list.privacy?.rawValue, completed: false
        )
    }
}

/// Filter !tasks, prioritizing selectedListId
func filterTaskItems(search: String, selectedListId: String? = nil) -> [AutocompleteItem] {
    let allTasks = TaskService.shared.tasks
    let lowered = search.lowercased()
    var filtered = lowered.isEmpty ? allTasks : allTasks.filter { $0.title.lowercased().contains(lowered) }
    filtered.sort { a, b in
        let aInList = a.listIds?.contains(selectedListId ?? "") == true
        let bInList = b.listIds?.contains(selectedListId ?? "") == true
        if aInList != bInList { return aInList }
        if a.completed != b.completed { return !a.completed }
        return (a.updatedAt ?? a.createdAt ?? .distantPast) > (b.updatedAt ?? b.createdAt ?? .distantPast)
    }
    return Array(filtered.prefix(15)).map { task in
        let listName = task.lists?.first?.name ?? task.listIds?.compactMap { id in
            ListService.shared.lists.first(where: { $0.id == id })?.name
        }.first
        return AutocompleteItem(
            id: task.id, type: .task, label: task.title,
            secondaryLabel: listName, image: nil,
            isAIAgent: false, isShared: false, privacy: nil, completed: task.completed
        )
    }
}

/// Build mentionable users from list members + AI agents
func buildMentionableUsers(listId: String? = nil) -> [User] {
    var users: [User] = []
    let listsToScan: [TaskList]
    if let listId = listId, listId != "my-tasks",
       let list = ListService.shared.lists.first(where: { $0.id == listId }) {
        listsToScan = [list]
    } else {
        listsToScan = ListService.shared.lists
    }
    for list in listsToScan {
        if let owner = list.owner { users.append(owner) }
        // Canonical source: `listMembers`. Legacy admins/members arrays are
        // not populated by the lists endpoints iOS calls.
        for lm in list.listMembers ?? [] {
            if let user = lm.user { users.append(user) }
        }
    }
    // Also include members from ListMemberService (loaded separately via /members endpoint)
    // This catches cases where listMembers[].user is nil but the member data is available
    users.append(contentsOf: ListMemberService.shared.members)
    if let agents = AIAgentCache.shared.load() {
        users.append(contentsOf: agents)
    }
    return users
}

/// Reconstruct @[Name](id) from display text using tracked references
func reconstructReferencesInText(_ text: String, references: [InsertedReference]) -> String {
    var result = text
    let sorted = references.sorted { $0.displayText.count > $1.displayText.count }
    for ref in sorted {
        let fullRef = "\(ref.displayText.prefix(1))[\(ref.displayText.dropFirst())](\(ref.id))"
        if let range = result.range(of: ref.displayText) {
            result = result.replacingCharacters(in: range, with: fullRef)
        }
    }
    return result
}

/// Build colored AttributedString from tracked references
func coloredAttributedString(text: String, references: [InsertedReference], defaultColor: Color) -> AttributedString {
    let displayText = text.isEmpty ? " " : text
    guard !references.isEmpty else {
        var plain = AttributedString(displayText)
        plain.foregroundColor = defaultColor
        plain.font = Theme.Typography.body()
        return plain
    }

    var result = AttributedString()
    var remaining = displayText[displayText.startIndex...]

    let sortedRefs = references.compactMap { ref -> (ref: InsertedReference, range: Range<String.Index>)? in
        guard let range = displayText.range(of: ref.displayText) else { return nil }
        return (ref, range)
    }.sorted { $0.range.lowerBound < $1.range.lowerBound }

    for (ref, range) in sortedRefs {
        guard range.lowerBound >= remaining.startIndex else { continue }
        if remaining.startIndex < range.lowerBound {
            var plain = AttributedString(remaining[remaining.startIndex..<range.lowerBound])
            plain.foregroundColor = defaultColor
            plain.font = Theme.Typography.body()
            result += plain
        }
        let color: Color = switch ref.type {
        case .mention: .blue
        case .list: .green
        case .task: .orange
        }
        var colored = AttributedString(ref.displayText)
        colored.foregroundColor = color
        colored.font = Theme.Typography.body()
        result += colored
        remaining = displayText[range.upperBound...]
    }

    if !remaining.isEmpty {
        var plain = AttributedString(remaining)
        plain.foregroundColor = defaultColor
        plain.font = Theme.Typography.body()
        result += plain
    }
    return result
}

// MARK: - Autocomplete Popup View

/// Reusable autocomplete popup for @mentions, #lists, !tasks
struct AutocompletePopupView: View {
    let items: [AutocompleteItem]
    let activeTrigger: AutocompleteItem.AutocompleteType?
    let textColor: Color
    let mutedColor: Color
    let backgroundColor: Color
    let borderColor: Color
    let onSelect: (AutocompleteItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(headerText)
                    .font(Theme.Typography.caption2())
                    .fontWeight(.semibold)
                    .foregroundColor(mutedColor)
                    .textCase(.uppercase)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(mutedColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            HStack(spacing: Theme.spacing8) {
                                autocompleteItemIcon(item)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.label)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(textColor)
                                        .lineLimit(1)
                                    if let secondary = item.secondaryLabel {
                                        Text(secondary)
                                            .font(Theme.Typography.caption2())
                                            .foregroundColor(mutedColor)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if item.isAIAgent {
                                    Text("AI")
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                if item.type == .task && item.completed {
                                    Text("Done")
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, Theme.spacing8)
                            .padding(.vertical, Theme.spacing8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .background(backgroundColor)
        .cornerRadius(Theme.radiusSmall)
        .shadow(radius: 2)
        .padding(.horizontal, Theme.spacing4)
    }

    private var headerText: String {
        switch activeTrigger {
        case .mention: return "People"
        case .list: return "Lists"
        case .task: return "Tasks"
        case .none: return ""
        }
    }

    /// Resolve image URL — handles relative paths and SVG→PNG conversion
    private func resolvedImageURL(_ path: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        var resolved = path
        if resolved.hasSuffix(".svg") {
            resolved = resolved.replacingOccurrences(of: ".svg", with: ".png")
        }
        if !resolved.hasPrefix("http") {
            let baseURL = Constants.API.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return URL(string: baseURL + resolved)
        }
        return URL(string: resolved)
    }

    /// Icon view — uses actual image for agents/lists, falls back to SF Symbol
    @ViewBuilder
    private func autocompleteItemIcon(_ item: AutocompleteItem) -> some View {
        if let url = resolvedImageURL(item.image) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                default:
                    fallbackIcon(item)
                }
            }
            .frame(width: 24, height: 24)
        } else {
            fallbackIcon(item)
        }
    }

    private func fallbackIcon(_ item: AutocompleteItem) -> some View {
        ZStack {
            Circle()
                .fill(item.iconColor.opacity(0.15))
                .frame(width: 24, height: 24)
            Image(systemName: item.icon)
                .font(.system(size: 11))
                .foregroundColor(item.iconColor)
        }
    }
}
