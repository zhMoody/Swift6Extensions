import Foundation
import CoreBluetooth
import BLEKit
import Combine
import SwiftUI

// MARK: - 1. 自定义包装结构体 (绕过 BLEKit 的 Internal 限制)
struct DiscoveredPeripheral: Identifiable, Equatable {
	let peripheral: Peripheral
	let rssi: Int
	let advertisementData: [String: Any] // 保存原始字典
	
	var id: UUID { peripheral.id }
	
	static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
		lhs.id == rhs.id
	}
}

/// 蓝牙底层管理单例
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
	
	static let shared = BluetoothManager()
	
	// MARK: - Observable Properties
	
	// ⚠️ 变化点：这里发布的是我们自定义的包装对象，而不是纯 Peripheral
	@Published var discoveredPeripherals: [DiscoveredPeripheral] = []
	
	@Published var connectedPeripheral: Peripheral?
	@Published var centralState: CBManagerState = .unknown
	
	// MARK: - Publishers
	let valuePublisher = PassthroughSubject<(Double, String), Never>()
	let hydrationPublisher = PassthroughSubject<(Int, String), Never>()
	let connectionStatusPublisher = PassthroughSubject<Bool, Never>()
	
	// MARK: - Internals
	private let central: CentralManager
	private var scanSet: Set<UUID> = []
	
	private override init() {
		self.central = CentralManager()
		super.init()
		self.central.delegate = self
		Task { try? await central.waitUntilReady() }
	}
	
	// MARK: - Public API
	
	func startScanning() {
		guard central.state == .poweredOn else { return }
		scanSet.removeAll()
		discoveredPeripherals.removeAll()
		central.scan(services: [], options: nil)
	}
	
	func stopScanning() {
		central.stopScan()
	}
	
	// 重连逻辑
	func tryReconnect(uuidString: String) async -> Bool {
		guard let uuid = UUID(uuidString: uuidString) else { return false }
		let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
		guard let targetPeripheral = peripherals.first else { return false }
		
		do {
			let _ = try await connect(to: targetPeripheral)
			return true
		} catch {
			return false
		}
	}
	
	func connect(to peripheral: Peripheral) async throws -> Peripheral {
		stopScanning()
		let p = try await central.connect(peripheral, timeout: 10.0)
		
		let services = try await p.discoverServices(nil)
		if let service = services.first {
			let characteristics = try await p.discoverCharacteristics(nil, for: service)
			if let char = characteristics.first {
				let _ = try await p.setNotifyValue(true, for: char)
			}
		}
		
		p.delegate = self
		self.connectedPeripheral = p
		connectionStatusPublisher.send(true)
		return p
	}
	
	func disconnect() {
		guard let p = connectedPeripheral else { return }
		Task {
			try? await central.cancelPeripheralConnection(p)
			self.connectedPeripheral = nil
			connectionStatusPublisher.send(false)
		}
	}
	
	// MARK: - 数据解析
	private func handleDeviceResponse(data: Data, peripheral: Peripheral) {
		let bytes = [UInt8](data)
		guard !bytes.isEmpty else { return }
		let sn = UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceName) ?? "JLUA-DEVICE"
		
		switch bytes[0] {
		case 0x04:
			if bytes.count > 1 {
				let secondsLeft = Int(bytes[1])
				hydrationPublisher.send((secondsLeft, sn))
			}
		case 0x05:
			let mockValue = 360.0
			valuePublisher.send((mockValue, sn))
		default:
			break
		}
	}
}

// MARK: - Delegate Implementations
extension BluetoothManager: CentralManagerDelegate {
	
	func centralManagerDidUpdateState(_ central: CentralManager) {
		self.centralState = central.state
	}
	
	func centralManager(_ central: CentralManager, didDiscover peripheral: Peripheral, advertisementData: UncheckedSendable<[String : Any]>, rssi RSSI: NSNumber) {
		guard !scanSet.contains(peripheral.id) else { return }
		scanSet.insert(peripheral.id)
		
		let rssiValue = RSSI.intValue
		let rawDict = advertisementData.value // UncheckedSendable.value 通常是 public 的
		
		let discoveredItem = DiscoveredPeripheral(
			peripheral: peripheral,
			rssi: rssiValue,
			advertisementData: rawDict
		)
		
		Task { @MainActor in
			withAnimation {
				self.discoveredPeripherals.append(discoveredItem)
			}
		}
	}
	
	func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) {}
	func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?) {}
	func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?) {
		if connectedPeripheral?.id == peripheral.id {
			Task { @MainActor in
				self.connectedPeripheral = nil
				self.connectionStatusPublisher.send(false)
			}
		}
	}
	func centralManager(_ central: CentralManager, willRestoreState dict: UncheckedSendable<[String : Any]>) {}
}

extension BluetoothManager: PeripheralDelegate {
	func peripheral(_ peripheral: Peripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard let data = characteristic.value else { return }
		handleDeviceResponse(data: data, peripheral: peripheral)
	}
}
