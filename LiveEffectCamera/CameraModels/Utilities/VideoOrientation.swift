//
//  VideoOrientation.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import Foundation

enum VideoOrientation : Int {

	case portrait = 1

	case portraitUpsideDown = 2

	case landscapeRight = 3

	case landscapeLeft = 4
	
	
	var angle: CGFloat {
		switch self {
		case .portrait: return 90
		case .portraitUpsideDown: return 270
		case .landscapeRight: return 0
		case .landscapeLeft: return 180
		}
	}
}
