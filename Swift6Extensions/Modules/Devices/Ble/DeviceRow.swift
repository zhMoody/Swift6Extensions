//
//  DeviceRow.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//
import SwiftUI

struct DeviceRow: View {
	let device: ScannedDevice
	@ObservedObject var viewModel: BleScannerViewModel // 传入 VM
	var onConnectAction: () -> Void
	
	// 判断当前行是否是目标行
	var isTarget: Bool { viewModel.targetDeviceId == device.id }
	
	var body: some View {
		HStack {
			// 图标区
			ZStack {
				Circle().fill(Color.exBlue.opacity(0.1))
					.frame(width: 44, height: 44)
				Image(systemName: getIconName())
					.foregroundStyle(.exBlue)
					.font(.system(size: 16, weight: .bold))
					.symbolEffect(.bounce, value: viewModel.connectionState) // iOS 17 动画
			}
			
			// 文字区
			VStack(alignment: .leading, spacing: 4) {
				Text(device.name)
					.font(.system(size: 16, weight: .medium))
					.foregroundStyle(.primary)
				
				HStack(spacing: 6) {
					// 如果正在连接当前设备，显示状态文字，否则显示信号
					if isTarget && viewModel.connectionState == .connecting {
						Text("正在连接...")
							.font(.caption2)
							.foregroundStyle(.exBlue)
					} else if isTarget && viewModel.connectionState == .failed {
						Text("连接失败，请重试")
							.font(.caption2)
							.foregroundStyle(.red)
					} else {
						Image(systemName: "cellularbars", variableValue: Double(device.rssi + 100) / 100.0)
							.font(.caption2)
						Text("RSSI: \(device.rssi)")
							.font(.caption2)
							.monospacedDigit()
					}
				}
				.foregroundStyle(.secondary)
			}
			
			Spacer()
			
			// 交互按钮区
			Button {
				onConnectAction()
			} label: {
				buttonContent
			}
			// 核心逻辑：
			// 1. 如果全局锁定了 (有人在连)，且不是我自己 -> 禁用
			// 2. 如果是我自己，且正在连 (connecting) 或 成功 (connected) -> 禁用 (防止重复点)
			// 3. 只有 "idle" 或 "failed" 状态可以点击
			.disabled(shouldDisableButton)
			.opacity(shouldDimButton ? 0.4 : 1.0)
		}
		.padding(12)
		.background(Color.white)
		.clipShape(RoundedRectangle(cornerRadius: 16))
		.shadow(color: isTarget ? Color.exBlue.opacity(0.15) : Color.black.opacity(0.03),
						radius: isTarget ? 8 : 2, x: 0, y: 1) // 选中时阴影加重
		.scaleEffect(isTarget ? 1.02 : 1.0) // 选中时微微放大
		.animation(.spring, value: viewModel.targetDeviceId)
		.transition(
			.asymmetric(
				insertion: .scale(scale: 0.3).combined(with: .opacity),
				removal: .opacity
			)
		)
	}
	
	// 动态图标
	func getIconName() -> String {
		if isTarget && viewModel.connectionState == .connected {
			return "checkmark.circle.fill"
		}
		return "wave.3.right"
	}
	
	// 按钮内容构建器
	@ViewBuilder
	var buttonContent: some View {
		ZStack {
			// 1. 正常状态 / 失败重试
			if !isTarget || viewModel.connectionState == .idle || viewModel.connectionState == .failed {
				Text(isTarget && viewModel.connectionState == .failed ? "重试" : "连接")
					.font(.caption.bold())
					.padding(.horizontal, 16)
					.padding(.vertical, 8)
					.background(
						Capsule()
							.stroke(isTarget && viewModel.connectionState == .failed ? Color.red : Color.exBlue, lineWidth: 1)
					)
					.foregroundStyle(isTarget && viewModel.connectionState == .failed ? Color.red : Color.exBlue)
			}
			
			// 2. 连接中
			if isTarget && viewModel.connectionState == .connecting {
				HStack(spacing: 6) {
					ProgressView()
						.scaleEffect(0.7)
					Text("连接中")
						.font(.caption.bold())
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(Color.exBlue.opacity(0.1))
				.clipShape(Capsule())
				.foregroundStyle(.exBlue)
			}
			
			// 3. 成功
			if isTarget && viewModel.connectionState == .connected {
				HStack(spacing: 4) {
					Image(systemName: "checkmark")
					Text("已连接")
				}
				.font(.caption.bold())
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.foregroundStyle(.green)
			}
		}
	}
	
	// 逻辑辅助
	var shouldDisableButton: Bool {
		// 如果全局锁定了，且不是我 -> 禁用
		if viewModel.isGlobalLocked && !isTarget { return true }
		// 如果是我，且状态是 连接中 或 已连接 -> 禁用
		if isTarget && (viewModel.connectionState == .connecting || viewModel.connectionState == .connected) { return true }
		return false
	}
	
	var shouldDimButton: Bool {
		// 其他行变淡
		return viewModel.isGlobalLocked && !isTarget
	}
}
