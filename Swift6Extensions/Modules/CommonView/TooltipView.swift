//
//  Project: Swift6Extensions
//  File: TooltipView.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  
//
import SwiftUI

struct TooltipView: View {
    let point: HealthDataPoint
    
    // 用于格式化 Tooltip 里的时间 (例如: 09:05)
    private var tooltipTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            // 大数值
            Text(String(format: "%.1f", point.value))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black)
            
            // 单位和时间
            VStack(alignment: .leading, spacing: 2) {
                Text("μmol/L") // 你可以根据需要修改单位
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Text(tooltipTimeFormatter.string(from: point.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.exBlue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            // 白色背景 + 圆角 + 阴影
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
        }
    }
}
