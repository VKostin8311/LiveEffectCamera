//
//  CameraViewModel + MTKViewDelegate.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 14.11.2024.
//

import Foundation
import MetalKit
import AVFoundation

extension CameraViewModel: MTKViewDelegate {
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        
        guard let sampleBuffer = sampleBuffer, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        var luminanceCVTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, hardware.textureCache!, imageBuffer, nil, .r8Unorm, width, height, 0, &luminanceCVTexture)

        var crominanceCVTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, hardware.textureCache!, imageBuffer, nil, .rg8Unorm, width/2, height/2, 1, &crominanceCVTexture)

        guard let luminanceCVTexture = luminanceCVTexture,
              let inputLuminance = CVMetalTextureGetTexture(luminanceCVTexture),
              let crominanceCVTexture = crominanceCVTexture,
              let inputCrominance = CVMetalTextureGetTexture(crominanceCVTexture)
        else { return }

        DispatchQueue.main.async {
            self.hardware.preview.drawableSize = CGSize(width: width, height: height)
        }
        
        guard let drawable: CAMetalDrawable = self.hardware.preview.currentDrawable else  { return }
        guard let commandBuffer = hardware.commandQueue.makeCommandBuffer(), let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

        computeCommandEncoder.setComputePipelineState(hardware.computePipelineState)
        computeCommandEncoder.setTexture(inputLuminance, index: 0)
        computeCommandEncoder.setTexture(inputCrominance, index: 1)
        computeCommandEncoder.setTexture(drawable.texture, index: 2)
        
        if let cubeBuffer = self.cubeBuffer {
            computeCommandEncoder.setBuffer(cubeBuffer.0, offset: 0, index: 0)
            computeCommandEncoder.setBuffer(cubeBuffer.1, offset: 0, index: 1)
        } else {
            let lutSizeBuffer = self.hardware.device.makeBuffer(bytes: [2], length: MemoryLayout<Int>.size)
            computeCommandEncoder.setBuffer(lutSizeBuffer, offset: 0, index: 0)
            let lutBuffer = self.hardware.device.makeBuffer(bytes: neutralLutArray, length: neutralLutArray.count * MemoryLayout<SIMD4<Float>>.stride, options: [])
            computeCommandEncoder.setBuffer(lutBuffer, offset: 0, index: 1)
        }
        
        computeCommandEncoder.setBytes([Float(self.showNoise ? 1.0 : 0.0)], length: 1 * MemoryLayout<Float>.size, index: 2)
        computeCommandEncoder.setBytes([Float(stamp.seconds)], length: 1 * MemoryLayout<Float>.size, index: 3)
        
        computeCommandEncoder.dispatchThreadgroups(inputLuminance.threadGroups(), threadsPerThreadgroup: inputLuminance.threadGroupCount())
        computeCommandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { buffer in
            
            self.hardware.writeQueue.async {
                 
                guard let adaptor = self.adaptor else { return }
                guard self.isWriting && self.assetWriter?.status == .writing && self.sessionAtSourceTime != nil && self.vInput?.isReadyForMoreMediaData == true
                else { return }
                
                var pixelBuffer: CVPixelBuffer?
                let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
                
                guard let pixelBuffer = pixelBuffer, pixelBufferStatus == kCVReturnSuccess else { return }
                
                CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                
                let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                
                guard let liminanceBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0), let chrominanceBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
                else { return }
                
                inputLuminance.getBytes(liminanceBytes, bytesPerRow: lumaBytesPerRow, from: MTLRegionMake2D(0, 0, inputLuminance.width, inputLuminance.height), mipmapLevel: 0)
                inputCrominance.getBytes(chrominanceBytes, bytesPerRow: chromaBytesPerRow, from: MTLRegionMake2D(0, 0, inputCrominance.width, inputCrominance.height), mipmapLevel: 0)
 
                if (!adaptor.append(pixelBuffer, withPresentationTime: stamp)) { print("Problem appending pixel buffer at time: \(stamp)") }
                
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            }
        }
        
        commandBuffer.commit()
        
    }
    
    
}
