//
//  ScannedDeviceModal.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//
import Foundation

// 状态机枚举
enum ConnectionState: Equatable {
	case idle           // 闲置
	case connecting     // 连接中
	case connected      // 已连接
	case failed         // 失败
}
