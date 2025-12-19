//
//  Project: Swift6Extensions
//  File: Swift6ExtensionsApp.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  
//

import SwiftUI
import SwiftData

@main
struct Swift6ExtensionsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
          TabView {
            DeviceMainScreen()
              .tabItem {
                Label("设备",systemImage: "flame.circle.fill")
              }
            
            ContentView()
              .tabItem {
                Label("数据",systemImage: "flame.circle.fill")
              }
          }
          
        }
        .modelContainer(sharedModelContainer)
    }
}
