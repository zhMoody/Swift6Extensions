import SwiftUI
import CoreBluetooth
import SwiftData
import Combine

struct DeviceMainScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: [SortDescriptor(\UricAcidData.timestamp, order: .reverse)]) private var savedRecords: [UricAcidData]
  
  @StateObject private var deviceManager = DeviceManager()
  
  @State private var selectedIndex = 0
  @State private var chartData: [HealthDataPoint] = []
  @State private var showScanBleList = false
  @State private var targetMaxSN: Int = 0 // 同步目标 SN
  
  var currentScope: TimeScope {
    let scopes = TimeScope.allCases
    guard selectedIndex >= 0 && selectedIndex < scopes.count else { return .hours8 }
    return scopes[selectedIndex]
  }
  
  var body: some View {
    MainView(
      pageOne: {
        ScrollView {
          VStack(spacing: 16) {
            
            Spacer().frame(height: 10)
            
            DeviceHeaderContainer(
              manager: deviceManager,
              showScanSheet: $showScanBleList
            )
            
            AdvancedSegmentedControl(
              items: ["8小时", "12小时", "24小时", "全周期"],
              selectedIndex: $selectedIndex,
              activeColor: .exBlue,
              inactiveColor: .gray,
              indicatorColor: .exBlue,
              backgroundColor: .exSegmentBg,
              containerHeight: 43
            )
            
            VStack {
              HealthTrendChart(scope: currentScope, data: chartData)
            }
            .frame(height: 280)
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            
            Button {
              // 1. 断开连接 & 清除缓存
              deviceManager.disconnect(isUserAction: true)
              
              // 2. 清除 SwiftData 数据库
              do {
                try modelContext.delete(model: UricAcidData.self)
                print("🗑️ 数据库已清空")
              } catch {
                print("❌ 数据库清空失败: \(error)")
              }
              
              // 3. 重置 UI 状态
              withAnimation {
                chartData = []
                targetMaxSN = 0
              }
              
              // 4. 清除 Manager 内部状态
              deviceManager.clearMemoryState()
              
            } label: {
              Text("断开连接并清除数据")
                .foregroundStyle(.red)
                .padding()
            }
            
            Spacer().frame(height: 40)
          }
          .padding(.horizontal)
        }
        .onAppear {
          refreshUI()
        }
        .onChange(of: selectedIndex) { _, _ in
          updateChartFromMemory()
        }
        // 核心：监听数据库变化，自动刷新 UI
        .onChange(of: savedRecords) { _, _ in
          refreshUI()
        }
        // 监听蓝牙数据并保存
        .onReceive(BluetoothManager.shared.valuePublisher) { (value, snStr, dataSN, timestamp, lifeMinutes) in
          // 检查是否重复以避免冗余
          let exists = savedRecords.contains(where: { $0.sn == dataSN })
          if !exists {
            let newData = UricAcidData(
              value: value,
              timestamp: timestamp, // 使用设备计算的精确时间
              serialNumber: snStr,
              sn: dataSN,
              lifeMinutes: lifeMinutes
            )
            modelContext.insert(newData)
            try? modelContext.save()
          }
        }
        // 监听握手完成：决定是同步历史还是开启实时
        .onReceive(BluetoothManager.shared.handshakeFinishedPublisher) { (maxSN, deviceStartTime, lifeMinutes) in
          print("🤝 握手完成: DeviceMaxSN=\(maxSN), Life=\(lifeMinutes)min")
          self.targetMaxSN = maxSN
          
          
          // 🔥 关键修复：直接查库获取最新 SN，不要用 savedRecords（可能有延迟）
          var localMaxSN = 0
          var descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.sn, order: .reverse)])
          descriptor.fetchLimit = 1
          
          if let lastItem = try? modelContext.fetch(descriptor).first {
            localMaxSN = lastItem.sn
          }
          
          if localMaxSN < maxSN {
            let remaining = maxSN - localMaxSN
            // 每次最多拉20条，或者拉取剩余的所有条数
            let count = min(20, remaining)
            
            print("📥 需要同步历史: Local=\(localMaxSN) -> Target=\(maxSN) (剩余: \(remaining), 本次拉取: \(count))")
            BluetoothManager.shared.send05Command(startSN: localMaxSN + 1, count: count)
          } else {
            print("✅ 数据已完全同步，开启实时监控")
            BluetoothManager.shared.send06Command(isEnabled: true)
          }
        }
        // 监听历史数据包
        .onReceive(BluetoothManager.shared.historyPublisher) { items in
          print("📦 [Rx] 收到历史数据包: \(items.count) 条")
          
          // 1. 保存数据 (如果有)
          if !items.isEmpty {
            for item in items {
              let newData = UricAcidData(
                value: item.value,
                timestamp: item.timestamp,
                serialNumber: "HISTORY",
                sn: item.sn
              )
              modelContext.insert(newData)
            }
            try? modelContext.save()
          }
          
          // 2. 重新查询本地最新的 SN
          var localMaxSN = 0
          var descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.sn, order: .reverse)])
          descriptor.fetchLimit = 1
          
          if let lastItem = try? modelContext.fetch(descriptor).first {
            localMaxSN = lastItem.sn
          }
          
          print("📊 同步进度: Local=\(localMaxSN) / Target=\(self.targetMaxSN)")
          
          // 3. 决策：继续拉取还是结束？
          // 如果收到的包为空，通常意味着设备也没数据了，直接结束比较安全
          // 或者如果本地已经完全追平了目标，也结束
          if items.isEmpty || localMaxSN >= self.targetMaxSN {
            print("🎉 历史同步完成，再次发送 0x04 校验...")
            BluetoothManager.shared.queryDeviceStatus()
          } else {
            let nextStart = localMaxSN + 1
            let remaining = self.targetMaxSN - nextStart + 1
            
            if remaining > 0 {
              let count = min(20, remaining)
              print("🔄 继续拉取下一批: Start=\(nextStart), Count=\(count)...")
              BluetoothManager.shared.send05Command(startSN: nextStart, count: count)
            } else {
              // 理论上不会进这里，但作为防御
              BluetoothManager.shared.queryDeviceStatus()
            }
          }
        }
      },
      pageTwo: {
        VStack(spacing: 0) {
          HStack {
            Text("历史数据归档")
              .font(.headline)
            Spacer()
            if deviceManager.isLoading {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text("共 \(deviceManager.historyData.count) 天")
                .font(.caption)
                .foregroundStyle(.gray)
            }
          }
          .padding()
          .background(Color.white)
          
          List {
            ForEach($deviceManager.historyData) { $day in
              Section {
                DisclosureGroup(isExpanded: $day.isExpanded) {
                  if day.isExpanded {
                    ForEach(day.items) { item in
                      HistoryRowView(item: item)
                    }
                  }
                } label: {
                  HStack {
                    Text(day.dateString)
                      .font(.system(.subheadline, design: .monospaced))
                      .fontWeight(.bold)
                      .foregroundStyle(Color("exBlue")) // 明确使用资源文件中的颜色
                    Spacer()
                    Text("\(day.items.count) 条记录")
                      .font(.caption2)
                      .foregroundStyle(.gray)
                  }                  .padding(.vertical, 4)
                }
              }
            }
          }
          .listStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    )
    .sheet(isPresented: $showScanBleList) {
      BleScanningSheet_Wrapper { device, peripheral in
        deviceManager.handleConnectSuccess(
          device: device,
          peripheral: peripheral,
          needHydration: true
        )
        showScanBleList = false
      }
    }
  }
  
  // 统一刷新入口
  private func refreshUI() {
    // 1. 更新历史列表
    deviceManager.processHistoryData(savedRecords)
    // 2. 更新图表
    updateChartFromMemory()
    
    // 3. 🔥 关键：用最新数据刷新 Header 显示
    if let latest = savedRecords.first {
      deviceManager.updateDisplayValue(
        latest.value,
        sn: latest.serialNumber,
        date: latest.timestamp,
        lifeMinutes: latest.lifeMinutes
      )
    }
  }
  
  private func updateChartFromMemory() {
    let now = Date()
    let secondsBack = currentScope.duration
    let startDate = now.addingTimeInterval(-secondsBack)
    
    // 在内存中过滤数据，比每次去查库更高效（因为 savedRecords 已经是我们需要的数据集）
    let filtered = savedRecords.filter { $0.timestamp >= startDate }
    let points = filtered.map { HealthDataPoint(date: $0.timestamp, value: $0.value) }
    
    // 排序确保图表绘制正确
    let sortedPoints = points.sorted { $0.date < $1.date }
    
    withAnimation(.easeInOut) {
      self.chartData = sortedPoints
    }
  }
}

// 辅助 Wrapper 保持不变
struct BleScanningSheet_Wrapper: View {
  var onConnectSuccess: (ScannedDevice, CBPeripheral?) -> Void
  
  var body: some View {
    BleScanningSheet(onConnect: onConnectSuccess)
  }
}

