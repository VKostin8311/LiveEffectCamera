//
//  SampleBufferView.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import SwiftUI
import CoreMedia

struct SampleBufferView: ViewRepresentable {
	
	typealias ViewType = DisplayLayerView
	
	let camera: CameraViewModel
	let preview: DisplayLayerView
	let sampleBuffer: Unchecked<CMSampleBuffer>
	
	func makeView(context: Context) -> DisplayLayerView {

		return preview
	}
	
	func updateView(_ view: DisplayLayerView, context: Context) {
		
		if view.displayLayer.sampleBufferRenderer.isReadyForMoreMediaData {
			view.displayLayer.sampleBufferRenderer.enqueue(sampleBuffer.wrappedValue)
		}
	}
}
