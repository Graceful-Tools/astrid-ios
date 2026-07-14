//
//  Astrid_TasksApp.swift
//  Astrid Tasks
//
//  Created by Jon Paris on 7/13/26.
//

import SwiftUI
import CoreData

@main
struct Astrid_TasksApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
