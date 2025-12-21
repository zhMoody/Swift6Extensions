import SwiftUI
import CoreBluetooth

struct DeviceMainScreen: View {

	@StateObject private var deviceManager = DeviceManager()

	// UI 状态
	@State private var selectedIndex = 0
	@State private var chartData: [HealthDataPoint] = []
	@State private var showScanBleList = false

	var currentScope: TimeScope {
		let scopes = TimeScope.allCases
		guard selectedIndex >= 0 && selectedIndex < scopes.count else { return .hours8 }
		return scopes[selectedIndex]
	}

	var body: some View {
		MainView {
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

			.task { await loadHealthData(for: currentScope) }
			.onChange(of: selectedIndex) { _, _ in
				Task { await loadHealthData(for: currentScope) }
			}
			Button {
				deviceManager.disconnect()
			} label: {
				Text("断开")
			}
		}
		// MARK: - 3. 蓝牙搜索页集成
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

	private func loadHealthData(for scope: TimeScope) async {
		generateSimulationData(for: scope)
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
		withAnimation(.easeInOut) { self.chartData = points }
	}
}

struct BleScanningSheet_Wrapper: View {
	var onConnectSuccess: (ScannedDevice, CBPeripheral?) -> Void

	var body: some View {
		BleScanningSheet(onConnect: onConnectSuccess)
	}
}


