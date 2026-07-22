//  MacDetailChrome.swift
//  Astrid for Mac — the task-details surface is a WHITE card (like Astrid Web), except in Dark
//  theme where a white card would make the (white) text unreadable — there it uses the dark
//  surface. Text stays readable in every theme because Theme.textPrimary resolves per theme.

#if os(macOS)
import SwiftUI

enum MacDetailChrome {
    static var background: Color {
        (UserDefaults.standard.string(forKey: "themeMode") ?? "ocean") == "dark"
            ? Theme.Dark.bgSecondary
            : .white
    }
}
#endif
