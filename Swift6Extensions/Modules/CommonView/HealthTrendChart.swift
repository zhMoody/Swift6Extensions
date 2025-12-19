import SwiftUI
import Charts


struct HealthDataPoint: Identifiable, Equatable {
  let id = UUID()
  let date: Date
  let value: Double
}

struct HealthTrendChart: View {
  var scope: TimeScope
  var data: [HealthDataPoint]
  
  @State private var chartDomain: ClosedRange<Date>
  @State private var xAxisTicks: [Date] = []
  
  @State private var selectedDataPoint: HealthDataPoint? = nil
  
  private let yMax: Double = 1000.0
  private let limitHigh: Double = 416.0
  private let limitLow: Double = 208.0
  
  init(scope: TimeScope, data: [HealthDataPoint]) {
    self.scope = scope
    self.data = data
    let win = scope.calculateWindow(currentDate: Date())
    _chartDomain = State(initialValue: win)
    _xAxisTicks = State(initialValue: scope.generateTicks(in: win))
  }
  
  var body: some View {
    Chart {
      ForEach(data) { point in
        AreaMark(
          x: .value("Time", point.date),
          y: .value("Value", point.value)
        )
        .interpolationMethod(.monotone)
        .foregroundStyle(LinearGradient(colors: [.exBlue.opacity(0.2), .exBlue.opacity(0.0)], startPoint: .top, endPoint: .bottom))
      }
      
      ForEach(data) { point in
        LineMark(
          x: .value("Time", point.date),
          y: .value("Value", point.value)
        )
        .interpolationMethod(.monotone)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .foregroundStyle(.exBlue)
      }
      
      RuleMark(y: .value("H", limitHigh))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        .foregroundStyle(.red)
        .annotation(position: .trailing) {
          Text(String(format:"%.1f", limitHigh)).font(.caption2.bold()).foregroundStyle(.red).offset(x:5)
        }
      
      RuleMark(y: .value("L", limitLow))
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        .foregroundStyle(.orange)
        .annotation(position: .trailing) {
          Text(String(format:"%.1f", limitLow)).font(.caption2.bold()).foregroundStyle(.orange).offset(x:5)
        }
      // MARK: - NEW: 2. 如果有选中的点，绘制交互指示器
      if let selectedPoint = selectedDataPoint {
        RuleMark(x: .value("Selected Time", selectedPoint.date))
          .lineStyle(StrokeStyle(lineWidth: 1))
          .foregroundStyle(Color.exBlue.opacity(0.5))
        
        PointMark(
          x: .value("Selected Time", selectedPoint.date),
          y: .value("Selected Value", selectedPoint.value)
        )
        .symbol {
          Circle()
            .fill(.white)
            .strokeBorder(Color.exBlue, lineWidth: 2)
            .frame(width: 12, height: 12)
        }
      }
    }
    .chartYScale(domain: 0...yMax)
    .chartXScale(domain: chartDomain)
    .chartYAxis {
      AxisMarks(position: .leading, values: [250, 500, 750, 1000]) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.gray.opacity(0.15))
        AxisValueLabel {
          if let v = value.as(Double.self) {
            Text(String(format: "%.0f", v))
              .font(.system(size: 10))
              .foregroundStyle(.gray)
              .monospacedDigit()
          }
        }
      }
    }
    
    .chartXAxis {
      AxisMarks(values: xAxisTicks) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          .foregroundStyle(Color.gray.opacity(0.2))
        AxisValueLabel(
          centered: false,
          anchor: .top,
          collisionResolution: .disabled
        ) {
          if let date = value.as(Date.self) {
            Text(formatHour(date))
              .font(.system(size: 11))
              .foregroundStyle(.gray)
              .frame(minWidth: 40, alignment: .center)
          }
        }
      }
    }
    .chartPlotStyle { plot in
      plot.clipped()
    }
    .chartOverlay { proxy in
      GeometryReader { geo in
        ZStack(alignment: .topLeading) {
          // 1. 手势感应层 (透明背景)
          Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  let currentX = value.location.x
                  if let date: Date = proxy.value(atX: currentX) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                      findClosestDataPoint(to: date)
                    }
                  }
                }
                .onEnded { _ in
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                      self.selectedDataPoint = nil
                    }
                  }
                }
            )
          
          if let selected = selectedDataPoint,
             let startX = proxy.position(forX: selected.date),
             let startY = proxy.position(forY: selected.value) {
            
            let halfTooltipWidth: CGFloat = 55
            
            let clampedX = max(halfTooltipWidth, min(geo.size.width - halfTooltipWidth, startX + 30))
            
            TooltipView(point: selected)
              .fixedSize()
              .position(x: clampedX, y: startY - 45)
              .animation(.easeOut(duration: 0.1), value: startX)
          }
        }
      }
    }
    .padding(.trailing, 20)
    .transaction { $0.animation = nil }
    .onChange(of: scope) { _, newScope in
      update(newScope)
    }
  }
  
  private func formatHour(_ date: Date) -> String {
    let h = Calendar.current.component(.hour, from: date)
    return String(format: "%02d:00", h)
  }
  
  private func update(_ newScope: TimeScope) {
    let win = newScope.calculateWindow(currentDate: Date())
    self.chartDomain = win
    self.xAxisTicks = newScope.generateTicks(in: win)
  }
  private func findClosestDataPoint(to date: Date) {
    let closest = data.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    guard let newPoint = closest, newPoint != selectedDataPoint else {
      return
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    self.selectedDataPoint = newPoint
  }
}

struct HealthDashboardView: View {
  // MARK: - 状态属性
  @State private var selectedIndex = 0
  // 图表数据源
  @State private var chartData: [HealthDataPoint] = []
  
  var currentScope: TimeScope {
    let scopes = TimeScope.allCases
    guard selectedIndex >= 0 && selectedIndex < scopes.count else { return .hours8 }
    return scopes[selectedIndex]
  }
  
  var body: some View {
    VStack(spacing: 24) {
      Text("实时监测")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
      
      AdvancedSegmentedControl(
        items: TimeScope.allCases.map { $0.rawValue },
        selectedIndex: $selectedIndex,
        activeColor: .black,
        containerHeight: 36
      )
      .padding(.horizontal)
      
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          Text("数值趋势")
            .font(.caption)
            .foregroundStyle(.secondary)
          
          // 这里的 chartData 现在由下方的 loadHealthData 填充
          HealthTrendChart(scope: currentScope, data: chartData)
            .frame(height: 280)
        }
      }
      
      Spacer()
    }
    .padding(.top)
    .background(Color(uiColor: .systemGroupedBackground))
    // MARK: - 生命周期
    .onAppear {
      loadHealthData(for: currentScope)
    }
    .onChange(of: selectedIndex) { _, _ in
      loadHealthData(for: currentScope)
    }
  }
  
  
  private func loadHealthData(for scope: TimeScope) {
    
    let useMockData = true
    
    if useMockData {
      print("当前无真实数据，正在生成模拟演示数据...")
      generateSimulationData(for: scope)
      return
    }
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

// MARK: - Preview
#Preview {
  HealthDashboardView()
}
