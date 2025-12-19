//
//  Project: Swift6Extensions
//  File: Item.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
