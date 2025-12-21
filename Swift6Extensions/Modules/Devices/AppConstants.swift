//
//  AppConstants.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//

//
//  AppInfrastructure.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//

import Foundation
import CoreBluetooth

enum AppConstants {
	enum Keys {
		static let lastDeviceID = "LastConnectedDeviceID"
		static let lastDeviceName = "LastConnectedDeviceName"
		static let hydrationStart = "HydrationStartTime"
	}

	enum Config {
		static let hydrationDuration: TimeInterval = 15
	}
}

// MARK: - 2. 设备模型 (ScannedDeviceModal.swift)
struct ScannedDevice: Identifiable, Equatable, Hashable {
	let id: UUID
	let name: String
	let rssi: Int
	let serviceUUIDs: [String]

	var uuidString: String { id.uuidString }

	init(id: UUID = UUID(), name: String, rssi: Int, serviceUUIDs: [String] = []) {
		self.id = id
		self.name = name
		self.rssi = rssi
		self.serviceUUIDs = serviceUUIDs
	}

	// 实现 Hashable 以便在 Set 或字典中使用
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: ScannedDevice, rhs: ScannedDevice) -> Bool {
		return lhs.id == rhs.id &&
		lhs.name == rhs.name &&
		lhs.rssi == rhs.rssi
	}
}
