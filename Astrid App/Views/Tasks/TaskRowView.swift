import SwiftUI

struct TaskRowView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    @EnvironmentObject var authManager: AuthManager
    let task: Task
    let onToggle: () -> Void
    var isViewingFeaturedPublicList: Bool = false
    var onCopy: (() -> Void)? = nil
    var isSelected: Bool = false
    var compactMode: Bool = false  // When true, truncate title to single line (used when details panel is visible)
    /// List ids the surrounding view already conveys (current list,
    /// current board column's status list, etc.) — filtered out of
    /// the chip set so the row doesn't surface redundant noise.
    var hiddenListIds: Set<String> = []
    /// When true, the row draws NO background / border / clip — the
    /// host (e.g. a board card) provides the single card chrome.
    /// Without this a board card showed two nested borders.
    var embeddedInCard: Bool = false

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    // Check if task belongs to any PUBLIC list
    private var isPublicListTask: Bool {
        task.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false
    }

    // Get effective assignee - use task.assignee if available, or create minimal User from assigneeId
    // This handles the case where task is loaded from Core Data (which only stores assigneeId)
    private var effectiveAssignee: User? {
        // First try the full assignee object
        if let assignee = task.assignee {
            return assignee
        }
        // If we have an assigneeId, create a minimal User that can use UserImageCache
        if let assigneeId = task.assigneeId {
            return User(
                id: assigneeId,
                email: nil,
                name: nil,
                image: nil,  // Will fallback to UserImageCache via cachedImageURL
                createdAt: nil,
                defaultDueTime: nil,
                isPending: nil,
                isAIAgent: nil,
                aiAgentType: nil
            )
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            // For public list tasks, show copy button instead of checkbox
            if isPublicListTask {
                Button(action: {
                    // Haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onCopy?()
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.clear)
                            )
                            .frame(width: 34, height: 34)

                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                }
                .buttonStyle(.plain)
            }
            // Show avatar if task is assigned to someone other than current user
            // Otherwise show completion checkbox
            else if let assignee = effectiveAssignee,
               let currentUser = authManager.currentUser,
               assignee.id != currentUser.id {
                // Show assignee avatar instead of checkbox for shared list tasks
                // Use cachedImageURL to leverage UserImageCache from list member data
                CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    // Show initials placeholder for loading or failed states
                    ZStack {
                        Circle()
                            .fill(Theme.accent)
                        Text(assignee.initials)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(priorityColor, lineWidth: 2)
                )
            } else {
                // Show completion checkbox for own tasks or unassigned tasks
                // Using custom checkbox images matching mobile web
                Button(action: {
                    // Haptic feedback based on completion state
                    if task.completed {
                        // Light impact when uncompleting
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    } else {
                        // Success notification when completing
                        let notification = UINotificationFeedbackGenerator()
                        notification.notificationOccurred(.success)
                    }

                    onToggle()
                }) {
                    checkboxImage
                }
                .buttonStyle(.plain)
            }

            // Task content
            VStack(alignment: .leading, spacing: 6) {
                // Title - 10% larger than standard (17pt × 1.1 = 19pt)
                // In compact mode (details panel visible), truncate to single line
                Text(task.title)
                    .font(.system(size: 19, weight: .medium))
                    .lineSpacing(-1)
                    .lineLimit(compactMode ? 1 : nil)
                    .truncationMode(.tail)
                    .strikethrough(task.completed)
                    .foregroundColor(
                        task.completed
                            ? (effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted)
                            : (effectiveTheme == "dark" ? Theme.Dark.textPrimary : Theme.textPrimary)
                    )

                // Combined metadata row: date first (left), then lists - matching web
                // Drop the row entirely when there's nothing useful to show
                // (no chips after context-filtering AND no due date). Without
                // this, a task whose only list IS the currently-viewed list
                // would leave an empty metadata strip beneath the title and
                // the title wouldn't vertically center in the row.
                let chipLists = chipListsForTaskRow(task.lists, hiddenListIds: hiddenListIds)
                let hasDateToShow = task.dueDateTime != nil && !isPublicListTask
                if !chipLists.isEmpty || hasDateToShow {
                    HStack(spacing: Theme.spacing8) {
                        // Date/Time (left side, plain text) - hide for public list tasks
                        // Use dueDateTime + isAllDay to determine display
                        if !isPublicListTask {
                            if let dueDateTime = task.dueDateTime {
                                if task.isAllDay {
                                    // All-day task - show relative date (Today/Tomorrow/etc) using UTC calendar
                                    Text(formatDate(dueDateTime))
                                        .font(Theme.Typography.subheadline()) // 15pt
                                        .foregroundColor(effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted)
                                } else {
                                    // Timed task - show date + time (local timezone)
                                    Text(formatDateTimeShort(dueDateTime))
                                        .font(Theme.Typography.subheadline()) // 15pt
                                        .foregroundColor(effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }

                        // Lists (after date) - only show when full list objects are available.
                        // Status lists ("Ready"/"Doing"/"Waiting") are filtered out so the
                        // regular project list survives `prefix(2)`; status only makes sense
                        // inside the board view, not the flat list.
                        if !chipLists.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(chipLists.prefix(2)) { list in
                                    HStack(spacing: 4) {
                                        // Icon based on list privacy
                                        if list.privacy == .PUBLIC {
                                            Image(systemName: "globe")
                                                .font(.system(size: 12))
                                                .foregroundColor(.green)
                                        } else if let members = list.listMembers, members.count > 1 {
                                            Image(systemName: "person.2")
                                                .font(.system(size: 12))
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "number")
                                                .font(.system(size: 12))
                                                .foregroundColor(Color(hex: list.displayColor) ?? Theme.accent)
                                        }

                                        Text(list.name)
                                            .font(Theme.Typography.subheadline()) // 15pt (was 12pt)
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(effectiveTheme == "dark" ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(getBadgeBackground())
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(getBorderColor(), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                if chipLists.count > 2 {
                                    Text("+\(chipLists.count - 2)")
                                        .font(Theme.Typography.subheadline())
                                        .foregroundColor(effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }

                        Spacer()
                    }
                    // Consistent height for metadata row - matches badge height (15pt font + 8pt padding)
                    .frame(minHeight: 27)
                }
            }

            Spacer()
        }
        // Board cards: 12pt vertical, 10pt horizontal. The horizontal
        // inset is cut by the same amount the card's outer margin grew
        // (LazyVStack padding in BoardColumnView) so the checkbox stays
        // put while the card itself gets narrower. List view: 14 / 16.
        .padding(.vertical, embeddedInCard ? 12 : 14)
        .padding(.horizontal, embeddedInCard ? 10 : Theme.spacing16)
        .frame(minHeight: 76)  // Min height: title(~22pt) + spacing(6pt) + metadata(~18pt) + padding(28pt)
        .background(
            // Main card background + selection arrow for iPad.
            // Suppressed when embedded in a board card — the host
            // supplies the single card background there.
            ZStack(alignment: .trailing) {
                if !embeddedInCard {
                    cardBackground
                }

                // Arrow indicator pointing to task details (iPad only, when selected)
                if isSelected && UIDevice.current.userInterfaceIdiom == .pad {
                    SelectionArrow(color: getCardBackground())
                        .offset(x: 20)  // Position arrow at right edge, extending into gap
                }
            }
        )
        .contentShape(Rectangle())
        .overlay(
            // Card border with rounded corners. Suppressed when
            // embedded in a board card so there's just ONE border.
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    embeddedInCard
                        ? Color.clear
                        : (isSelected ? Color.accentColor : getBorderColor()),
                    lineWidth: isSelected ? 2.5 : 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Theme Helpers

    /// Card background with support for Liquid Glass theme
    @ViewBuilder
    private var cardBackground: some View {
        if effectiveTheme == "light" {
            // Light theme: Use material blur for glass effect
            if isSelected {
                // Selected state: thicker glass with accent tint
                ZStack {
                    Theme.LiquidGlass.accentGlassTint
                    Rectangle()
                        .fill(Theme.LiquidGlass.secondaryGlassMaterial)
                }
            } else {
                // Normal state: ultra-thin glass
                Rectangle()
                    .fill(Theme.LiquidGlass.primaryGlassMaterial)
            }
        } else {
            // Other themes: solid backgrounds
            getCardBackground()
        }
    }

    /// Get card background color (20% transparent white on Ocean theme for subtle cyan show-through)
    private func getCardBackground() -> Color {
        if effectiveTheme == "ocean" {
            // Selected row is solid white; the rest are 20% translucent.
            return Color.white.opacity(isSelected ? 1.0 : 0.8)
        }
        return effectiveTheme == "dark" ? Theme.Dark.bgPrimary : Theme.bgPrimary
    }

    /// Get border color based on current theme
    private func getBorderColor() -> Color {
        if effectiveTheme == "ocean" {
            return Theme.Ocean.border  // Cyan border on Ocean
        }
        if effectiveTheme == "light" {
            return Theme.LiquidGlass.border  // Subtle glass edge on Light
        }
        return effectiveTheme == "dark" ? Theme.Dark.border : Theme.border
    }

    /// Get background color for list badges
    private func getBadgeBackground() -> Color {
        if effectiveTheme == "light" {
            return Color.white.opacity(0.3)  // Translucent badge on glass
        }
        if effectiveTheme == "ocean" {
            return Theme.Ocean.bgTertiary  // Subtle gray for badges on white cards
        }
        return effectiveTheme == "dark" ? Theme.Dark.bgSecondary : Theme.bgSecondary
    }
    
    private var priorityColor: Color {
        switch task.priority {
        case .none:
            return Theme.priorityNone
        case .low:
            return Theme.priorityLow
        case .medium:
            return Theme.priorityMedium
        case .high:
            return Theme.priorityHigh
        }
    }

    /// Custom checkbox image matching mobile web design
    private var checkboxImage: some View {
        let priorityValue = task.priority.rawValue
        let isRepeating = task.repeating != nil && task.repeating != .never
        let isChecked = task.completed

        // Build image name: check_box[_repeat][_checked]_<priority>
        var imageName = "check_box"
        if isRepeating {
            imageName += "_repeat"
        }
        if isChecked {
            imageName += "_checked"
        }
        imageName += "_\(priorityValue)"

        return Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
    }

    /// Format date + time in short form (e.g., "Jan 5 6:26 PM")
    /// Used when task has a specific time set (not all-day)
    /// Date+time uses local timezone (user's timezone) since it represents a specific moment
    private func formatDateTimeShort(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        // Use local timezone for date+time (represents specific moment in user's timezone)

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short  // e.g., "6:26 PM"

        return "\(dateFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }

    private func formatDate(_ date: Date) -> String {
        // CRITICAL: Get "today" from LOCAL calendar first, then convert to UTC
        // This ensures "Today" means the user's local day, not UTC day
        let localCalendar = Calendar.current
        let todayLocal = localCalendar.startOfDay(for: Date())
        let todayComponents = localCalendar.dateComponents([.year, .month, .day], from: todayLocal)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Create UTC midnight for today's local date
        guard let todayUTC = utcCalendar.date(from: DateComponents(
            year: todayComponents.year,
            month: todayComponents.month,
            day: todayComponents.day,
            hour: 0,
            minute: 0,
            second: 0
        )) else { return date.description }

        let compareDate = utcCalendar.startOfDay(for: date)
        let daysDiff = utcCalendar.dateComponents([.day], from: todayUTC, to: compareDate).day ?? 0

        if daysDiff == 0 {
            return "Today"
        } else if daysDiff == 1 {
            return "Tomorrow"
        } else if daysDiff == -1 {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.timeZone = TimeZone(identifier: "UTC")  // Display in UTC
            return formatter.string(from: date)
        }
    }

}

// MARK: - Selection Arrow (points to task details on iPad)

/// Arrow indicator that points from selected task row to task details pane
struct SelectionArrow: View {
    let color: Color

    var body: some View {
        Triangle()
            .fill(color)
            .frame(width: 12, height: 24)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 0)
    }
}

/// Triangle shape pointing to the right
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

#Preview {
    let task = Task(
        id: "1",
        title: "Sample Task",
        description: "This is a sample task description",
        creatorId: "user1",
        isAllDay: false,
        repeating: .never,
        priority: .high,
        isPrivate: false,
        completed: false
    )

    List {
        TaskRowView(task: task) {
            print("Toggled")
        }
    }
}
