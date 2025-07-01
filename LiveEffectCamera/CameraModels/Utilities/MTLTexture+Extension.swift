//
//  MTLTexture+Extension.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import Metal

extension MTLTexture {
	
	func threadGroupCount() -> MTLSize {
		return MTLSizeMake(8, 8, 1)
	}
	
	func threadGroups() -> MTLSize {
		let groupCount = threadGroupCount()
		return MTLSize(width: (Int(width) + groupCount.width-1)/groupCount.width,
					   height: (Int(height) + groupCount.height-1)/groupCount.height,
					   depth: 1)
	}

}
