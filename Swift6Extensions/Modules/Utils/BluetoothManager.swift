import Foundation
import CoreBluetooth
import BLEKit
import Combine
import SwiftUI

// MARK: - 1. 包装结构体
struct DiscoveredPeripheral: Identifiable, Equatable {
  let peripheral: Peripheral
  let rssi: Int
  let advertisementData: [String: Any]
  
  var id: UUID { peripheral.id }
  
  static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
    lhs.id == rhs.id
  }
}

/// 蓝牙底层管理单例
/// 特性：后台线程运行、防阻塞、支持自定义协议解析
@MainActor
final class BluetoothManager: NSObject, ObservableObject {
  
  static let shared = BluetoothManager()
  
  // MARK: - Observable Properties
  @Published var discoveredPeripherals: [DiscoveredPeripheral] = []
  @Published var connectedPeripheral: Peripheral?
  @Published var centralState: CBManagerState = .unknown
  
  // MARK: - Publishers (数据管道)
  /// 发送尿酸/血糖数值 (Value, DeviceName, DataSN, CalculatedDate, LifeMinutes)
  let valuePublisher = PassthroughSubject<(Double, String, Int, Date, Int), Never>()
  /// 发送水化/倒计时秒数 (Seconds, SN)
  let hydrationPublisher = PassthroughSubject<(Int, String), Never>()
  /// 握手完成 (CurrentMaxSN, DeviceStartTime, LifeMinutes)
  let handshakeFinishedPublisher = PassthroughSubject<(Int, Date, Int), Never>()
  /// 历史数据包 ([Item])
  let historyPublisher = PassthroughSubject<[UricAcidHistoryItem], Never>()
  /// 连接状态变更
  let connectionStatusPublisher = PassthroughSubject<Bool, Never>()
  
  // MARK: - Internals
  private let central: CentralManager
  private var scanSet: Set<UUID> = []
  
  // 设备状态缓存
  private var deviceStartTime: Date?
  private var currentMaxSN: Int = 0
  private var currentLifeMinutes: Int = 0
  
  // 标记是否希望扫描
  private var isScanningDesired = false
  // 专用串行队列，确保蓝牙操作不卡顿 UI
  private let bleQueue = DispatchQueue(label: "com.uric.ble.queue", qos: .userInitiated)
  
  private override init() {
    // 初始化：传入专用队列，避免主线程干扰
    // 添加 RestoreIdentifier 以消除 API MISUSE 警告
    let options: [String: Any] = [
      CBCentralManagerOptionRestoreIdentifierKey: "com.uric.ble.restore"
    ]
    let manager = CentralManager(delegate: nil, queue: bleQueue, options: options)
    self.central = manager
    super.init()
    
    self.central.delegate = self
    
    // 启动等待
    Task { try? await central.waitUntilReady() }
  }
  
  // MARK: - Public Intents (UI 调用)
  
  /// 主动查询设备状态 (发送 0x04)
  func queryDeviceStatus() {
    guard let p = connectedPeripheral,
          let service = p.services?.first(where: { $0.uuid == .URIC_ACID_SERVICE }),
          let characteristic = service.characteristics?.first(where: { $0.uuid == .URIC_ACID_CHARACTERISTIC }) else { return }
    
    print("🔄 [BluetoothManager] UI 请求: 查询设备状态 (0x04)")
    send04CommandInternal(to: p, characteristic: characteristic)
  }
  
  func startScanning() {
    print("🔵 [BluetoothManager] UI 请求: 开始扫描")
    isScanningDesired = true
    
    if central.state == .poweredOn {
      performScan()
    }
  }
  
  func stopScanning() {
    print("⚪️ [BluetoothManager] UI 请求: 停止扫描")
    isScanningDesired = false
    central.stopScan()
  }
  
  private func performScan() {
    scanSet.removeAll()
    discoveredPeripherals.removeAll()
    
    let options: [String: Any] = [
      CBCentralManagerScanOptionAllowDuplicatesKey: false
    ]
    
    print("🚀 [BluetoothManager] 开始扫描 (模式: 所有设备)")
    
    central.scanForPeripherals(withServices: nil, options: options)
  }
  
  // 重连逻辑
  func tryReconnect(uuidString: String) async -> Bool {
    guard let uuid = UUID(uuidString: uuidString) else { return false }
    let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
    guard let targetPeripheral = peripherals.first else { return false }
    do { let _ = try await connect(to: targetPeripheral); return true } catch { return false }
  }
  
