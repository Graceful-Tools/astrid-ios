import Foundation

struct Task: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var title: String
    var description: String
    var assigneeId: String?
    var assignee: User?
    var creatorId: String?  // Optional - MCP API doesn't return this, only creator object
    var creator: User?
    var dueDateTime: Date?  // The due date/time (single source of truth)
    var isAllDay: Bool  // Whether this is an all-day task (true = all-day, false = timed)
    var reminderTime: Date?
    var reminderSent: Bool?
    var reminderType: ReminderType?
    var repeating: Repeating?  // Optional - MCP API doesn't always return this
    var repeatingData: CustomRepeatingPattern?
    var repeatFrom: RepeatFromMode?  // Whether to repeat from due date or completion date
    var occurrenceCount: Int?  // Number of times this task has repeated
    var timerDuration: Int?  // New field
    var lastTimerValue: String? // Last completion details for the timer
    var priority: Priority
    var lists: [TaskList]?
    var listIds: [String]?
    var isPrivate: Bool
    var completed: Bool
    var attachments: [Attachment]?
    var secureFiles: [SecureFile]?
    var comments: [Comment]?
    var createdAt: Date?
    var updatedAt: Date?
    var originalTaskId: String?
    var sourceListId: String?
    var clientRequestId: String?

    enum Priority: Int, Codable, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        /// Lenient decode: the server is permissive (Prisma schema has
        /// no cap on `priority`), and 2 prod tasks for jonparis@gmail.com
        /// were observed with `priority: 4`. Swift's default rawValue
        /// decode would throw on those, which fails the WHOLE tasks
        /// array decode and silently breaks sync. Unknown values fall
        /// back to `.none` so the task stays usable.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(Int.self)
            self = Priority(rawValue: raw) ?? .none
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var displayName: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
        
        var color: String {
            switch self {
            case .none: return "gray"
            case .low: return "#10b981"
            case .medium: return "#f59e0b"
            case .high: return "#ef4444"
            }
        }
    }
    
    enum Repeating: String, Codable, CaseIterable {
        case never, daily, weekly, monthly, yearly, custom
        
        var displayName: String {
            switch self {
            case .never: return "Never"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .custom: return "Custom"
            }
        }
    }
    
    enum ReminderType: String, Codable {
        case push, email, both
    }

    enum RepeatFromMode: String, Codable, CaseIterable {
        case DUE_DATE
        case COMPLETION_DATE

        var displayName: String {
            switch self {
            case .DUE_DATE: return "Repeat from due date"
            case .COMPLETION_DATE: return "Repeat from completion date"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, assigneeId, assignee, creatorId, creator
        case dueDateTime  // Primary datetime field
        case isAllDay  // All-day task flag
        case reminderTime, reminderSent, reminderType
        case repeating, repeatingData, repeatFrom, occurrenceCount, timerDuration, lastTimerValue
        case priority, lists, listIds
        case isPrivate, completed, attachments, secureFiles, comments
        case createdAt, updatedAt, originalTaskId, sourceListId, clientRequestId
    }

    // Custom initializer with default values to avoid breaking existing code
    init(
        id: String,
        title: String,
        description: String = "",
        assigneeId: String? = nil,
        assignee: User? = nil,
        creatorId: String? = nil,
        creator: User? = nil,
        dueDateTime: Date? = nil,
        isAllDay: Bool = true,
        reminderTime: Date? = nil,
        reminderSent: Bool? = nil,
        reminderType: ReminderType? = nil,
        repeating: Repeating? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: RepeatFromMode? = nil,
        occurrenceCount: Int? = nil,
        timerDuration: Int? = nil,
        lastTimerValue: String? = nil,
        priority: Priority = .none,
        lists: [TaskList]? = nil,
        listIds: [String]? = nil,
        isPrivate: Bool = false,
        completed: Bool = false,
        attachments: [Attachment]? = nil,
        secureFiles: [SecureFile]? = nil,
        comments: [Comment]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        originalTaskId: String? = nil,
        sourceListId: String? = nil,
        clientRequestId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.assigneeId = assigneeId
        self.assignee = assignee
        self.creatorId = creatorId
        self.creator = creator
        self.dueDateTime = dueDateTime
        self.isAllDay = isAllDay
        self.reminderTime = reminderTime
        self.reminderSent = reminderSent
        self.reminderType = reminderType
        self.repeating = repeating
        self.repeatingData = repeatingData
        self.repeatFrom = repeatFrom
        self.occurrenceCount = occurrenceCount
        self.timerDuration = timerDuration
        self.lastTimerValue = lastTimerValue
        self.priority = priority
        self.lists = lists
        self.listIds = listIds
        self.isPrivate = isPrivate
        self.completed = completed
        self.attachments = attachments
        self.secureFiles = secureFiles
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalTaskId = originalTaskId
        self.sourceListId = sourceListId
        self.clientRequestId = clientRequestId
    }
}

// Marked `nonisolated` so its Codable conformance is usable from nonisolated
// contexts (e.g. CDTask encode/decode helpers). The struct holds only value-type
// fields, so it is inherently thread-safe.
nonisolated struct CustomRepeatingPattern: Codable, Equatable, Hashable {
    var type: String?  // Always "custom"
    var unit: String?  // "days", "weeks", "months", "years"
    var interval: Int?  // Every X days/weeks/months/years
    var endCondition: String?  // "never", "after_occurrences", "until_date"
    var endAfterOccurrences: Int?
    var endUntilDate: Date?

    // For weekly patterns
    var weekdays: [String]?  // ["monday", "wednesday", "friday"]

    // For monthly patterns
    var monthRepeatType: String?  // "same_date" or "same_weekday"
    var monthDay: Int?  // 1-31 for same_date
    var monthWeekday: MonthWeekday?  // For same_weekday

    // For yearly patterns
    var month: Int?  // 1-12
    var day: Int?    // 1-31

    nonisolated struct MonthWeekday: Codable, Equatable, Hashable {
        var weekday: String  // "monday", "tuesday", etc.
        var weekOfMonth: Int  // 1-5
    }
}

struct Attachment: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var url: String
    var type: String
    var size: Int
    var createdAt: Date?
    var taskId: String?
}

