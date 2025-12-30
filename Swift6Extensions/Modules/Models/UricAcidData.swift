import Foundation
import SwiftData

@Model
final class UricAcidData {
    var id: UUID
    var value: Double
    var timestamp: Date
    var serialNumber: String // Keeping string for display/compatibility
    @Attribute(.unique) var sn: Int // Numeric serial number for logic/sorting, unique
    var status: String // "normal", "high", "low"
    var lifeMinutes: Int = 0
    
    init(id: UUID = UUID(), value: Double, timestamp: Date, serialNumber: String, sn: Int, lifeMinutes: Int = 0) {
        self.id = id
        self.value = value
        self.timestamp = timestamp
        self.serialNumber = serialNumber
        self.sn = sn
        self.lifeMinutes = lifeMinutes
        self.status = UricAcidData.calculateStatus(value: value)
    }
    
    static func calculateStatus(value: Double) -> String {
        // 男性标准
        if value > 416 { return "偏高" }
        if value < 208 { return "偏低" }
        return "正常"
    }
}
