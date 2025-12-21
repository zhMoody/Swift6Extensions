import SwiftUI

// 从未连接过设备
struct Header_NoLinkHeader: View {
	@Binding var showSheet: Bool
	
	var body: some View {
		HStack(spacing: 20) {
			VStack {
				VStack {
					Image(systemName: "infinity")
						.font(.system(size: 24))
						.foregroundColor(.exBlue)
						.symbolEffect(.pulse)
				}
				.frame(width: 60, height: 60)
				.background(Color.white)
				.clipShape(.circle)
				.shadow(color: .exBlue.opacity(0.25), radius: 20, x: 0, y: 0)
			}
			.frame(width: 86, height: 86)
			.background()
			.clipShape(.circle)
			.overlay {
				Circle()
					.stroke(.white, lineWidth: 8)
			}
			.shadow(color: .exBlue.opacity(0.25), radius: 10, x: 0, y: 0)
			
			VStack(spacing: 10) {
				Text("请点击“关联设备”，进行设备配对过程")
					.font(.caption2)
				
				Button {
					showSheet = true
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
				} label: {
					HStack {
						Text("点击关联设备")
							.font(.caption)
							.foregroundStyle(.exBlue)
					}
					.frame(width: 123, height: 32)
					.overlay {
						RoundedRectangle(cornerRadius: 16)
							.stroke(.exBlue, lineWidth: 2)
					}
				}
			}
		}
		.frame(maxWidth: .infinity)
		.frame(height: 132, alignment: .leading)
	}
}

// 连接中 (Loading)
struct Header_Connecting: View {
	let sn: String
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			topSN(sn)
			Spacer()
			HStack(spacing: 16) {
				ProgressView()
					.scaleEffect(1.2)
					.tint(.exBlue)
					.frame(width: 40, height: 40)
					.background(Circle().fill(Color.exBlue.opacity(0.1)))
				
				VStack(alignment: .leading, spacing: 4) {
					Text("连接中")
						.font(.system(size: 16, weight: .bold))
						.foregroundStyle(.exBlue)
					Text("预警参考值（男性）")
						.font(.system(size: 10))
						.foregroundStyle(.gray)
				}
			}
			.padding(.horizontal, 20)
			Spacer()
			bottomInfo(deviceStatus: "连接中")
		}
	}
}

// 3.3 连接失败 (Retry)
struct Header_ConnectionFailed: View {
	let sn: String
	var onRetry: () -> Void
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			topSN(sn)
			Spacer()
			HStack {
				Text("— . —")
					.font(.system(size: 30, weight: .black))
					.foregroundStyle(.primary)
				Spacer()
				Button(action: onRetry) {
					Text("重新连接")
						.font(.system(size: 12, weight: .medium))
						.padding(.horizontal, 16)
						.padding(.vertical, 8)
						.background(Color.exBlue.opacity(0.1))
						.foregroundStyle(.exBlue)
						.clipShape(Capsule())
				}
				Spacer()
				Image(systemName: "power")
					.font(.system(size: 20))
					.foregroundStyle(.primary)
			}
			.padding(.horizontal, 20)
			Spacer()
			bottomInfo(deviceStatus: "未连接")
		}
	}
}

// 3.4 倒计时 (Initialization) - 纯视图，只负责显示
//struct Header_Countdown: View {
//		let sn: String
//		let seconds: Int // 接收计算好的秒数
//
//		var body: some View {
//				VStack(alignment: .leading, spacing: 0) {
//						topSN(sn)
//						Spacer()
//						Text(formattedTime)
//								.font(.system(size: 44, weight: .bold))
//								.foregroundStyle(.primary)
//								.padding(.leading, 20)
//								.contentTransition(.numericText())
//						Spacer()
//						HStack(spacing: 4) {
//								Text("设备初始化中（倒计时）")
//								Text("|").padding(.horizontal, 4)
//								Text("蓝牙：")
//								Text("已连接").foregroundStyle(.exBlue)
//						}
//						.font(.system(size: 11)).foregroundStyle(.gray)
//						.padding(.horizontal, 20).padding(.bottom, 16)
//				}
//		}
//
//		var formattedTime: String {
//				let h = seconds / 3600
//				let m = (seconds % 3600) / 60
//				let s = seconds % 60
//				return String(format: "%02d:%02d:%02d", h, m, s)
//		}
//}

