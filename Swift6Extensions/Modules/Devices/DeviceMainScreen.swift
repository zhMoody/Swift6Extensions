import SwiftUI
import CoreBluetooth

struct DeviceMainScreen: View {

	@StateObject private var deviceManager = DeviceManager()

	@State private var selectedIndex = 0
	@State private var chartData: [HealthDataPoint] = []
	@State private var showScanBleList = false

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
							deviceManager.disconnect()
						} label: {
							Text("断开连接")
								.foregroundStyle(.red)
								.padding()
						}

						Spacer().frame(height: 40)
					}
					.padding(.horizontal)
				}
				.task { await loadHealthData(for: currentScope) }
				.onChange(of: selectedIndex) { _, _ in
					Task { await loadHealthData(for: currentScope) }
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
											.foregroundStyle(.exBlue)
										Spacer()
										Text("\(day.items.count) 条记录")
											.font(.caption2)
											.foregroundStyle(.gray)
									}
									.padding(.vertical, 4)
								}
							}
						}
					}
					.listStyle(.plain)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.task {
					await deviceManager.generateData()
				}
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

// 辅助 Wrapper 保持不变
struct BleScanningSheet_Wrapper: View {
	var onConnectSuccess: (ScannedDevice, CBPeripheral?) -> Void

	var body: some View {
		BleScanningSheet(onConnect: onConnectSuccess)
	}
}

