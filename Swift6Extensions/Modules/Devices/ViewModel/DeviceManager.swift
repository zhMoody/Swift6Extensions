import SwiftUI
import Combine
import CoreBluetooth
import BLEKit

struct HistoryItem: Identifiable {
	let id = UUID()
	let timeString: String // 预先格式化好时间，避免滚动时重复计算
	let value: Int
	let status: String // 模拟状态：正常/偏高/偏低
}

// 每一天的数据组 (Day Group)
struct HistoryDay: Identifiable {
	let id = UUID()
	let dateString: String // 显示如 "2025-12-21"
	var items: [HistoryItem]
	var isExpanded: Bool = false // 控制折叠状态
}

@MainActor
class DeviceManager: ObservableObject {
	@Published var displayState: DeviceDisplayState = .disconnected

	@Published var historyData: [HistoryDay] = []
	@Published var isLoading = true

	private(set) var connectedPeripheral: CBPeripheral?
	private var cancellables = Set<AnyCancellable>()

	init() {
		setupBluetoothObservers()
	}
	// Mock
	func generateData() async {
		guard historyData.isEmpty else { return }
		let generatedDays = await Task.detached(priority: .userInitiated) { () -> [HistoryDay] in
			var days: [HistoryDay] = []
			let calendar = Calendar.current
			let now = Date()
			let formatter = DateFormatter()
			formatter.dateFormat = "yyyy-MM-dd"

			let timeFormatter = DateFormatter()
			timeFormatter.dateFormat = "HH:mm"

			for dayOffset in 0..<15 {
				guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }

				var dailyItems: [HistoryItem] = []
				for i in 0..<720 {
					let totalMinutes = 24 * 60 - (i * 2)
					let hours = totalMinutes / 60
					let minutes = totalMinutes % 60
					let timeStr = String(format: "%02d:%02d", hours, minutes)

					// 模拟数值波动
					let value = Int.random(in: 60...140)
					let status = value > 120 ? "偏高" : (value < 70 ? "偏低" : "正常")

					dailyItems.append(HistoryItem(timeString: timeStr, value: value, status: status))
				}

				let dayModel = HistoryDay(
					dateString: dayOffset == 0 ? "今天 (\(formatter.string(from: date)))" : formatter.string(from: date),
					items: dailyItems,
					isExpanded: dayOffset == 0
				)
				days.append(dayModel)
			}
			return days
		}.value

		self.historyData = generatedDays
		self.isLoading = false
	}

	private func setupBluetoothObservers() {
		BluetoothManager.shared.connectionStatusPublisher
			.receive(on: RunLoop.main)
			.sink { [weak self] isConnected in
				if !isConnected {
					self?.disconnect(isUserAction: false)
				}
			}
			.store(in: &cancellables)

		BluetoothManager.shared.hydrationPublisher
			.receive(on: RunLoop.main)
			.sink { [weak self] (secondsLeft, sn) in
				guard let self = self else { return }

				let targetDate = Date().addingTimeInterval(TimeInterval(secondsLeft))

				if case .initializing = self.displayState {
				}

				withAnimation {
					self.displayState = .initializing(targetDate: targetDate)
				}

				UserDefaults.standard.set(Date(), forKey: AppConstants.Keys.hydrationStart)
			}
			.store(in: &cancellables)

		BluetoothManager.shared.valuePublisher
			.receive(on: RunLoop.main)
			.sink { [weak self] (value, sn) in
				guard let self = self else { return }

				// 清除水化状态
				UserDefaults.standard.removeObject(forKey: AppConstants.Keys.hydrationStart)

				withAnimation {
					self.displayState = .running(DeviceDataModel(
						serialNumber: sn,
						value: value,
						date: Date(),
						batteryDays: 10
					))
				}
			}
			.store(in: &cancellables)
	}

	func loadState() {
		guard let lastID = UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceID) else {
			self.displayState = .disconnected
			return
		}

		if let current = BluetoothManager.shared.connectedPeripheral,
			 current.id.uuidString == lastID {
			return
		}

		self.displayState = .connecting

		Task {
			// 调用刚才新增的重连方法
			let success = await BluetoothManager.shared.tryReconnect(uuidString: lastID)

			// 必须回到主线程更新 UI
			await MainActor.run {
				if !success {
					self.displayState = .connectionFailed
				} else {
					print("重连指令发送成功")
				}
			}
		}
	}

	func handleConnectSuccess(device: ScannedDevice, peripheral: CBPeripheral?, needHydration: Bool) {
		// 1. 保存引用
		self.connectedPeripheral = peripheral

		// 2. 持久化
		UserDefaults.standard.set(device.id.uuidString, forKey: AppConstants.Keys.lastDeviceID)
		UserDefaults.standard.set(device.name, forKey: AppConstants.Keys.lastDeviceName)

		withAnimation {
			self.displayState = .connecting
		}
	}

	func disconnect(isUserAction: Bool = true) {
		if isUserAction {
			BluetoothManager.shared.disconnect()

			// 只有用户主动断开才清除记忆，意外断开保留 ID 以便重连
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.lastDeviceID)
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.lastDeviceName)
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.hydrationStart)
		}

		self.connectedPeripheral = nil

		withAnimation {
			self.displayState = .disconnected
		}
	}
}
