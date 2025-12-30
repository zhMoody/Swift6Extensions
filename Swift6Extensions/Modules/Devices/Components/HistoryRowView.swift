//
//  HistoryRowView.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/22.
//
import SwiftUI

struct HistoryRowView: View {
	let item: HistoryItem

	var body: some View {
		HStack {
			Text(item.timeString)
				.font(.system(.body, design: .monospaced))
				.foregroundStyle(.gray)

			Spacer()
			
			let val = Double(item.value) ?? 0.0
			let statusColor = getStatusColor(value: val)

			Text(item.value)
				.fontWeight(.medium)
				.foregroundStyle(statusColor)

			Text(item.status)
				.font(.caption)
				.padding(.horizontal, 6)
				.padding(.vertical, 2)
				.background(statusColor.opacity(0.1))
				.cornerRadius(4)
				.foregroundStyle(statusColor)
				.frame(width: 50)
		}
		.padding(.vertical, 2)
	}
	
	private func getStatusColor(value: Double) -> Color {
		// 男性标准: > 416 红, < 208 橙, 其他 黑
		if value > 416 { return .red }
		if value < 208 { return .orange }
		return .exBlue // 正常范围显示黑色
	}
}
