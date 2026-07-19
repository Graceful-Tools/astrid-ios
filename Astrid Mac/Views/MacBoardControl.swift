//  MacBoardControl.swift
//  Astrid for Mac — pure board enable/disable state (Task 9e7f37d4). A list has a board iff it's
//  attached to a project.

#if os(macOS)
import Foundation

enum MacBoardControl {
    static func isEnabled(projectId: String?) -> Bool {
        !(projectId ?? "").isEmpty
    }
}
#endif
