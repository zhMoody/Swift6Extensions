//
//  Project: Swift6Extensions
//  File: MainBackgroundView.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  Modified: 2025/12/21 (Added Paging Support)
//

import SwiftUI

struct MainView<Content1: View, Content2: View>: View {

	@State private var selectedIndex: Int = 0

	@ViewBuilder let pageOne: () -> Content1
	@ViewBuilder let pageTwo: () -> Content2

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {

			// MARK: Header Area
			HStack(spacing: 20) {
				dotView

				Text("数据监测")
					.font(.title3)
					.foregroundStyle(selectedIndex == 0 ? .exBlue : .gray)
					.onTapGesture {
						withAnimation { selectedIndex = 0 }
						UIImpactFeedbackGenerator(style: .light).impactOccurred()
					}

				Text("数据记录")
					.font(.title3)
					.foregroundStyle(selectedIndex == 1 ? .exBlue : .gray)
					.onTapGesture {
						withAnimation { selectedIndex = 1 }
						UIImpactFeedbackGenerator(style: .light).impactOccurred()
					}

				Spacer()

//				Button {} label: {
//					Image(systemName: "message")
//						.foregroundStyle(.exBlue)
//				}
			}
			.padding(.horizontal)

			TabView(selection: $selectedIndex) {
				pageOne()
					.tag(0)
				pageTwo()
					.tag(1)
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
			.animation(.easeInOut, value: selectedIndex)

		}
		.padding(.top)
		.frame(
			maxWidth: .infinity,
			maxHeight: .infinity,
			alignment: .topLeading
		)
		.background(.exBgGrey)
		.ignoresSafeArea(edges: .bottom)
	}
}

extension MainView {
	@ViewBuilder
	var dotView: some View {
		HStack(spacing: 6) {
			VStack(spacing: 6) {
				Circle()
					.frame(width: 4, height: 4)
					.foregroundStyle(.exBlue)
				Circle()
					.frame(width: 4, height: 4)
					.foregroundStyle(.exBlue)
			}
			VStack(spacing: 6) {
				Circle()
					.frame(width: 4, height: 4)
					.foregroundStyle(.exBlue)
				Circle()
					.frame(width: 4, height: 4)
					.foregroundStyle(.exBlue)
			}
		}
	}
}

// MARK: - Preview
#Preview {
	MainView(
		pageOne: {
			ZStack {
				RoundedRectangle(cornerRadius: 12)
					.fill(Color.white)
					.shadow(radius: 2)
				Text("实时监测数据图表区")
					.foregroundStyle(.blue)
			}
			.padding()
		},
		pageTwo: {
			ZStack {
				RoundedRectangle(cornerRadius: 12)
					.fill(Color.white.opacity(0.8))
					.shadow(radius: 2)
				VStack {
					Text("历史记录列表")
						.font(.headline)
					List(0..<5) { i in
						Text("记录条目 #\(i)")
					}
					.listStyle(.plain)
				}
			}
			.padding()
		}
	)
}
