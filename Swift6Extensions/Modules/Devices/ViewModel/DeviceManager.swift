import SwiftUI
import Combine
import CoreBluetooth
import BLEKit
import SwiftData

struct HistoryItem: Identifiable {
	let id = UUID()
	let timeString: String // 预先格式化好时间，避免滚动时重复计算
	let value: String      // 改为 String，显示原始小数位
	let status: String     // 正常/偏高/偏低
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

    // 缓存剩余寿命，以便在 initializing 状态下显示
    private var currentLifeMinutes: Int = 0
    
	private(set) var connectedPeripheral: CBPeripheral?
	private var cancellables = Set<AnyCancellable>()

	init() {
		// 1. 先初始化蓝牙监听
		setupBluetoothObservers()
		
		// 2. 初始化时直接读取状态，避免 UI 闪烁 (从 disconnected -> connecting)
		if UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceID) != nil {
			self.displayState = .connecting
		}
	}
	
	// 处理历史数据 (接收 @Query 结果)
	func processHistoryData(_ rawData: [UricAcidData]) {
		self.isLoading = true
		
		Task.detached(priority: .userInitiated) {
			let calendar = Calendar.current
			let dayFormatter = DateFormatter()
			dayFormatter.dateFormat = "yyyy-MM-dd"
			
			let timeFormatter = DateFormatter()
			timeFormatter.dateFormat = "HH:mm"
			
			// 按天分组
			let groupedDict = Dictionary(grouping: rawData) { item in
				dayFormatter.string(from: item.timestamp)
			}
			
			// 对日期键进行降序排序
			let sortedKeys = groupedDict.keys.sorted(by: >)
			
			var resultDays: [HistoryDay] = []
			
			for dateKey in sortedKeys {
				guard let itemsInDay = groupedDict[dateKey] else { continue }
				
				// 天内的记录按时间降序
				let sortedItems = itemsInDay.sorted { $0.timestamp > $1.timestamp }
				
				let historyItems = sortedItems.map { data in
					HistoryItem(
						timeString: timeFormatter.string(from: data.timestamp),
						value: String(format: "%.1f", data.value), // 关键：保留原始小数显示
						status: data.status
					)
				}
				
				// 今天?
				let isToday = dateKey == dayFormatter.string(from: Date())
				let displayDate = isToday ? "今天 (\(dateKey))" : dateKey
				
				resultDays.append(HistoryDay(
					dateString: displayDate,
					items: historyItems,
					isExpanded: isToday // 默认展开今天
				))
			}
			
			await MainActor.run { [resultDays] in
				self.historyData = resultDays
				self.isLoading = false
			}
		}
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

				if secondsLeft == 0 {
					// 水化结束或无需水化，清除记录
					print("💧 [DeviceManager] 握手成功/水化完成")
					UserDefaults.standard.removeObject(forKey: AppConstants.Keys.hydrationStart)
					
					// ⚠️ 注意：不要在这里强行设为 0.0，否则会覆盖刚同步好的历史数据
					// 正确的数值显示交由 DeviceMainScreen 的 refreshUI() 和 updateDisplayValue() 处理
					
				} else {
					// 水化进行中
					let targetDate = Date().addingTimeInterval(TimeInterval(secondsLeft))
					withAnimation {
                        // 使用缓存的 lifeMinutes
						self.displayState = .initializing(targetDate: targetDate, lifeMinutes: self.currentLifeMinutes)
					}
					UserDefaults.standard.set(Date(), forKey: AppConstants.Keys.hydrationStart)
				}
			}
			.store(in: &cancellables)

        // 监听握手完成，更新剩余寿命
        BluetoothManager.shared.handshakeFinishedPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (maxSN, startTime, lifeMinutes) in
                guard let self = self else { return }
                self.currentLifeMinutes = lifeMinutes
                
                // 如果当前是 initializing 状态，更新 lifeMinutes
                if case .initializing(let targetDate, _) = self.displayState {
                    withAnimation {
                        self.displayState = .initializing(targetDate: targetDate, lifeMinutes: lifeMinutes)
                    }
                }
            }
            .store(in: &cancellables)

		BluetoothManager.shared.valuePublisher
			.receive(on: RunLoop.main)
			.sink { [weak self] (value, sn, dataSN, timestamp, lifeMinutes) in
				guard let self = self else { return }

				// 清除水化状态
				UserDefaults.standard.removeObject(forKey: AppConstants.Keys.hydrationStart)
                
                // 更新缓存
                self.currentLifeMinutes = lifeMinutes

				withAnimation {
					self.displayState = .running(DeviceDataModel(
						serialNumber: sn,
						value: value,
						date: timestamp, 
						batteryDays: 0,
                        lifeMinutes: lifeMinutes
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
		self.connectedPeripheral = peripheral

		UserDefaults.standard.set(device.id.uuidString, forKey: AppConstants.Keys.lastDeviceID)
		UserDefaults.standard.set(device.name, forKey: AppConstants.Keys.lastDeviceName)

		withAnimation {
			if let hydrationStart = UserDefaults.standard.object(forKey: AppConstants.Keys.hydrationStart) as? Date {
				let elapsed = Date().timeIntervalSince(hydrationStart)
				let remaining = AppConstants.Config.hydrationDuration - elapsed
				if remaining > 0 {
					let targetDate = Date().addingTimeInterval(remaining)
                    // 连接恢复时，lifeMinutes 暂时未知，设为 0
					self.displayState = .initializing(targetDate: targetDate, lifeMinutes: 0)
					return
				}
			}
			
			// 🔥 只要连接成功，直接显示运行状态（默认值 0.0）
			self.displayState = .running(DeviceDataModel(
				serialNumber: device.name,
				value: 0.0,
				date: Date(),
				batteryDays: 0,
                lifeMinutes: 0
			))
		}
	}

	func disconnect(isUserAction: Bool = true) {
		if isUserAction {
			BluetoothManager.shared.disconnect()

			// 只有用户主动断开才清除记忆，意外断开保留 ID 以便重连
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.lastDeviceID)
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.lastDeviceName)
			UserDefaults.standard.removeObject(forKey: AppConstants.Keys.hydrationStart)
            
            self.connectedPeripheral = nil
            withAnimation {
                self.displayState = .disconnected
            }
		} else {
            // 意外断开
            self.connectedPeripheral = nil
            
            // 如果有历史设备记录，尝试自动重连
            if UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceID) != nil {
                print("⚠️ [DeviceManager] 意外断开，尝试自动重连...")
                withAnimation {
                    self.displayState = .connecting
                }
                // 延迟一下再重连，避免频繁抖动
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.loadState()
                }
            } else {
                withAnimation {
                    self.displayState = .disconnected
                }
            }
        }
	}
	
	func clearMemoryState() {
		self.historyData = []
		self.isLoading = false
		print("🧹 [DeviceManager] 内存状态已重置")
	}
	
	/// 更新首页 Header 显示的数值
	func updateDisplayValue(_ value: Double, sn: String, date: Date = Date(), lifeMinutes: Int = 0) {
		Task { @MainActor in
			// 如果已断开或连接失败，则不更新 UI
			if case .disconnected = self.displayState { return }
			if case .connectionFailed = self.displayState { return }
			
			// 无论当前是 connecting, initializing 还是 running，只要有数据且未断开，就强制显示数据
			// 这样能确保历史同步完成后，Header 立即显示最后一条历史数据
			withAnimation {
				self.displayState = .running(DeviceDataModel(
					serialNumber: sn,
					value: value,
					date: date, // 使用真实的数据时间
					batteryDays: 0,
                    lifeMinutes: lifeMinutes
				))
			}
		}
	}
}
