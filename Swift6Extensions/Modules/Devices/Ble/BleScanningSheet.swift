import SwiftUI
import CoreBluetooth

struct BleScanningSheet: View {
	var onConnect: ((ScannedDevice, CBPeripheral?) -> Void)?
	
	@StateObject private var scanner = BleScannerViewModel()
	@Environment(\.dismiss) var dismiss
	
	var body: some View {
		VStack(spacing: 0) {
			ZStack {
				LinearGradient(
					colors: [Color.exBlue.opacity(0.1), Color.clear],
					startPoint: .top,
					endPoint: .bottom
				)
				.ignoresSafeArea()
				
				VStack(spacing: 20) {
					Text(titleText)
						.font(.headline)
						.foregroundStyle(.secondary)
						.padding(.top, 20)
						.id("Title-\(scanner.connectionState)")
					RadarRippleView().frame(height: 120)
				}
				Spacer().frame(height: 10)
			}
			.frame(height: 230)
			
			ScrollView {
				LazyVStack(spacing: 12) {
					ForEach(scanner.foundDevices) { device in
						DeviceRow(
							device: device,
							viewModel: scanner,
							onConnectAction: {
								// 连接逻辑
								scanner.connect(to: device) { connectedDevice, peripheral in
									// ⚠️ 传递 peripheral
									onConnect?(connectedDevice, peripheral)
									dismiss()
								}
							}
						)
					}
				}
				.padding()
			}
			.background(Color.exBgGrey)
			.disabled(scanner.isGlobalLocked)
			
			// 取消按钮
			Button {
				scanner.stopScanning()
				dismiss()
			} label: {
				Text("取消")
				// ... 保持原样 ...
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding()
					.background(Color.white)
					.foregroundStyle(scanner.isGlobalLocked ? .gray : .red)
					.clipShape(RoundedRectangle(cornerRadius: 12))
			}
			.padding()
			.background(Color.exBgGrey)
			.disabled(scanner.isGlobalLocked)
		}
		.interactiveDismissDisabled(scanner.isGlobalLocked)
		.onAppear {
			scanner.startScanning()
		}
	}
	
	var titleText: String {
		switch scanner.connectionState {
		case .connecting: return "正在建立连接..."
		case .connected: return "连接成功"
		default: return "搜索设备中..."
		}
	}
}
// MARK: - Preview
#Preview {
	Text("Host View")
		.sheet(isPresented: .constant(true)) {
			BleScanningSheet()
		}
}

