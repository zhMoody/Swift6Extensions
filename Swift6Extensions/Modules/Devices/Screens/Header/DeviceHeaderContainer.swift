//
//  DeviceHeaderContainer.swift
//  Swift6Extensions
//
//  Created by Moody on 2025/12/20.
//

import SwiftUI

struct DeviceHeaderContainer: View {
	@ObservedObject var manager: DeviceManager
	@Binding var showScanSheet: Bool
	
	var body: some View {
		ZStack {
			Color.white
			
			switch manager.displayState {
			case .disconnected:
				Header_NoLinkHeader(showSheet: $showScanSheet)
				
			case .connecting:
				Header_Connecting(sn: "JLUA-CONNECTING...")
				
			case .connectionFailed:
				Header_ConnectionFailed(sn: getCurrentSN() ?? "Unknown") {
					manager.loadState()
				}
				
			case .initializing(let targetDate, let lifeMinutes):
				Header_Countdown(sn: getCurrentSN() ?? "Unknown", targetDate: targetDate, lifeMinutes: lifeMinutes)
				
			case .running(let model):
				Header_DataDisplay(model: model)
			}
		}
		.frame(height: 132)
		.clipShape(RoundedRectangle(cornerRadius: 16))
		.shadow(color: shadowColor.opacity(0.1), radius: 10, x: 0, y: 4)
		.animation(.easeInOut(duration: 0.3), value: manager.displayState)
		.onAppear {
			manager.loadState()
		}
	}
	
	private var shadowColor: Color {
		if case .running(let model) = manager.displayState {
			return model.status.color
		}
		return .exBlue
	}
	
	private func getCurrentSN() -> String? {
		return UserDefaults.standard.string(forKey: AppConstants.Keys.lastDeviceName)
	}
}
