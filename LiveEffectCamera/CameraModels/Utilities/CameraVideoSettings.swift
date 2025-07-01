//
//  CameraVideoSettings.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import Foundation

struct CameraVideoSettings: Codable, Equatable {
	var selectedPreset: String = ""
	var videoQuality: VideoQuality = .normal
}

enum VideoQuality: String, Codable, CaseIterable {
	case normal = "NORMAL"
	case high = "HIGH"
	case max = "MAX"
	
	var next: VideoQuality {
		switch self {
		case .normal:
			return .high
		case .high:
			return .max
		case .max:
			return .normal
		}
	}
}
