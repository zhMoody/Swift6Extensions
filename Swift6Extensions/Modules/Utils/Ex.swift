//
//  Project: Swift6Extensions
//  File: Ex.swift
//  Author: Created by Moody
//  Date: 2025/12/22
//  
//
import Foundation

public nonisolated struct FoundationEx<T> {
  public let t: T
  public init(_ t: T) {
    self.t = t
  }
}

public nonisolated protocol FoundationExCompatible {
  associatedtype E
  static var ex: FoundationEx<E>.Type { get set }
  var ex: FoundationEx<E> { get set }
}

public extension FoundationExCompatible {
  nonisolated static var ex: FoundationEx<Self>.Type {
    get { FoundationEx<Self>.self }
    set {}
  }
  nonisolated var ex: FoundationEx<Self> {
    get { FoundationEx(self) }
    set {}
  }
}

extension String: FoundationExCompatible {}
extension Double: FoundationExCompatible {}
extension Int: FoundationExCompatible {}
extension UInt8: FoundationExCompatible {}
extension UInt16: FoundationExCompatible {}
extension Date: FoundationExCompatible {}
extension Data: FoundationExCompatible {}

extension FoundationEx where T == Int {
  public nonisolated func fromRawValue<R>(for type: R.Type) -> R? where T == R.RawValue, R: RawRepresentable {
    R(rawValue: t)
  }
}

extension FoundationEx where T == UInt8 {
  public nonisolated var hex: String {
    String(format: "%02X", t)
  }
}

extension FoundationEx where T == Double {
  nonisolated var hex: [UInt8] {
    var value = Int64(t)
    guard value > 0 else { return [] }
    var result: [UInt8] = []
    result.reserveCapacity(8)
    while value > 0 {
      result.insert(UInt8(value & 0xFF), at: 0)
      value >>= 8
    }
    return result
  }
}
