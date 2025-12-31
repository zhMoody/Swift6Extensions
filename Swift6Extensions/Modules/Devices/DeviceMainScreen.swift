import SwiftUI
import CoreBluetooth
import SwiftData
import Combine

// 内部传输对象
private struct ChartInputData: Sendable {
    let date: Date
    let value: Double
}

struct DeviceMainScreen: View {
  @Environment(\.modelContext) private var modelContext
  // 移除全量 @Query，避免主线程卡顿
  // @Query ... savedRecords
  
  @StateObject private var deviceManager = DeviceManager()
  
  @State private var selectedIndex = 0
  @State private var chartData: [HealthDataPoint] = []
  @State private var showScanBleList = false
  @State private var targetMaxSN: Int = 0 
  
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
              HealthTrendChart(scope: currentScope, data: chartData, customYRange: 0...6, limitHigh: 1.9, limitLow: 1.4)
            }
            .frame(height: 280)
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            
            Button {
              deviceManager.disconnect(isUserAction: true)
              
              do {
                try modelContext.delete(model: UricAcidData.self)
                print("🗑️ 数据库已清空")
              } catch {
                print("❌ 数据库清空失败: \(error)")
              }
              
              withAnimation {
                chartData = []
                targetMaxSN = 0
              }
              
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
          // 视图出现时，触发全量后台加载
          refreshUI()
        }
        .onChange(of: selectedIndex) { _, _ in
           // 切换时间范围，重新从后台拉取图表数据
           updateChartFromBackground()
        }
        // 蓝牙实时数据 -> 插入 -> 刷新
        .onReceive(BluetoothManager.shared.valuePublisher) { (value, snStr, dataSN, timestamp, lifeMinutes) in
           insertData(value: value, snStr: snStr, dataSN: dataSN, timestamp: timestamp, lifeMinutes: lifeMinutes)
        }
        // 握手完成 -> 同步逻辑 (保持不变，除了一处)
        .onReceive(BluetoothManager.shared.handshakeFinishedPublisher) { (maxSN, deviceStartTime, lifeMinutes) in
          print("🤝 握手完成: DeviceMaxSN=\(maxSN), Life=\(lifeMinutes)min")
          self.targetMaxSN = maxSN
          
          // 🔥 关键：使用 FetchDescriptor 手动查询最新 SN，不依赖 @Query
          var localMaxSN = 0
          var descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.sn, order: .reverse)])
          descriptor.fetchLimit = 1
          
          if let lastItem = try? modelContext.fetch(descriptor).first {
            localMaxSN = lastItem.sn
          }
          
          if localMaxSN < maxSN {
            let remaining = maxSN - localMaxSN
            let count = min(20, remaining)
            print("📥 需要同步历史: Local=\(localMaxSN) -> Target=\(maxSN)")
            BluetoothManager.shared.send05Command(startSN: localMaxSN + 1, count: count)
          } else {
            print("✅ 数据已完全同步")
            BluetoothManager.shared.send06Command(isEnabled: true)
          }
        }
        // 历史数据包 -> 插入 -> 刷新
        .onReceive(BluetoothManager.shared.historyPublisher) { items in
          print("📦 [Rx] 收到历史数据包: \(items.count) 条")
          
          if !items.isEmpty {
            for item in items {
               let newData = UricAcidData(
                 value: item.value,
                 timestamp: item.timestamp,
                 serialNumber: "HISTORY NOW",
                 sn: item.sn
               )
               modelContext.insert(newData)
            }
            try? modelContext.save()
            
            // 插入后刷新 UI
            refreshUI()
          }
          
           // 重新查询本地最新的 SN
          var localMaxSN = 0
          var descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.sn, order: .reverse)])
          descriptor.fetchLimit = 1
          
          if let lastItem = try? modelContext.fetch(descriptor).first {
            localMaxSN = lastItem.sn
          }
          
          if items.isEmpty || localMaxSN >= self.targetMaxSN {
            BluetoothManager.shared.queryDeviceStatus()
          } else {
            let nextStart = localMaxSN + 1
            let remaining = self.targetMaxSN - nextStart + 1
            if remaining > 0 {
              let count = min(20, remaining)
              BluetoothManager.shared.send05Command(startSN: nextStart, count: count)
            } else {
              BluetoothManager.shared.queryDeviceStatus()
            }
          }
        }
      },
      pageTwo: {
        VStack(spacing: 0) {
          HStack {
            Text("历史数据归档").font(.headline)
            Spacer()
            if deviceManager.isLoading {
              ProgressView().scaleEffect(0.8)
            } else {
              Text("共 \(deviceManager.historyData.count) 天").font(.caption).foregroundStyle(.gray)
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
                    Text(day.dateString).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold).foregroundStyle(.exBlue)
                    Spacer()
                    Text("\(day.items.count) 条记录").font(.caption2).foregroundStyle(.gray)
                  }
                  .padding(.vertical, 4)
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
  
  // 辅助：插入数据并刷新
  private func insertData(value: Double, snStr: String, dataSN: Int, timestamp: Date, lifeMinutes: Int) {
     // 先查重 (这里用 fetch)
     var descriptor = FetchDescriptor<UricAcidData>(predicate: #Predicate { $0.sn == dataSN })
     descriptor.fetchLimit = 1
     
     if let _ = try? modelContext.fetch(descriptor).first {
         // 已存在
     } else {
         let newData = UricAcidData(
            value: value,
            timestamp: timestamp,
            serialNumber: snStr,
            sn: dataSN,
            lifeMinutes: lifeMinutes
        )
        modelContext.insert(newData)
        try? modelContext.save()
        
        // 插入后刷新
        refreshUI()
     }
  }

  // 统一刷新入口
  private func refreshUI() {
    let container = modelContext.container
    
    // 1. 触发列表后台加载
    deviceManager.loadAllData(container: container)
    
    // 2. 触发图表后台加载
    updateChartFromBackground()
    
    // 3. 更新 Header (在主线程简单查询一条最新数据即可)
    updateHeader()
  }
  
  private func updateHeader() {
      var descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
      descriptor.fetchLimit = 1
      if let latest = try? modelContext.fetch(descriptor).first {
          deviceManager.updateDisplayValue(
            latest.value,
            sn: latest.serialNumber,
            date: latest.timestamp,
            lifeMinutes: latest.lifeMinutes
          )
      }
  }
  
  private func updateChartFromBackground() {
    let container = modelContext.container
    let scopeDuration = currentScope.duration
    
    Task.detached(priority: .userInitiated) {
      let context = ModelContext(container)
      let now = Date()
      let startDate = now.addingTimeInterval(-scopeDuration)
      
      let descriptor = FetchDescriptor<UricAcidData>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
      
      if let rawData = try? context.fetch(descriptor) {
         // 1. 过滤
         let filtered = rawData.filter { $0.timestamp >= startDate }
         
         // 2. 转换并排序
         let sortedPoints = filtered.map { 
             HealthDataPoint(date: $0.timestamp, value: $0.value) 
         }.sorted { $0.date < $1.date }
         
         // 3. 降采样
         // 屏幕宽度有限，渲染过多点位会导致严重卡顿。限制在 300 个点左右。
         let targetPointCount = 300
         var finalPoints: [HealthDataPoint] = []

         if sortedPoints.count > targetPointCount {
             let step = Double(sortedPoints.count) / Double(targetPointCount)
             for i in 0..<targetPointCount {
                 let index = Int(Double(i) * step)
                 if index < sortedPoints.count {
                     finalPoints.append(sortedPoints[index])
                 }
             }
             // 确保最后一个点总是包含在内，保证图表右侧闭合
             if let last = sortedPoints.last, finalPoints.last != last {
                 finalPoints.append(last)
             }
         } else {
             finalPoints = sortedPoints
         }
         
         // 4. 回到主线程更新
         await MainActor.run {
            self.chartData = finalPoints
         }
      }
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

