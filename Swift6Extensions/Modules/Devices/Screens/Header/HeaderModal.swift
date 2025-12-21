import SwiftUI

// MARK: - 1. 核心显示状态
enum DeviceDisplayState: Equatable {
	case disconnected       // 未连接 (无 UserDefaults 数据)
	case connecting         // 连接中 (有数据，正在自动重连)
	case connectionFailed   // 连接失败 (有数据，但连接断开)
	case initializing(targetDate: Date)  // 初始化/水化 (计算出的剩余秒数)
	case running(DeviceDataModel) // 正常运行 (显示数值)
}

// MARK: - 2. 尿酸状态逻辑
enum UricAcidStatus {
	case normal, high, low, outOfRangeLow, outOfRangeHigh

	static func from(value: Double) -> UricAcidStatus {
		if value <= 0.5 { return .outOfRangeLow }
		if value >= 1000.0 { return .outOfRangeHigh }
		if value < 150 { return .low }
		if value > 360 { return .high }
		return .normal
	}

	var color: Color {
		switch self {
		case .normal: return .exSuccess
		case .high, .outOfRangeHigh: return .exFail
		case .low, .outOfRangeLow: return .orange
		}
	}

	var icon: String {
		switch self {
		case .normal: return "checkmark.circle.fill"
		case .high: return "exclamationmark.triangle.fill"
		case .low: return "sun.min.fill"
		case .outOfRangeLow, .outOfRangeHigh: return "exclamationmark.circle.fill"
		}
	}

	var title: String {
		switch self {
		case .normal: return "尿酸值正常"
		case .high: return "高尿酸预警"
		case .low: return "低尿酸预警"
		case .outOfRangeLow, .outOfRangeHigh: return "超监测范围"
		}
	}
}

// MARK: - 3. 设备数据模型
struct DeviceDataModel: Equatable {
	let serialNumber: String
	let value: Double
	let date: Date
	let batteryDays: Int

	var status: UricAcidStatus { UricAcidStatus.from(value: value) }

	var valueString: String {
		if value <= 0.5 { return "≤ 0.5" }
		if value >= 1000.0 { return "≥ 1000.0" }
		return String(format: "%.1f", value)
	}
}
