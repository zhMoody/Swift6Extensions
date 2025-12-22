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
    /// 发送尿酸/血糖数值 (Value, SN)
    let valuePublisher = PassthroughSubject<(Double, String), Never>()
    /// 发送水化/倒计时秒数 (Seconds, SN)
    let hydrationPublisher = PassthroughSubject<(Int, String), Never>()
    /// 连接状态变更
    let connectionStatusPublisher = PassthroughSubject<Bool, Never>()
    
    // MARK: - Internals
    private let central: CentralManager
    private var scanSet: Set<UUID> = []
    
    // 标记是否希望扫描
    private var isScanningDesired = false
    
    // 专用串行队列，确保蓝牙操作不卡顿 UI
    private let bleQueue = DispatchQueue(label: "com.uric.ble.queue", qos: .userInitiated)
    
    private override init() {
        // 初始化：传入专用队列，避免主线程干扰
        let manager = CentralManager(delegate: nil, queue: bleQueue, options: nil)
        self.central = manager
        super.init()
        
        self.central.delegate = self
        
        // 启动等待
        Task { try? await central.waitUntilReady() }
    }
    
    // MARK: - Public Intents (UI 调用)
    
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
        
        // 生产环境关闭 AllowDuplicatesKey 以节省电量
        // 如果你的设备广播频率极低搜不到，可以将这里改为 true
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        print("🚀 [BluetoothManager] 开始扫描 (模式: 所有设备)")
        
        // 核心配置：使用 nil 扫描所有服务，这是能搜到设备的关键
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
  func connect(to peripheral: Peripheral) async throws -> Peripheral {
    stopScanning()
    print("🔗 [BluetoothManager] 正在连接: \(peripheral.id)")
    
    // 1. 建立连接
    let p = try await central.connect(peripheral, timeout: 10.0)
    
    // 2. 发现服务
    let services = try await p.discoverServices(nil)
    
    if let service = services.first {
      let characteristics = try await p.discoverCharacteristics(nil, for: service)
      
      // -------------------------------------------------------
      // 步骤 A: 开启通知 (找到支持 Notify 的特征)
      // -------------------------------------------------------
      // 优先找支持 notify 的特征，如果找不到就取第一个
      if let notifyChar = characteristics.first(where: { $0.properties.contains(.notify) }) ?? characteristics.first {
        
        // 尝试开启通知
        if notifyChar.properties.contains(.notify) {
          let _ = try await p.setNotifyValue(true, for: notifyChar)
          print("📡 [BluetoothManager] 已开启通知: \(notifyChar.uuid)")
        }
        
        // -------------------------------------------------------
        // 步骤 B: 立即发送 04 指令 (握手/开始测量)
        // -------------------------------------------------------
        // 构造 04 指令数据
        let commandData = Data([0x04])
        
        // 策略：通常数据通道是同一个特征。如果该特征支持写，就写它；
        // 如果不支持，就找服务里其他支持写的特征。
        var writeChar = notifyChar
        
        let canWrite = writeChar.properties.contains(.write) || writeChar.properties.contains(.writeWithoutResponse)
        
        if !canWrite {
          // 如果通知特征不可写，尝试在列表里找一个能写的
          if let otherChar = characteristics.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }) {
            writeChar = otherChar
            print("🔀 [BluetoothManager] 切换到可写特征: \(writeChar.uuid)")
          }
        }
        
        // 执行写入
        if writeChar.properties.contains(.write) || writeChar.properties.contains(.writeWithoutResponse) {
          // 优先使用带响应的写入 (.withResponse)，除非只支持无响应
          let type: CBCharacteristicWriteType = writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
          
          p.writeValue(commandData, for: writeChar, type: type)
          print("📤 [BluetoothManager] 已发送 04 指令 (Type: \(type == .withResponse ? "WithResp" : "NoResp"))")
        } else {
          print("⚠️ [BluetoothManager] 未找到可写入的特征，04 指令发送失败")
        }
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
    
    // MARK: - 🔥 自定义数据处理逻辑 🔥
    
    /// 这里处理设备返回的原始字节数据
    fileprivate func handleReceivedData(_ data: Data, from sn: String) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return }
        
        print("📥 [RX Data] 收到数据: \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        let command = bytes[0]
        
        // --- 请在此处填入你的具体逻辑 ---
        switch command {
            
        case 0xF3: // [示例] 水化倒计时
            // 假设 byte[1] 是剩余秒数
            if bytes.count > 1 {
                let secondsLeft = Int(bytes[1])
                print("💧 水化进行中: 剩余 \(secondsLeft)秒")
                hydrationPublisher.send((secondsLeft, sn))
            }
            
        case 0xF4: // [示例] 测量结果
            // 假设后续字节是数值，这里暂时 Mock 一个值
            print("🩸 测量完成")
            let mockValue = 360.0
            valuePublisher.send((mockValue, sn))
            
        case 0xF5:
            // 处理 06 指令...
            print("收到 F6 指令")
            
        case 0xF7:
            // 处理 07 指令...
            print("收到 F7 指令")
            
        case 0x10:
            // 处理 07 指令...
            print("收到 10 指令")

        default:
            print("未知指令: \(command)")
        }
    }
}

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
            
            // 打印发现日志，方便调试
            // print("🔎 发现: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
            
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
