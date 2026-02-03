//
//  MuscleMetricApp.swift
//  MuscleMetric
//
//  Created by iMac on 2026/1/30.
//

import SwiftUI
import CoreData

@main
struct MuscleMetricApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
