//
//  HardwareContainer.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 15.11.2024.
//


import AVFoundation
import CoreMotion
import Foundation
import MetalKit

final class HardwareContainer {
    
    let sessionQueue = DispatchQueue(label: "session", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit)
    let videoQueue = DispatchQueue(label: "video", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    let writeQueue = DispatchQueue(label: "writeQueue")
    
    let device: MTLDevice
    let preview: MTKView
    let commandQueue: MTLCommandQueue
    let computePipelineState: MTLComputePipelineState
    let context = CIContext()
    
    let mManager: CMMotionManager = .init()
    let session: AVCaptureSession = .init()
    let photoOut: AVCapturePhotoOutput = .init()
    let videoOut: AVCaptureVideoDataOutput = .init()
    let audioOut: AVCaptureAudioDataOutput = .init()
    
    var textureCache: CVMetalTextureCache?
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Can not create MTL Device") }
        self.device = device
        self.preview = MTKView(frame: .zero, device: self.device)
        
        if let layer = self.preview.layer as? CAMetalLayer { layer.colorspace = CGColorSpace(name: CGColorSpace.itur_709) }
        
        guard let commandQueue = self.device.makeCommandQueue() else { fatalError("Can not create command queue") }
        self.commandQueue = commandQueue
        
        guard let library = device.makeDefaultLibrary() else { fatalError("Could not create Metal Library") }
        guard let function = library.makeFunction(name: "cameraKernel") else { fatalError("Unable to create gpu kernel") }
        do {
            self.computePipelineState = try self.device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Unable to create compute pipelane state")
        }
         
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &self.textureCache) == kCVReturnSuccess else { fatalError("Unable to allocate texture cache.") }
        
    }
    
}
