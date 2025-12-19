//
//  Project: Swift6Extensions
//  File: TimeScope.swift
//  Author: Created by Moody
//  Date: 2025/12/19
//  
//
import SwiftUI

enum TimeScope: String, CaseIterable, Identifiable {
  case hours8 = "8小时"
  case hours12 = "12小时"
  case hours24 = "24小时"
  
  var id: String { rawValue }
  var duration: TimeInterval {
    switch self {
    case .hours8: return 8 * 3600
    case .hours12: return 12 * 3600
    case .hours24: return 24 * 3600
    }
  }
  
  private func snapToNearestHour(_ date: Date) -> Date {
    let calendar = Calendar.current
    let minute = calendar.component(.minute, from: date)
    let adjust = minute >= 30 ? 1 : 0
    let startOfHour = calendar.date(bySetting: .minute, value: 0, of: date)!
    return calendar.date(byAdding: .hour, value: adjust, to: startOfHour)!
  }
  
  func calculateWindow(currentDate: Date = Date()) -> ClosedRange<Date> {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: currentDate)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return currentDate...currentDate }
    
    switch self {
    case .hours24: return startOfDay...endOfDay
    case .hours8, .hours12:
      let center = snapToNearestHour(currentDate)
      let half = duration / 2.0
      var start = center.addingTimeInterval(-half)
      var end = center.addingTimeInterval(half)
      if start < startOfDay {
        start = startOfDay
        end = startOfDay.addingTimeInterval(duration)
      } else if end > endOfDay {
        end = endOfDay
        start = endOfDay.addingTimeInterval(-duration)
      }
      return start...end
    }
  }
  
  func generateTicks(in window: ClosedRange<Date>) -> [Date] {
    let start = window.lowerBound
    let end = window.upperBound
    let step = (end.timeIntervalSince(start)) / 4.0
    return (0...4).map { start.addingTimeInterval(step * Double($0)) }
  }
}
