import SwiftUI

// MARK: - 1. 核心显示状态
enum DeviceDisplayState: Equatable {
	case disconnected       // 未连接 (无 UserDefaults 数据)
	case connecting         // 连接中 (有数据，正在自动重连)
	case connectionFailed   // 连接失败 (有数据，但连接断开)
	case initializing(targetDate: Date, lifeMinutes: Int)  // 初始化/水化 (计算出的剩余秒数)
	case running(DeviceDataModel) // 正常运行 (显示数值)
}

// MARK: - 2. 尿酸状态逻辑
enum Gender {
	case male, female
}

enum UricAcidStatus {
	case normal, high, low

	static func from(value: Double, gender: Gender = .male) -> UricAcidStatus {
		let highThreshold = (gender == .male) ? 416.0 : 368.0
		let lowThreshold = (gender == .male) ? 208.0 : 149.0
		
		if value > highThreshold { return .high }
		if value < lowThreshold { return .low }
		return .normal
	}

	var color: Color {
		switch self {
		case .normal: return .black
		case .high: return .red
		case .low: return .orange
		}
	}

	var icon: String {
		switch self {
		case .normal: return "checkmark.circle.fill"
		case .high: return "exclamationmark.triangle.fill"
		case .low: return "sun.min.fill"
		}
	}

	var title: String {
		switch self {
		case .normal: return "尿酸值正常"
		case .high: return "高尿酸"
		case .low: return "低尿酸"
		}
	}
}

// MARK: - 3. 设备数据模型
struct DeviceDataModel: Equatable {
	let serialNumber: String
	let value: Double
	let date: Date
	let batteryDays: Int // This was previously named batteryDays, but it's really the raw value from device. Let's keep it or rename.
    let lifeMinutes: Int

	// 默认使用男性标准，后续可从 UserProfile 注入
	var status: UricAcidStatus { UricAcidStatus.from(value: value, gender: .male) }

	var valueString: String {
		if value >= 1000.0 { return "≥ 1000.0" }
		return String(format: "%.1f", value)
	}
    
    var displayLifeDays: Int {
        return lifeMinutes / 1440
    }
}
