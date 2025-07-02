//
//  SessionStatus.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import Foundation

struct SessionStatus: Codable, Equatable {
	
	var position: CameraPosition = .back
	var backDevice: BackDeviceType = .wideAngleCamera
	var frameRate: VideoFrameRate = .extra
	var videoResolution: VideoResolution = .fullHD
	var isVideoMirrored: Bool = true
}

enum CameraPosition: Codable {
	case front
	case back
}

enum BackDeviceType: Codable {
	case ultraWideAngleCamera
	case wideAngleCamera
	case wideAngleX2Camera
	case telephotoCamera
}

enum VideoFrameRate: Int, Codable, CaseIterable {
	case low = 24
	case medium = 30
	case high = 60
	case extra = 120
	
	var next: VideoFrameRate {
		switch self {
		case .low:
			return .medium
		case .medium:
			return .high
		case .high:
			return .extra
		case .extra:
			return .low
		}
	}
}

enum VideoResolution: Int, Codable {
	case fullHD = 1080
	case _4k = 2160
	
	var description: String {
		switch self {
		case .fullHD:
			return "1080p"
		case ._4k:
			return "4K"
		}
	}
}
