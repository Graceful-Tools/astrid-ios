//  CoreCommands.swift
//  The commands the services send astrid-core, typed so a call site cannot misspell a kind or a
//  field. Each is `astrid_core::app::Command`'s variant of the same name; the wire is its contract.

import AstridCore
import Foundation

/// An edit to a task: the fields to change, `null` for the ones to clear.
typealias TaskEdit = CoreFields

extension TaskEdit {
    /// Every field an `UpdateTaskRequest` carries, as it would send them to the server.
    init(request: UpdateTaskRequest) {
        self = (try? CoreFields(encoding: request)) ?? CoreFields()
    }
}

extension CoreCommand {
    init(kind: String, taskId: String) {
        self.init(kind: kind, ["taskId": .value(taskId)])
    }

    /// Cached tasks in the wire shape: every one, or the named ones.
    static func tasks(ids: [String]? = nil) -> CoreCommand {
        var command = CoreCommand(kind: "tasks")
        command.set("ids", ids)
        return command
    }

    /// Which real ids these temporary ones became.
    static func resolveIds(_ ids: [String]) -> CoreCommand {
        CoreCommand(kind: "resolveIds", ["ids": .value(ids)])
    }

    // swiftlint:disable:next function_parameter_count
    static func createTask(
        title: String, description: String?, listIds: [String], priority: Int?,
        dueDateTime: String?, isAllDay: Bool, assigneeId: String?, parentTaskId: String?,
        statusRole: String?, repeating: String?, repeatingData: CustomRepeatingPattern?,
        isPrivate: Bool?
    ) -> CoreCommand {
        var command = CoreCommand(kind: "createTask", ["title": .value(title), "listIds": .value(listIds)])
        command.set("description", description)
        command.set("priority", priority)
        command.set("dueDateTime", dueDateTime)
        command.set("isAllDay", isAllDay)
        command.set("assigneeId", assigneeId)
        command.set("parentTaskId", parentTaskId)
        command.set("statusRole", statusRole)
        command.set("repeating", repeating)
        command.set("repeatingData", repeatingData)
        command.set("isPrivate", isPrivate)
        // The app decided its own defaults before calling (NewTaskDefaults); the core must not
        // apply the list's a second time, least of all to a sync provider's import.
        command.set("applyListDefaults", false)
        return command
    }

    static func updateTask(taskId: String, changes: TaskEdit) -> CoreCommand {
        CoreCommand(kind: "updateTask", ["taskId": .value(taskId), "changes": .value(changes)])
    }

    // swiftlint:disable:next function_parameter_count
    static func completeTask(
        taskId: String, completed: Bool, task: Task?, timerDuration: Int?, lastTimerValue: String?,
        completedAt: String?, source: String?
    ) -> CoreCommand {
        var command = CoreCommand(kind: "completeTask", ["taskId": .value(taskId), "completed": .value(completed)])
        command.set("task", task)
        command.set("timerDuration", timerDuration)
        command.set("lastTimerValue", lastTimerValue)
        command.set("completedAt", completedAt)
        command.set("source", source)
        return command
    }
}
