import SwiftUI
import Combine
import CoreBluetooth
import BLEKit

@MainActor
class BleScannerViewModel: ObservableObject {
	@Published var foundDevices: [ScannedDevice] = []
	@Published var isScanning = false
	@Published var targetDeviceId: UUID? = nil
	@Published var connectionState: ConnectionState = .idle

	private let bluetoothManager = BluetoothManager.shared
	private var cancellables = Set<AnyCancellable>()

	private var peripheralMap: [UUID: DiscoveredPeripheral] = [:]

	var isGlobalLocked: Bool {
		return connectionState == .connecting || connectionState == .connected
	}

	init() {
		bluetoothManager.$discoveredPeripherals
			.receive(on: RunLoop.main)
			.sink { [weak self] items in
				self?.updateList(from: items)
			}
			.store(in: &cancellables)
	}

	func startScanning() {
		guard !isScanning else { return }
		isScanning = true
		foundDevices = []
		peripheralMap.removeAll()
		bluetoothManager.startScanning()
	}

	func stopScanning() {
		isScanning = false
		bluetoothManager.stopScanning()
	}

	private func updateList(from items: [DiscoveredPeripheral]) {
		for item in items {
			peripheralMap[item.id] = item

			let rssiVal = item.rssi

			var uuids: [String] = []
			if let serviceUUIDs = item.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
				uuids = serviceUUIDs.map { $0.uuidString }
			}

			let devName = item.peripheral.name ?? (item.advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown Device"

			let newDevice = ScannedDevice(
				id: item.id,
				name: devName,
				rssi: rssiVal,
				serviceUUIDs: uuids
			)

			if !foundDevices.contains(where: { $0.id == newDevice.id }) {
				withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
					foundDevices.append(newDevice)
				}
			} else {
				if let index = foundDevices.firstIndex(where: { $0.id == newDevice.id }) {
					if foundDevices[index].rssi != rssiVal {
						foundDevices[index] = newDevice
					}
				}
			}
		}
	}

	func connect(to device: ScannedDevice, onSuccess: @escaping (ScannedDevice, CBPeripheral?) -> Void) {
		guard let targetWrapper = peripheralMap[device.id] else {
			self.connectionState = .failed
			return
		}

		withAnimation {
			self.targetDeviceId = device.id
			self.connectionState = .connecting
		}
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()

		Task {
			do {
				let connectedP = try await bluetoothManager.connect(to: targetWrapper.peripheral)
				await MainActor.run {
					withAnimation {
						self.connectionState = .connected
						UINotificationFeedbackGenerator().notificationOccurred(.success)

						DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
							onSuccess(device, connectedP.cbPeripheral)
							self.resetState()
						}
					}
				}
			} catch {
				await MainActor.run {
					self.connectionState = .failed
					UINotificationFeedbackGenerator().notificationOccurred(.error)
					print("Connect failed: \(error)")
				}
			}
		}
	}

	func resetState() {
		self.targetDeviceId = nil
		self.connectionState = .idle
	}
}