  // 连接设备
  /// 连接指定外设并初始化协议流程
  ///
  /// **连接流程:**
  /// 1. 建立物理连接 (`central.connect`)
  /// 2. 发现尿酸服务 (18F1)
  /// 3. 发现特征值 (2AF1)
  /// 4. 开启 Notify 订阅
  /// 5. 发送 `0x04` 协议指令（同步时间/查询设备信息）
  /// 6. 设置代理监听后续数据
  func connect(to peripheral: Peripheral) async throws -> Peripheral {
    stopScanning()
    print("🔗 [BluetoothManager] 正在连接: \(peripheral.id)")
    
    // 1. 建立连接
    let p = try await central.connect(peripheral, timeout: 10.0)
    
    // 2. 🔥 精准发现服务: 只找 18F1
    let services = try await p.discoverServices([.URIC_ACID_SERVICE])
    guard let service = services.first else {
      print("❌ 未找到尿酸服务 (18F1)")
      throw NSError(domain: "BLEError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Service not found"])
    }
    
    // 3. 🔥 精准发现特征: 只找 2AF1
    let characteristics = try await p.discoverCharacteristics([.URIC_ACID_CHARACTERISTIC], for: service)
    guard let targetChar = characteristics.first else {
      print("❌ 未找到数据特征 (2AF1)")
      throw NSError(domain: "BLEError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Characteristic not found"])
    }
    
    print("✅ [BluetoothManager] 锁定特征: \(targetChar.uuid)")
    
    // 4. 开启通知 (订阅数据)
    // 即使它看起来像只读特征，只要协议说能订阅，我们就订阅
    if targetChar.properties.contains(.notify) || targetChar.properties.contains(.indicate) {
      let _ = try await p.setNotifyValue(true, for: targetChar)
      print("📡 [BluetoothManager] 已开启通知 (订阅)")
    } else {
      // 有些设备属性标得不对，强行订阅试试
      try await p.setNotifyValue(true, for: targetChar)
      print("⚠️ [BluetoothManager] 特征未标记Notify，已强制尝试订阅")
    }
    
    // 5. 发送 0x04 指令 (同步时间/查询信息)
    // 此时库的内部流程已走完，可以发送指令了
    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s 缓冲
    send04CommandInternal(to: p, characteristic: targetChar)
    
    // 🔥 最后再接管代理，处理后续的实时数据
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
  
  // MARK: - Protocol Helpers
  
  /// 发送 0x04 指令: App查询最新采样序号/同步时间
  ///
  /// **协议结构:**
  /// - Header: `D3 96`
  /// - Command: `04`
  /// - DeviceID: `06` (App端标识)
  /// - Content: `Timestamp` (4字节, Big Endian)
  /// - Checksum: `XOR` (从 Header 到 Content)
  private func send04CommandInternal(to p: Peripheral, characteristic: CBCharacteristic) {
    let now = Int(Date().timeIntervalSince1970)
    let timeBytes = [
      UInt8((now >> 24) & 0xFF),
      UInt8((now >> 16) & 0xFF),
      UInt8((now >> 8) & 0xFF),
      UInt8(now & 0xFF)
    ]
    // 06 为APP设备编号
    let content: [UInt8] = [0x06] + timeBytes
    let packet = buildPacket(type: 0x04, content: content)
    
    sendData(packet, to: p, characteristic: characteristic)
  }
  
  /// 发送 0x05 指令: 拉取历史数据
  /// 结构: D3 96 05 [StartSN 4 bytes] [Count 2 bytes] [Checksum]
  func send05Command(startSN: Int, count: Int) {
    guard let p = connectedPeripheral,
          let service = p.services?.first(where: { $0.uuid == .URIC_ACID_SERVICE }),
          let characteristic = service.characteristics?.first(where: { $0.uuid == .URIC_ACID_CHARACTERISTIC }) else { return }
    
    let snBytes = [
      UInt8((startSN >> 24) & 0xFF),
      UInt8((startSN >> 16) & 0xFF),
      UInt8((startSN >> 8) & 0xFF),
      UInt8(startSN & 0xFF)
    ]
    let countBytes = [
      UInt8((count >> 8) & 0xFF),
      UInt8(count & 0xFF)
    ]
    
    let content = snBytes + countBytes
    let packet = buildPacket(type: 0x05, content: content)
    
    print("📜 [Tx] 请求历史: StartSN=\(startSN), Count=\(count)")
    sendData(packet, to: p, characteristic: characteristic)
  }
  
  /// 发送 0x06 指令: 实时数据通知开关
  /// 结构: D3 96 06 [01/00] [Checksum]
  func send06Command(isEnabled: Bool) {
    guard let p = connectedPeripheral,
          let service = p.services?.first(where: { $0.uuid == .URIC_ACID_SERVICE }),
          let characteristic = service.characteristics?.first(where: { $0.uuid == .URIC_ACID_CHARACTERISTIC }) else { return }
    
    let value: UInt8 = isEnabled ? 0x01 : 0x00
    let content: [UInt8] = [value]
    let packet = buildPacket(type: 0x06, content: content)
    
    print("🚀 [Tx] 发送实时开关: \(isEnabled)")
    sendData(packet, to: p, characteristic: characteristic)
  }
  
  /// 构造协议包
  /// Header(D3 96) + Type(1) + Content(N) + Checksum(1)
  private func buildPacket(type: UInt8, content: [UInt8]) -> Data {
    var packet: [UInt8] = [0xD3, 0x96, type]
    packet.append(contentsOf: content)
    
    // 计算校验位: 从第一个字节(D3)开始异或到内容结束
    var checksum: UInt8 = 0
    for byte in packet {
      checksum ^= byte
    }
    packet.append(checksum)
    
    return Data(packet)
  }
  
  private func sendData(_ data: Data, to p: Peripheral, characteristic: CBCharacteristic) {
    let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
    // print("📤 [Tx] 发送指令: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
    
    p.writeValue(data, for: characteristic, type: writeType)
  }
  
  /// 处理接收到的蓝牙数据
  ///
  /// **流程:**
  /// 1. 验证协议头 (D3 96) 和校验位
  /// 2. 根据 Command Byte 分发处理:
  ///    - `0x10`: 实时测量数据
  ///    - `0xF4`: 握手/状态查询应答
  ///    - `0xF5`: 历史数据包
  ///    - `0xF6`: 设置成功确认
  fileprivate func handleReceivedData(_ data: Data, from sn: String) {
    let bytes = [UInt8](data)
    guard bytes.count >= 4 else { return } // 最小包长: D3 96 Type Checksum
    
    // 1. 验证头 D3 96
    guard bytes[0] == 0xD3, bytes[1] == 0x96 else {
      print("⚠️ [Rx] 无效包头: \(bytes.prefix(2).map { String(format: "%02X", $0) })")
      return
    }
    
    // 2. 验证校验位
    var calculatedChecksum: UInt8 = 0
    for i in 0..<(bytes.count - 1) {
      calculatedChecksum ^= bytes[i]
    }
    let receivedChecksum = bytes.last!
    guard calculatedChecksum == receivedChecksum else {
      print("⚠️ [Rx] 校验失败: Calc \(String(format: "%02X", calculatedChecksum)) != Recv \(String(format: "%02X", receivedChecksum))")
      return
    }
    
    // print("📥 [Rx] 收到数据: \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
    
    let type = bytes[2]
    let content = Array(bytes[3..<(bytes.count - 1)])
    
    switch type {
    case 0x10: // 实时血糖数据
      handleRealtimeData(content, sn: sn)
      
    case 0xF4: // 查询应答 (含水化时间)
      handleF4Response(content, sn: sn)
      
    case 0xF5: // 历史数据
      handleF5Response(content)
      
    case 0xF6:
      print("✅ [Rx] 实时数据开关设定成功 (F6)")
      
    default:
      print("ℹ️ [Rx] 未处理指令类型: \(String(format: "%02X", type))")
    }
  }
  
  /// 处理 0x10 实时数据
  ///
  /// **数据解析:**
  /// - SN (Bytes 0-3): 当前数据的序列号
  /// - Life (Bytes 4-5): 发射器寿命余量 (分钟)
  /// - Value (Bytes 6-7): 测量值原始数据 (需除以 10.0)
  /// - Time: 使用 `deviceStartTime + (SN * 120s)` 计算精确时间
  ///
  /// **特殊逻辑:**
  /// - 如果收到 F1 标志 (Byte 10)，说明设备请求同步时间，将自动发送 0x04。
  private func handleRealtimeData(_ content: [UInt8], sn: String) {
    guard content.count >= 11 else { return }
    
    // 提取 SN (bytes 0-3)
    let sn3 = Int(content[0])
    let sn2 = Int(content[1])
    let sn1 = Int(content[2])
    let sn0 = Int(content[3])
    let dataSN = (sn3 << 24) + (sn2 << 16) + (sn1 << 8) + sn0
    
    // 提取寿命余量 (bytes 4-5)
    let l1 = Int(content[4])
    let l0 = Int(content[5])
    let lifeMinutes = (l1 << 8) + l0
    self.currentLifeMinutes = lifeMinutes
    
    // 提取血糖/尿酸值 (bytes 6, 7)
    let valueHigh = Int(content[6])
    let valueLow = Int(content[7])
    let rawValue = (valueHigh << 8) + valueLow
    let finalValue = Double(rawValue) / 10.0
    
    // 计算精确时间: StartTime + (SN * 120s)
    var timestamp = Date()
    if let start = self.deviceStartTime {
        let rawDate = start.addingTimeInterval(TimeInterval(dataSN * 120))
        // 修正：绝不超过当前手机时间，防止出现“未来数据”
        timestamp = min(rawDate, Date())
    }
    
    print("🩸 实时测量值: \(finalValue) (SN: \(dataSN), Life: \(lifeMinutes)min, Time: \(timestamp))")
    valuePublisher.send((finalValue, sn, dataSN, timestamp, lifeMinutes))
    
    // 检查 F1 同步标志 (byte 10)
    if content.count > 10, content[10] == 0xF1 {
      print("⚠️ 设备请求同步时间 (F1)")
      if let p = connectedPeripheral, let services = p.services,
         let s = services.first(where: { $0.uuid == .URIC_ACID_SERVICE }),
         let c = s.characteristics?.first(where: { $0.uuid == .URIC_ACID_CHARACTERISTIC }) {
        send04CommandInternal(to: p, characteristic: c)
      }
    }
  }
  
  // 处理 0xF4 查询应答
  // Content: SampleNo(4) + Life(2) + Timestamp(4) + UserInfo(12) + Hydration(2)
  private func handleF4Response(_ content: [UInt8], sn: String) {
    // 校验长度，只要够读到水化时间即可
    guard content.count >= 24 else { return }
    
    // 1. 提取当前最大 SN (Current Sample No) - Bytes 0-3
    let s3 = Int(content[0])
    let s2 = Int(content[1])
    let s1 = Int(content[2])
    let s0 = Int(content[3])
    self.currentMaxSN = (s3 << 24) + (s2 << 16) + (s1 << 8) + s0
    
    // 2. 提取寿命余量 (Bytes 4-5)
    let l1 = Int(content[4])
    let l0 = Int(content[5])
    let lifeMinutes = (l1 << 8) + l0
    self.currentLifeMinutes = lifeMinutes
    
    // 3. 提取设备启动时间戳 (Timestamp) - Bytes 6-9
    let t3 = Int(content[6])
    let t2 = Int(content[7])
    let t1 = Int(content[8])
    let t0 = Int(content[9])
    let timestampVal = (t3 << 24) + (t2 << 16) + (t1 << 8) + t0
    let startTime = Date(timeIntervalSince1970: TimeInterval(timestampVal))
    self.deviceStartTime = startTime
    
    print("ℹ️ 设备状态: MaxSN=\(currentMaxSN), Life=\(lifeMinutes)min, StartTime=\(startTime)")
    
    // 4. 提取水化时间 - Bytes 22-23
    let hHigh = Int(content[22])
    let hLow = Int(content[23])
    let hydrationVal = (hHigh << 8) + hLow
    
    // 通知 UI
    if hydrationVal == 0 {
      print("💧 水化已结束")
      hydrationPublisher.send((0, sn))
    } else if hydrationVal == 0xFFFF {
      print("💧 水化尚未开始")
      hydrationPublisher.send((0, sn)) // Treat as ready
    } else {
      print("💧 水化剩余: \(hydrationVal) 秒")
      hydrationPublisher.send((hydrationVal, sn))
    }
    
    // 5. 🔥 握手完成，通知 DeviceManager 决定是同步历史还是开启实时
    handshakeFinishedPublisher.send((currentMaxSN, startTime, lifeMinutes))
  }
  
  /// 处理 0xF5 历史数据响应
  ///
  /// **数据结构:**
  /// - Count (1 Byte): 本包包含的记录条数
  /// - Items (N * 8 Bytes): 每条记录 8 字节
  ///   - SN (4 Bytes)
  ///   - Value (2 Bytes, offset 6)
  ///
  /// **逻辑:**
  /// - 解析每一条记录的 SN 和 Value
  /// - 根据 `StartTime` 推算每条记录的时间戳
  /// - 批量发送给 UI 层保存
  private func handleF5Response(_ content: [UInt8]) {
    guard !content.isEmpty else { return }
    
    let count = Int(content[0])
    let itemSize = 8
    
    guard content.count >= 1 + (count * itemSize) else {
      print("⚠️ [Rx] 历史数据长度不足")
      return
    }
    
    var items: [UricAcidHistoryItem] = []
    guard let startTime = self.deviceStartTime else {
      print("⚠️ [Rx] 收到历史数据但无设备启动时间")
      return
    }
    
    for i in 0..<count {
      let offset = 1 + (i * itemSize)
      let chunk = Array(content[offset..<(offset + itemSize)])
      
      // SN (0-3)
      let sn = (Int(chunk[0]) << 24) + (Int(chunk[1]) << 16) + (Int(chunk[2]) << 8) + Int(chunk[3])
      
      // Value (6-7)
      let valRaw = (Int(chunk[6]) << 8) + Int(chunk[7])
      let val = Double(valRaw) / 10.0
      
      // Calculate Time: StartTime + (SN * 2 minutes)
      // Protocol implies interval is 2 minutes (120s)
      let rawTime = startTime.addingTimeInterval(TimeInterval(sn * 120))
      // 修正：绝不超过当前手机时间
      let itemTime = min(rawTime, Date())
      
      items.append(UricAcidHistoryItem(sn: sn, value: val, timestamp: itemTime))
    }
    
    print("📦 [Rx] 收到 \(items.count) 条历史数据 (SN: \(items.first?.sn ?? 0) - \(items.last?.sn ?? 0))")
    historyPublisher.send(items)
  }
}

