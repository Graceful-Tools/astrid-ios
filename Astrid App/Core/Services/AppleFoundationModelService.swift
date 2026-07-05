import Foundation
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "AppleFM")

/// Sentinel ID used to identify the on-device Apple Foundation Model in settings
let kAppleFoundationModelId = "apple-foundation-model"

/// Result of AI-powered task parsing via Apple Foundation Models
struct AITaskParseResult {
    let title: String
    let description: String?
    let dueDate: Date?
    let priority: Int?       // 0-3
    let repeating: String?   // "daily"|"weekly"|"monthly"|"yearly"
    let listHint: String?    // e.g., "shopping" (from #shopping)
}

/// Service wrapping Apple's Foundation Models framework (iOS 26+) for on-device AI task management.
/// Provides free, private, on-device inference with no API keys or server costs.
@MainActor
final class AppleFoundationModelService {

    static let shared = AppleFoundationModelService()

    private init() {}

    // MARK: - Availability

    /// Whether Apple Foundation Models are available on this device
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return true
        }
        #endif
        return false
    }

    // MARK: - Task Parsing

    /// Parse natural language input into structured task data using on-device AI.
    func parseTask(_ input: String) async -> AITaskParseResult? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await _parseTask(input)
        }
        #endif
        logger.warning("Foundation Models not available on this device")
        return nil
    }

    // MARK: - Chat Response with Task Management

    /// Process a chat message directed at Astrid and generate a response.
    /// The model can read tasks and return structured actions (create/update/complete).
    /// Returns the response text to post as Astrid, or nil if unavailable.
    func processChatMessage(_ message: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await _processChatMessage(message)
        }
        #endif
        return nil
    }
}

// MARK: - iOS 26+ Implementation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
extension AppleFoundationModelService {

    // MARK: - Generable Schemas

    @Generable
    struct TaskParseSchema {
        /// The cleaned task title with metadata keywords removed
        var title: String
        /// Optional task description or additional details
        var description: String?
        /// ISO 8601 date string for when the task is due
        var dueDateISO: String?
        /// Priority level: 0 = none, 1 = low, 2 = medium, 3 = high
        var priority: Int?
        /// Repeating pattern: "daily", "weekly", "monthly", or "yearly"
        var repeating: String?
        /// List hint extracted from hashtags (e.g., "shopping" from #shopping)
        var listHint: String?
    }

    /// Structured response from the on-device model for chat messages
    @Generable
    struct ChatResponseSchema {
        /// The text response to show the user
        var response: String
        /// Actions to perform (each is a JSON-like string: "create:title", "complete:taskId", "update:taskId:field:value")
        var actions: [String]
    }

    // MARK: - Chat Processing

