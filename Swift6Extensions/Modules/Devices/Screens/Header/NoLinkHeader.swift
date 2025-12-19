//
//  Project: Swift6Extensions
//  File: NoLinkHeader.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  
//
import SwiftUI

struct NoLinkHeader: View {
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



#Preview  {
  NoLinkHeader(showSheet: .constant(false))
}
