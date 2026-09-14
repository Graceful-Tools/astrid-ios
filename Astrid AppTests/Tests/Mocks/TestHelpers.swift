import Foundation
@testable import Astrid_App

/// Test helper functions for creating test data
/// Provides factory methods for creating model instances with sensible defaults
enum TestHelpers {

    // MARK: - User Factory

    /// Create a test user with sensible defaults
    static func createTestUser(
        id: String = UUID().uuidString,
        name: String? = "Test User",
        email: String? = "test@example.com",
        image: String? = nil,
        createdAt: Date? = nil,
        defaultDueTime: String? = nil,
        isPending: Bool? = nil,
        isAIAgent: Bool? = nil,
        aiAgentType: String? = nil
    ) -> User {
        return User(
            id: id,
            email: email,
            name: name,
            image: image,
            createdAt: createdAt,
            defaultDueTime: defaultDueTime,
            isPending: isPending,
            isAIAgent: isAIAgent,
            aiAgentType: aiAgentType
        )
    }

    // MARK: - Task Factory

    /// Create a minimal test task
    static func createTestTask(
        id: String = UUID().uuidString,
        title: String = "Test Task",
        description: String = "",
        priority: Task.Priority = .none,
        completed: Bool = false,
        dueDateTime: Date? = nil,
        isAllDay: Bool = true,
        repeating: Task.Repeating? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: Task.RepeatFromMode? = nil,
        occurrenceCount: Int? = nil,
        assigneeId: String? = nil,
        assignee: User? = nil,
        creatorId: String? = nil,
        creator: User? = nil,
        listIds: [String]? = nil,
        lists: [TaskList]? = nil,
        isPrivate: Bool = false,
        reminderTime: Date? = nil,
        reminderSent: Bool? = nil,
        reminderType: Task.ReminderType? = nil,
        attachments: [Attachment]? = nil,
        comments: [Comment]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        originalTaskId: String? = nil,
        sourceListId: String? = nil,
        completedAt: Date? = nil,
        completedSource: String? = nil,
        statusRole: String? = nil,
        secureFiles: [SecureFile]? = nil,
        clientRequestId: String? = nil,
        parentTaskId: String? = nil
    ) -> Task {
        return Task(
            id: id,
            title: title,
            description: description,
            assigneeId: assigneeId,
            assignee: assignee,
            creatorId: creatorId,
            creator: creator,
            dueDateTime: dueDateTime,
            isAllDay: isAllDay,
            reminderTime: reminderTime,
            reminderSent: reminderSent,
            reminderType: reminderType,
            repeating: repeating,
            repeatingData: repeatingData,
            repeatFrom: repeatFrom,
            occurrenceCount: occurrenceCount,
            priority: priority,
            lists: lists,
            listIds: listIds,
            isPrivate: isPrivate,
            completed: completed,
            completedAt: completedAt,
            completedSource: completedSource,
            statusRole: statusRole,
            attachments: attachments,
            secureFiles: secureFiles,
            comments: comments,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalTaskId: originalTaskId,
            sourceListId: sourceListId,
            clientRequestId: clientRequestId,
            parentTaskId: parentTaskId
        )
    }

    /// Create a repeating test task
    static func createRepeatingTask(
        id: String = UUID().uuidString,
        title: String = "Repeating Task",
        repeating: Task.Repeating = .daily,
        repeatFrom: Task.RepeatFromMode = .DUE_DATE,
        dueDateTime: Date = Date(),
        occurrenceCount: Int = 0
    ) -> Task {
        return createTestTask(
            id: id,
            title: title,
            dueDateTime: dueDateTime,
            isAllDay: false,
            repeating: repeating,
            repeatFrom: repeatFrom,
            occurrenceCount: occurrenceCount
        )
    }

    /// Create a task with custom repeating pattern
    static func createCustomRepeatingTask(
        id: String = UUID().uuidString,
        title: String = "Custom Repeating Task",
        pattern: CustomRepeatingPattern,
        repeatFrom: Task.RepeatFromMode = .DUE_DATE,
        dueDateTime: Date = Date(),
        occurrenceCount: Int = 0
    ) -> Task {
        return createTestTask(
            id: id,
            title: title,
            dueDateTime: dueDateTime,
            isAllDay: false,
            repeating: .custom,
            repeatingData: pattern,
            repeatFrom: repeatFrom,
            occurrenceCount: occurrenceCount
        )
    }

    // MARK: - TaskList Factory