    private func _processChatMessage(_ message: String) async -> String? {
        do {
            // Build task context from local data
            let tasks = TaskService.shared.tasks
            let incompleteTasks = tasks.filter { !$0.completed }
            let taskSummary = incompleteTasks.prefix(30).map { task in
                let priorityLabel = ["none", "!", "!!", "!!!"][min(task.priority.rawValue, 3)]
                let due = task.dueDateTime.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "no due date"
                return "- ![" + task.title + "](" + task.id + ") \(priorityLabel) (\(due))"
            }.joined(separator: "\n")

            let completedCount = tasks.filter { $0.completed }.count
            let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .short)

            // Build list context
            let lists = ListService.shared.lists.filter { $0.isVirtual != true }
            let listSummary = lists.prefix(15).map { list in
                return "- #[" + list.name + "](" + list.id + ")"
            }.joined(separator: "\n")

            let session = LanguageModelSession(
                instructions: """
                You are Astrid, a helpful task management assistant running on-device. \
                Keep responses concise and friendly. Current date/time: \(today)

                ## How to reference things in your responses
                Always refer to tasks, lists, and people by name using linked references — never show raw IDs.
                - Reference a task: ![Task Title](taskId) — e.g. ![Buy groceries](def-456)
                - Reference a list: #[List Name](listId) — e.g. #[Shopping](abc-123)
                - Mention a person: @[Name](userId) — e.g. @[Jon](cmeje-123)

                ## Priority levels
                0 = none, 1 = low (!), 2 = medium (!!), 3 = high/urgent (!!!)

                ## Current tasks (\(incompleteTasks.count) incomplete, \(completedCount) completed)
                \(taskSummary.isEmpty ? "No incomplete tasks." : taskSummary)

                ## Lists
                \(listSummary.isEmpty ? "No lists." : listSummary)

                ## Actions
                You can take actions by including them in the "actions" array:
                - Create a task: "create:Buy groceries" or "create:Buy groceries:priority:2:due:2026-04-03T17:00:00"
                - Complete a task: "complete:<taskId>"
                - Update priority: "update:<taskId>:priority:3"
                - Update title: "update:<taskId>:title:New title"

                Only take actions the user explicitly asked for. Don't assume intent — if the user asks \
                a question, answer it. If they ask you to do something, do it. When unsure, ask first. \
                Always confirm what you did in your response text.
                """
            )

            let result = try await session.respond(
                to: message,
                generating: ChatResponseSchema.self
            )

            // Execute any actions the model requested
            for action in result.content.actions {
                await executeAction(action)
            }

            let responseText = result.content.response
            logger.notice("On-device chat: \(result.content.actions.count) actions, response: \(responseText.prefix(80))")
            return responseText
        } catch {
            logger.error("On-device chat processing failed: \(error.localizedDescription)")
            return "I had trouble processing that on-device. Please try again."
        }
    }

    /// Execute a structured action string from the model
    private func executeAction(_ action: String) async {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count >= 2 else { return }

        let verb = parts[0].lowercased().trimmingCharacters(in: .whitespaces)
        let rest = parts[1].trimmingCharacters(in: .whitespaces)

        switch verb {
        case "create":
            await executeCreateAction(rest)
        case "complete":
            await executeCompleteAction(rest)
        case "update":
            await executeUpdateAction(rest)
        default:
            logger.warning("Unknown action verb: \(verb)")
        }
    }

    private func executeCreateAction(_ spec: String) async {
        // Parse "title" or "title:priority:2:due:2026-04-03T17:00:00"
        let segments = spec.split(separator: ":", maxSplits: 10).map(String.init)
        let title = segments.first ?? spec
        var priority: Int?
        var dueDate: Date?

        var i = 1
        while i < segments.count - 1 {
            let key = segments[i].lowercased().trimmingCharacters(in: .whitespaces)
            let value = segments[i + 1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "priority":
                priority = Int(value)
            case "due":
                dueDate = parseISODate(value)
            default:
                break
            }
            i += 2
        }

        do {
            let task = try await TaskService.shared.createTask(
                listIds: [],
                title: title,
                priority: priority,
                whenDate: dueDate,
                assigneeId: AuthManager.shared.userId,
                isPrivate: true,
                repeating: "never"
            )
            logger.notice("On-device AI created task: \(task.title)")
        } catch {
            logger.error("On-device AI failed to create task: \(error.localizedDescription)")
        }
    }

    private func executeCompleteAction(_ taskId: String) async {
        let id = taskId.trimmingCharacters(in: .whitespaces)
        do {
            // Use completeTask (not updateTask) so repeating patterns roll
            // forward via RepeatingTaskCalculator — the canonical path. Pass
            // task: so rollover anchors on real state, not cache freshness.
            let task = TaskService.shared.tasks.first { $0.id == id }
            _ = try await TaskService.shared.completeTask(id: id, completed: true, task: task)
            logger.notice("On-device AI completed task: \(id)")
        } catch {
            logger.error("On-device AI failed to complete task \(id): \(error.localizedDescription)")
        }
    }

    private func executeUpdateAction(_ spec: String) async {
        // Parse "taskId:field:value"
        let segments = spec.split(separator: ":", maxSplits: 4).map(String.init)
        guard segments.count >= 3 else { return }

        let taskId = segments[0].trimmingCharacters(in: .whitespaces)
        let field = segments[1].lowercased().trimmingCharacters(in: .whitespaces)
        let value = segments[2].trimmingCharacters(in: .whitespaces)

        do {
            switch field {
            case "priority":
                if let p = Int(value) {
                    _ = try await TaskService.shared.updateTask(taskId: taskId, priority: p)
                }
            case "title":
                _ = try await TaskService.shared.updateTask(taskId: taskId, title: value)
            case "completed":
                // MUST route completion through completeTask, never
                // updateTask(completed:), or repeating tasks skip rollover
                // (CLAUDE.md canonical-control-point rule). Pass task: so
                // rollover anchors on real state.
                let task = TaskService.shared.tasks.first { $0.id == taskId }
                _ = try await TaskService.shared.completeTask(
                    id: taskId, completed: value == "true", task: task)
            default:
                logger.warning("Unknown update field: \(field)")
                return
            }
            logger.notice("On-device AI updated task \(taskId) \(field)=\(value)")
        } catch {
            logger.error("On-device AI failed to update task \(taskId): \(error.localizedDescription)")
        }
    }

    // MARK: - Task Parsing

    private func _parseTask(_ input: String) async -> AITaskParseResult? {
        do {
            let session = LanguageModelSession(
                instructions: """
                You are a task management assistant. Parse the user's natural language input into structured task data.
                Extract: a clean title (remove date/priority/repeating keywords), due date (as ISO 8601), \
                priority (0=none, 1=low, 2=medium, 3=high), repeating pattern, and any list hints from #hashtags.
                Only include fields you can confidently extract. For dates, interpret relative terms like \
                "today", "tomorrow", "next week" relative to the current time.
                """
            )

            let response = try await session.respond(
                to: input,
                generating: TaskParseSchema.self
            )

            let result = response.content
            let dueDate = result.dueDateISO.flatMap { parseISODate($0) }

            var priority = result.priority
            if let p = priority, p < 0 || p > 3 { priority = nil }

            let validRepeating = ["daily", "weekly", "monthly", "yearly"]
            let repeating = result.repeating.flatMap { validRepeating.contains($0.lowercased()) ? $0.lowercased() : nil }

            logger.notice("Parsed task: title='\(result.title)', dueDate=\(dueDate?.description ?? "nil"), priority=\(priority ?? -1)")

            return AITaskParseResult(
                title: result.title.isEmpty ? input : result.title,
                description: result.description,
                dueDate: dueDate,
                priority: priority,
                repeating: repeating,
                listHint: result.listHint
            )
        } catch {
            logger.error("Foundation Model task parsing failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func parseISODate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: iso)
    }
}
#endif