struct Header_Countdown: View {
	let sn: String
	let targetDate: Date // 1. 接收结束时间 (保持你的逻辑纯洁性)
	
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			topSN(sn)
			Spacer()
			
			// 2. 使用 TimelineView 创建每秒刷新的机制
			// 这比外部 Timer 更高效，只影响这个 Text 的渲染
			TimelineView(.periodic(from: .now, by: 1.0)) { context in
				
				// 3. 动态计算剩余秒数
				let seconds = Int(max(0, targetDate.timeIntervalSince(context.date)))
				
				Text(formatTime(seconds))
					.font(.system(size: 44, weight: .bold))
					.foregroundStyle(.primary)
					.padding(.leading, 20)
				// 4. 关键：防止数字变动时宽度跳动
					.monospacedDigit()
				// 5. 关键：保留你喜欢的数字滚动动画
					.contentTransition(.numericText())
				// 6. 确保动画流畅触发
					.animation(.default, value: seconds)
			}
			
			Spacer()
			HStack(spacing: 4) {
				Text("设备初始化中（倒计时）")
				Text("|").padding(.horizontal, 4)
				Text("蓝牙：")
				Text("已连接").foregroundStyle(.exBlue)
			}
			.font(.system(size: 11)).foregroundStyle(.gray)
			.padding(.horizontal, 20).padding(.bottom, 16)
		}
	}
	
	// 格式化逻辑 (HH:MM:SS)
	private func formatTime(_ totalSeconds: Int) -> String {
		let h = totalSeconds / 3600
		let m = (totalSeconds % 3600) / 60
		let s = totalSeconds % 60
		return String(format: "%02d:%02d:%02d", h, m, s)
	}
}


// 3.5 正常数据 (Running)
struct Header_DataDisplay: View {
	let model: DeviceDataModel
	
	var body: some View {
		VStack(spacing: 0) {
			topSN(model.serialNumber)
			HStack(alignment: .center, spacing: 0) {
				HStack(alignment: .bottom, spacing: 4) {
					Text(model.valueString)
						.font(.system(size: 40, weight: .semibold))
						.foregroundStyle(model.status.color)
						.contentTransition(.numericText())
					Text("µmol/L")
						.font(.system(size: 12))
						.foregroundStyle(.gray)
						.padding(.bottom, 8)
				}
				Spacer()
				Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 1, height: 40).padding(.horizontal, 16)
				VStack(alignment: .leading, spacing: 4) {
					HStack(spacing: 4) {
						Text(model.status.title)
							.font(.system(size: 14, weight: .bold))
							.foregroundStyle(model.status.color)
						Image(systemName: model.status.icon)
							.font(.system(size: 14))
							.foregroundStyle(model.status.color)
					}
					Text("预警参考值（女性）").font(.system(size: 10)).foregroundStyle(.gray.opacity(0.8))
				}
				.frame(minWidth: 100, alignment: .leading)
			}
			.padding(.horizontal, 20).padding(.vertical, 20)
			bottomInfo(deviceStatus: "已连接", highlightStatus: true)
		}
	}
}

// 需要把这个辅助函数也加上，或者放在原来的位置
fileprivate func topSN(_ sn: String) -> some View {
	HStack {
		Text("设备序列号：\(sn)")
			.font(.system(size: 10))
			.foregroundStyle(.gray.opacity(0.8))
		Spacer()
	}
	.padding(.horizontal, 20).padding(.top, 16)
}

private func bottomInfo(deviceStatus: String, highlightStatus: Bool = false) -> some View {
	HStack {
		Text(Date().formatted(date: .numeric, time: .shortened))
		Spacer()
		Text("剩余：10天")
		Text("|").padding(.horizontal, 4)
		HStack(spacing: 4) {
			Text("设备：")
			Text(deviceStatus).foregroundStyle(highlightStatus ? Color.exBlue : .gray)
		}
	}
	.font(.system(size: 11)).foregroundStyle(.gray)
	.padding(.horizontal, 20).padding(.bottom, 16)
}
