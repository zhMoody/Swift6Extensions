//
//  Project: Swift6Extensions
//  File: MainBackgroundView.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//
//
import SwiftUI

struct MainView<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 20) {
        dot
        Text("尿酸监测")
          .font(.title3)
          .foregroundStyle(.exBlue)
        Text("数据记录")
          .font(.headline)
          .foregroundStyle(.gray)
        Spacer()
        Button {} label: {
          Image(systemName: "message")
            .foregroundStyle(.exBlue)
        }
      }
      content()
    }
    .padding()
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .topLeading
    )
    .background(.exBgGrey)
  }
}

@ViewBuilder
var dot: some View {
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


#Preview {
    MainView {
        Text("Content Area")
            .foregroundStyle(.blue)
    }
}
