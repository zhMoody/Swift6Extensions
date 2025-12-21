import SwiftUI
import Combine
import CoreBluetooth
import BLEKit

@MainActor
class DeviceManager: ObservableObject {
	@Published var displayState: DeviceDisplayState = .disconnected

	private(set) var connectedPeripheral: CBPeripheral?
	private var cancellables = Set<AnyCancellable>()

	init() {
		setupBluetoothObservers()
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
					// 已经在倒计时中，可能不需要频繁更新 targetDate，
					// 除非偏差过大。这里简单处理：始终信任设备发来的最新时间。
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