    /// Create a test list with sensible defaults
    static func createTestList(
        id: String = UUID().uuidString,
        name: String = "Test List",
        color: String? = "#3b82f6",
        privacy: TaskList.Privacy? = .PRIVATE,
        ownerId: String? = nil,
        owner: User? = nil,
        description: String? = nil,
        taskCount: Int? = 0,
        isFavorite: Bool? = false,
        isVirtual: Bool? = false,
        defaultAssigneeId: String? = nil,
        defaultPriority: Int? = nil,
        defaultRepeating: String? = nil,
        defaultDueDate: String? = nil,
        defaultDueTime: String? = nil
    ) -> TaskList {
        return TaskList(
            id: id,
            name: name,
            color: color,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: privacy,
            publicListType: nil,
            ownerId: ownerId,
            owner: owner,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: defaultAssigneeId,
            defaultAssignee: nil,
            defaultPriority: defaultPriority,
            defaultRepeating: defaultRepeating,
            defaultIsPrivate: nil,
            defaultDueDate: defaultDueDate,
            defaultDueTime: defaultDueTime,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: nil,
            updatedAt: nil,
            description: description,
            tasks: nil,
            taskCount: taskCount,
            isFavorite: isFavorite,
            favoriteOrder: nil,
            isVirtual: isVirtual
        )
    }

    // MARK: - CustomRepeatingPattern Factory

    /// Create a daily custom pattern
    static func createDailyPattern(
        interval: Int = 1,
        endCondition: String = "never",
        endAfterOccurrences: Int? = nil,
        endUntilDate: Date? = nil
    ) -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )
    }

    /// Create a weekly custom pattern with specific weekdays
    static func createWeeklyPattern(
        interval: Int = 1,
        weekdays: [String] = ["monday", "wednesday", "friday"],
        endCondition: String = "never",
        endAfterOccurrences: Int? = nil,
        endUntilDate: Date? = nil
    ) -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: weekdays,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )
    }

    /// Create a monthly custom pattern (same date each month)
    static func createMonthlySameDatePattern(
        interval: Int = 1,
        endCondition: String = "never",
        endAfterOccurrences: Int? = nil,
        endUntilDate: Date? = nil
    ) -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "months",
            interval: interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: nil,
            monthRepeatType: "same_date",
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )
    }

    /// Create a monthly custom pattern (same weekday, e.g., "2nd Tuesday")
    static func createMonthlySameWeekdayPattern(
        interval: Int = 1,
        weekday: String = "tuesday",
        weekOfMonth: Int = 2,
        endCondition: String = "never",
        endAfterOccurrences: Int? = nil,
        endUntilDate: Date? = nil
    ) -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "months",
            interval: interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: nil,
            monthRepeatType: "same_weekday",
            monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: weekday, weekOfMonth: weekOfMonth),
            month: nil,
            day: nil
        )
    }

    /// Create a yearly custom pattern
    static func createYearlyPattern(
        interval: Int = 1,
        month: Int = 1,
        day: Int = 1,
        endCondition: String = "never",
        endAfterOccurrences: Int? = nil,
        endUntilDate: Date? = nil
    ) -> CustomRepeatingPattern {
        return CustomRepeatingPattern(
            type: "custom",
            unit: "years",
            interval: interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: month,
            day: day
        )
    }

    // MARK: - Date Helpers

    /// Create a date with specific components
    static func createDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 9,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)!
    }

    /// Create a date relative to now
    static func createRelativeDate(
        daysFromNow: Int = 0,
        hoursFromNow: Int = 0,
        minutesFromNow: Int = 0
    ) -> Date {
        let now = Date()
        var components = DateComponents()
        components.day = daysFromNow
        components.hour = hoursFromNow
        components.minute = minutesFromNow
        return Calendar.current.date(byAdding: components, to: now)!
    }

    // MARK: - Comment Factory

    /// Create a test comment
    static func createTestComment(
        id: String = UUID().uuidString,
        content: String = "Test comment",
        type: Comment.CommentType = .TEXT,
        authorId: String? = nil,
        author: User? = nil,
        taskId: String = UUID().uuidString,
        createdAt: Date? = nil
    ) -> Comment {
        return Comment(
            id: id,
            content: content,
            type: type,
            authorId: authorId,
            author: author,
            taskId: taskId,
            createdAt: createdAt,
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )
    }

    // MARK: - Attachment Factory

    /// Create a test attachment
    static func createTestAttachment(
        id: String = UUID().uuidString,
        name: String = "test-file.pdf",
        url: String = "https://example.com/test-file.pdf",
        type: String = "application/pdf",
        size: Int = 1024,
        taskId: String? = nil
    ) -> Attachment {
        return Attachment(
            id: id,
            name: name,
            url: url,
            type: type,
            size: size,
            createdAt: nil,
            taskId: taskId
        )
    }
}