struct UricAcidHistoryItem {
  let sn: Int
  let value: Double
  let timestamp: Date
}
  
  // MARK: - Protocol Helpers
  
  /// 发送 0x04 指令: App查询最新采样序号/同步时间

// MARK: - CentralManagerDelegate
extension BluetoothManager: CentralManagerDelegate {
  
  nonisolated func centralManagerDidUpdateState(_ central: CentralManager) {
    Task { @MainActor in
      self.centralState = central.state
      // 状态就绪且用户想要扫描 -> 自动开始
      if central.state == .poweredOn && self.isScanningDesired {
        self.performScan()
      }
    }
  }
  
  nonisolated func centralManager(
    _ central: CentralManager,
    didDiscover peripheral: Peripheral,
    advertisementData: UncheckedSendable<[String : Any]>,
    rssi RSSI: NSNumber
  ) {
    Task { @MainActor in
      guard !self.scanSet.contains(peripheral.id) else { return }
      self.scanSet.insert(peripheral.id)
      
      let discoveredItem = DiscoveredPeripheral(
        peripheral: peripheral,
        rssi: RSSI.intValue,
        advertisementData: advertisementData.value
      )
      
      withAnimation {
        self.discoveredPeripherals.append(discoveredItem)
      }
    }
  }
  
  nonisolated func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) {
    print("✅ [Delegate] 已连接设备")
  }
  
  nonisolated func centralManager(_ central: CentralManager, didFailToConnect peripheral: Peripheral, error: Error?) {
    print("❌ [Delegate] 连接失败: \(error?.localizedDescription ?? "")")
  }
  
  nonisolated func centralManager(_ central: CentralManager, didDisconnectPeripheral peripheral: Peripheral, error: Error?) {
    print("⚠️ [Delegate] 连接断开")
    Task { @MainActor in
      if self.connectedPeripheral?.id == peripheral.id {
        self.connectedPeripheral = nil
        self.connectionStatusPublisher.send(false)
      }
    }
  }
  
  nonisolated func centralManager(_ central: CentralManager, willRestoreState dict: UncheckedSendable<[String : Any]>) {}
}

// MARK: - PeripheralDelegate
extension BluetoothManager: PeripheralDelegate {
  
  // 收到数据回调
  nonisolated func peripheral(_ peripheral: Peripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let data = characteristic.value else { return }
    
    // 获取 SN，如果还没拿到真实 SN，先用暂存的
    let sn = UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceName) ?? "JLUA-DEVICE"
    
    // 切回主线程/Actor 处理业务逻辑
    Task { @MainActor in
      BluetoothManager.shared.handleReceivedData(data, from: sn)
    }
  }
}
