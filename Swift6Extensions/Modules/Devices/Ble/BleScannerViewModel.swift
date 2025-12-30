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
    connectionState == .connecting || connectionState == .connected
  }

  private func parseDeviceDisplayName(rawName: String, advertisementData: [String: Any]) -> String {
    let upperName = rawName.uppercased()

    guard upperName.hasPrefix("JL") else { return rawName }

    let typeName: String
    if upperName.contains("LA") {
      typeName = "乳酸"
    } else if upperName.contains("GM") {
      typeName = "血糖"
    } else if upperName.contains("UA") {
      typeName = "尿酸"
    } else {
      typeName = "设备"
    }

    var serialNumber = ""

    if let manuData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
      serialNumber = manuData.map { String(format: "%02X", $0) }.joined()
    }

    if serialNumber.isEmpty {
      let components = rawName.split(separator: "-")
      if components.count > 1, let last = components.last {
        let lastStr = String(last)
        serialNumber = lastStr.count > 12 ? String(lastStr.dropFirst(12)) : lastStr
      } else {
        serialNumber = String(rawName.suffix(4))
      }
    }

    return "捷鹿\(typeName)-\(String(serialNumber.suffix(4)))"
  }
  // MARK: - Init
  init() {
    // 监听底层扫描到的设备
    bluetoothManager.$discoveredPeripherals
      .receive(on: RunLoop.main)
      .sink { [weak self] items in
        guard let self = self else { return }
        
        // 🔥🔥🔥 [关键修复] 更新设备映射缓存 🔥🔥🔥
        // 必须把底层对象存入 Map，否则 connect 方法找不到真实的蓝牙对象，点击就会没反应
        items.forEach { self.peripheralMap[$0.id] = $0 }
        
        // -------------------------------------------------
        // 下面是你提供的原有逻辑，完全保持不变
        // -------------------------------------------------
        
        // 1. 过滤 & 转换
        let processedDevices: [ScannedDevice] = items.compactMap { item in
          
          // 获取原始名称
          let rawName = item.peripheral.name ?? (item.advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
          
          // 🔍 过滤逻辑：必须包含 "JL" (忽略大小写)
          guard rawName.uppercased().contains("JL") else { return nil }
          
          // 🛠 解析中文名称
          let displayName = self.parseDeviceDisplayName(rawName: rawName, advertisementData: item.advertisementData)
          
          // 获取 RSSI 和 UUIDs
          let rssiVal = item.rssi
          var uuids: [String] = []
          if let serviceUUIDs = item.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            uuids = serviceUUIDs.map { $0.uuidString }
          }
          
          // 生成 UI 模型
          return ScannedDevice(
            id: item.id,
            name: displayName,
            rssi: rssiVal,
            serviceUUIDs: uuids
          )
        }
        
        // 日志验证
        if !processedDevices.isEmpty && processedDevices.count != self.foundDevices.count {
          print("✅ ViewModel 更新列表: \(processedDevices.map { $0.name })")
        }
        
        // 2. 更新列表 (带有去重和动画)
        self.updateUIList(newDevices: processedDevices)
      }
      .store(in: &cancellables)
  }

  private func updateUIList(newDevices: [ScannedDevice]) {
    for device in newDevices {
      // 如果列表里还没有这个设备，添加
      if !foundDevices.contains(where: { $0.id == device.id }) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
          foundDevices.append(device)
        }
      } else {
        // 如果已存在，仅更新信号强度或名称(如果名称会变的话)
        if let index = foundDevices.firstIndex(where: { $0.id == device.id }) {
          // 只有变化才更新，避免 UI 抖动
          if foundDevices[index].rssi != device.rssi || foundDevices[index].name != device.name {
            foundDevices[index] = device
          }
        }
      }
    }
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
        }
      }
    }
  }
  
  func resetState() {
    self.targetDeviceId = nil
    self.connectionState = .idle
  }
}
