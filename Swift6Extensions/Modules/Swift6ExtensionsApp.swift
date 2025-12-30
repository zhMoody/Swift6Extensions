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
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: UricAcidData.self)
        } catch {
            print("❌ [SwiftData] Container init failed: \(error)")
            print("🧹 [SwiftData] Attempting to wipe database and recreate...")
            
            // 尝试删除旧数据库文件以恢复
            let fileManager = FileManager.default
            if let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dbUrl = supportDir.appendingPathComponent("default.store")
                let shmUrl = supportDir.appendingPathComponent("default.store-shm")
                let walUrl = supportDir.appendingPathComponent("default.store-wal")
                
                try? fileManager.removeItem(at: dbUrl)
                try? fileManager.removeItem(at: shmUrl)
                try? fileManager.removeItem(at: walUrl)
            }
            
            do {
                container = try ModelContainer(for: UricAcidData.self)
                print("✅ [SwiftData] Database reset successful.")
            } catch {
                fatalError("💀 [SwiftData] Critical Error: Failed to create container even after wipe. \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            DeviceMainScreen()
        }
        .modelContainer(container)
    }
}
