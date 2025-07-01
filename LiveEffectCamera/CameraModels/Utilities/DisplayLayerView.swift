//
//  DisplayLayerView.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import UIKit
import AVFoundation

final class DisplayLayerView: UIView {

	override class var layerClass: AnyClass {
		AVSampleBufferDisplayLayer.self
	}

	var displayLayer: AVSampleBufferDisplayLayer {
		layer as! AVSampleBufferDisplayLayer
	}
}
