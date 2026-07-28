//  MacTimerSection.swift
//  Astrid for Mac — when the timer is worth showing (Task b2785c35).
//
//  The Timer sat under Comments on every task, offering 00:00:00 and a Start button whether or not
//  the task would ever be timed. iOS moved the timer into the comment footer and leaves only a
//  "last timer" caption in the body. Same idea here: the section appears while a timer is RUNNING,
//  starting one lives in the ⋮ menu, and a task with recorded time keeps a caption so hiding the
//  section never hides the data.

#if os(macOS)
import Foundation

enum MacTimerSection {
    static func showsSection(running: Bool) -> Bool { running }

    static func showsLoggedCaption(running: Bool, loggedSeconds: Int) -> Bool {
        !running && loggedSeconds > 0
    }

    static func offersStartInMenu(running: Bool) -> Bool { !running }
}
#endif