struct Comment: Identifiable, Codable, Equatable, Hashable {
    var id: String  // Mutable to allow updating temp ID → real ID
    var content: String
    var type: CommentType
    var authorId: String?  // Optional to support system comments (authorId: null)
    var author: User?
    var taskId: String
    var createdAt: Date?
    var updatedAt: Date?
    var attachmentUrl: String?
    var attachmentName: String?
    var attachmentType: String?
    var attachmentSize: Int?
    var parentCommentId: String?
    var replies: [Comment]?
    var secureFiles: [SecureFile]?
    var clientRequestId: String?  // Server echoes back the temp_<UUID> idempotency key — use it for offline-sync dedup

    /// Stable ID for SwiftUI ForEach - uses id if valid, otherwise generates from content hash
    var stableId: String {
        if !id.isEmpty {
            return id
        }
        // Fallback for corrupted data with empty IDs
        let contentHash = content.hashValue
        let dateHash = createdAt?.timeIntervalSince1970 ?? 0
        return "fallback_\(contentHash)_\(Int(dateHash))"
    }

    enum CommentType: String, Codable {
        case TEXT, MARKDOWN, ATTACHMENT
    }
}

struct SecureFile: Codable, Equatable, Hashable {
    var id: String
    var name: String
    var size: Int
    var mimeType: String

    // Map API field names to iOS property names
    enum CodingKeys: String, CodingKey {
        case id
        case name = "originalName"  // API returns "originalName"
        case size = "fileSize"      // API returns "fileSize"
        case mimeType
    }
}

// MARK: - Task Extensions
extension Task {
    /// Returns the creator's user ID, checking both creatorId field and creator object
    /// This is necessary because MCP API returns creator object but not creatorId field
    var effectiveCreatorId: String? {
        return creatorId ?? creator?.id
    }

    /// Check if the given user ID is the creator of this task
    func isCreatedBy(_ userId: String) -> Bool {
        return effectiveCreatorId == userId
    }

    /// Returns all unique secure files from this task (direct and from comments)
    var allSecureFiles: [SecureFile] {
        var seenIds = Set<String>()
        var uniqueFiles: [SecureFile] = []
        
        // 1. Add direct task attachments
        if let directFiles = secureFiles {
            for file in directFiles {
                if !seenIds.contains(file.id) {
                    seenIds.insert(file.id)
                    uniqueFiles.append(file)
                }
            }
        }
        
        // 2. Add legacy attachments (if any, converted to SecureFile)
        if let legacyAttachments = attachments {
            for att in legacyAttachments {
                if !seenIds.contains(att.id) {
                    seenIds.insert(att.id)
                    uniqueFiles.append(SecureFile(
                        id: att.id,
                        name: att.name,
                        size: att.size,
                        mimeType: att.type
                    ))
                }
            }
        }
        
        // 3. Add files from comments
        if let comments = comments {
            for comment in comments {
                if let files = comment.secureFiles {
                    for file in files {
                        if !seenIds.contains(file.id) {
                            seenIds.insert(file.id)
                            uniqueFiles.append(file)
                        }
                    }
                }
            }
        }
        
        return uniqueFiles
    }
}
