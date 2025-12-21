//
//  RadarRippleView.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//

import SwiftUI

struct RadarRippleView: View {
	@State private var isAnimating = false
	@State private var rotation: Double = 0
	
	var body: some View {
		ZStack {
			// MARK: - 核心修改点：替换成了图标组合
			// 1. 核心图标组合 (带呼吸效果)
			ZStack {
				// 1.1 背景光晕圆底 (让图标不至于太单薄)
				Circle()
					.fill(Color.exBlue.opacity(0.15)) // 半透明背景
					.frame(width: 40, height: 40)
				// 添加一点内发光效果
					.overlay(
						Circle()
							.stroke(Color.exBlue.opacity(0.3), lineWidth: 1)
					)
				
				// 1.2 中心图标 (SF Symbol)
				Image(systemName: "dot.radiowaves.left.and.right")
				//				 Image(systemName: "antenna.radiowaves.left.and.right")  备选方案
				//				 Image(systemName: "bluetooth")  备选方案
					.font(.system(size: 20, weight: .semibold))
					.foregroundStyle(Color.exBlue)
				// 给图标本身也加一点点光晕
					.shadow(color: .exBlue.opacity(0.6), radius: 4, x: 0, y: 0)
			}
			// 整体呼吸动画
			.scaleEffect(isAnimating ? 1.1 : 0.9) // 呼吸范围设置得更有弹性一点
			.animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
			
			
			// 2. 旋转的扫描扇形 (保持不变)
			Circle()
				.fill(
					AngularGradient(
						gradient: Gradient(colors: [.clear, .exBlue.opacity(0.05), .exBlue.opacity(0.3)]),
						center: .center
					)
				)
				.frame(width: 140, height: 140)
				.rotationEffect(.degrees(rotation))
				.animation(.linear(duration: 3).repeatForever(autoreverses: false), value: rotation)
			
			// 3. 向外扩散的波纹 (保持不变)
			ForEach(0..<3) { i in
				Circle()
					.stroke(Color.exBlue.opacity(0.3), lineWidth: 1)
					.frame(width: 20, height: 20)
				// 稍微调大了扩散的最终倍数，让它扩散得更远一点
					.scaleEffect(isAnimating ? 7 : 1)
					.opacity(isAnimating ? 0 : 1)
					.animation(
						.easeOut(duration: 2.5)
						.repeatForever(autoreverses: false)
						.delay(Double(i) * 0.8),
						value: isAnimating
					)
			}
		}
		.onAppear {
			isAnimating = true
			rotation = 360
		}
	}
}

// MARK: - Preview (方便你直接看效果)
#Preview {
	ZStack {
		Color.black.opacity(0.1).ignoresSafeArea()
		RadarRippleView()
			.frame(width: 200, height: 200)
	}
}
