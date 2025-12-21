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

			Text("\(item.value)")
				.fontWeight(.medium)
				.foregroundStyle(color(for: item.value))

			Text(item.status)
				.font(.caption)
				.padding(.horizontal, 6)
				.padding(.vertical, 2)
				.background(color(for: item.value).opacity(0.1))
				.cornerRadius(4)
				.foregroundStyle(color(for: item.value))
				.frame(width: 50)
		}
		.padding(.vertical, 2)
	}

	func color(for value: Int) -> Color {
		if value > 120 { return .orange }
		if value < 70 { return .red }
		return .green
	}
}
