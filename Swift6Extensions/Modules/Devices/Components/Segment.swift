//
//  Project: Swift6Extensions
//  File: Segment.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//
//
import SwiftUI

struct AdvancedSegmentedControl: View {
	let items: [String]
	@Binding var selectedIndex: Int
	var activeColor: Color = .blue
	var inactiveColor: Color = .gray
	var indicatorColor: Color = .blue
	var backgroundColor: Color = Color(uiColor: .systemGray6)
	var containerHeight: CGFloat = 43
	var cornerRadius: CGFloat = 21.5
	
	@Namespace private var animationNamespace
	
	var body: some View {
		HStack(spacing: 0) {
			ForEach(items.indices, id: \.self) { index in
				SegmentItem(
					title: items[index],
					isSelected: selectedIndex == index,
					activeColor: activeColor,
					inactiveColor: inactiveColor,
					indicatorColor: indicatorColor,
					namespace: animationNamespace
				)
				.contentShape(Rectangle())
				.onTapGesture {
					let generator = UIImpactFeedbackGenerator(style: .light)
					generator.impactOccurred()
					
					withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
						selectedIndex = index
					}
				}
			}
		}
		.frame(height: containerHeight)
		.background(
			RoundedRectangle(cornerRadius: cornerRadius)
				.fill(backgroundColor)
		)
	}
}

private struct SegmentItem: View {
	let title: String
	let isSelected: Bool
	let activeColor: Color
	let inactiveColor: Color
	let indicatorColor: Color
	let namespace: Namespace.ID
	
	var body: some View {
		VStack(spacing: 4) {
			Text(title)
				.font(.system(size: 15, weight: isSelected ? .semibold : .medium))
				.foregroundStyle(isSelected ? activeColor : inactiveColor)
				.frame(maxWidth: .infinity)
			
			if isSelected {
				Capsule()
					.fill(indicatorColor)
					.frame(width: 20, height: 3)
					.matchedGeometryEffect(id: "indicator", in: namespace)
			} else {
				Capsule()
					.fill(.clear)
					.frame(width: 20, height: 3)
			}
		}
		.padding(.top, 4)
	}
}

struct SegmentTestView: View {
	@State private var currentIndex = 0
	let categories = ["推荐", "热门", "动画", "科技"]
	
	var body: some View {
		VStack(spacing: 30) {
			Text("当前选择 Index: \(currentIndex)")
				.monospacedDigit()
			
			// 1. 默认样式
			AdvancedSegmentedControl(
				items: categories,
				selectedIndex: $currentIndex
			)
			
			// 2. 高度自定义样式 (赛博朋克风/暗黑风)
			AdvancedSegmentedControl(
				items: ["日榜", "周榜", "月榜"],
				selectedIndex: $currentIndex,
				activeColor: .green,
				inactiveColor: .white.opacity(0.4),
				indicatorColor: .green,
				backgroundColor: .black,
				containerHeight: 50
			)
		}
		.padding()
		.background(Color(uiColor: .systemGroupedBackground))
	}
}

#Preview {
	SegmentTestView()
}
