//
//  Project: Swift6Extensions
//  File: DeviceMain.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//
//

import SwiftUI


struct DeviceMainScreen: View {
  
  @State private var selectedIndex = 0
  // 图表数据源
  @State private var chartData: [HealthDataPoint] = []
  
  var currentScope: TimeScope {
    let scopes = TimeScope.allCases
    guard selectedIndex >= 0 && selectedIndex < scopes.count else { return .hours8 }
    return scopes[selectedIndex]
  }
  
  @State var showScanBleList = false
  
  var body: some View {
    MainView {
      Spacer()
        .frame(height: 10)
      NoLinkHeader(showSheet: $showScanBleList)
        .background(RoundedRectangle(cornerRadius: 16)
          .fill(Color.white))
      
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
      .task {
        await loadHealthData(for: currentScope)
      }
      .onChange(of: selectedIndex) { _, _ in
        Task {
         await loadHealthData(for: currentScope)
        }
      }
      .sheet(isPresented: $showScanBleList) {
        VStack {
          Text("Scan Device")
        }
        .task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 10 秒
            showScanBleList = false
          }
      }
    }
  }
  
  
  private func loadHealthData(for scope: TimeScope) async {
    
    let useMockData = true
    
    if useMockData {
      print("当前无真实数据，正在生成模拟演示数据...")
      generateSimulationData(for: scope)
      return
    }
    
    // --- ⬇️ 未来：真实数据接入区 (现在先空着) ⬇️ ---
    // let apiData = await Api.get(...)
    // self.chartData = apiData
    // --- ⬆️ 未来：真实数据接入区 ⬆️ ---
  }
  
  private func generateSimulationData(for scope: TimeScope) {
    var points: [HealthDataPoint] = []
    let now = Date()
    
    let secondsBack = scope.duration
    let startDate = now.addingTimeInterval(-secondsBack)
    
    let interval: TimeInterval = 600
    let totalPoints = Int(secondsBack / interval)
    
    for i in 0...totalPoints {
      let date = startDate.addingTimeInterval(Double(i) * interval)
      
      if date > now { break }
      
      let baseValue = 300.0
      let sineWave = sin(Double(i) * 0.1) * 100.0
      let randomNoise = Double.random(in: -20...20)
      let value = max(0, min(1000, baseValue + sineWave + randomNoise))
      
      points.append(HealthDataPoint(date: date, value: value))
    }
    
    withAnimation(.easeInOut) {
      self.chartData = points
    }
  }
}


#Preview {
  DeviceMainScreen()
}
