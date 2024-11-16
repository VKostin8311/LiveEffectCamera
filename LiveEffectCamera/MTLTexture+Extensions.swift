//
//  MTLTexture+Extensions.swift
//  QuantCap
//
//  Created by Владимир Костин on 19.10.2024.
//

import AVFoundation
import Foundation
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
    
    func bytes() -> UnsafeMutableRawPointer? {
        let width = self.width
        let height = self.height
        let rowBytes = self.width * 4
        if let p = malloc(width * height * 4) {
            
            self.getBytes(p, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            
            return p
        } else {
            return nil
        }
    }
  
}

extension Data {
    
    var float: Float {
        get {
            let value = self.withUnsafeBytes{$0.load(as: Float.self)}
            return value
        }
    }
}

extension AVCaptureDevice.FlashMode: Codable {
    
}
