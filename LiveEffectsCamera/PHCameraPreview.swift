//
//  PHCameraPreview.swift
//  PHLow
//
//  Created by Владимир Костин on 06.12.2022.
//

import AVFoundation
import Metal
import MetalKit
import SwiftUI

struct PHCameraPreview: UIViewRepresentable {
    
    @StateObject var renderer: CameraRenderer
     
    func makeUIView(context: Context) -> MTKView {
        
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.backgroundColor = .clear
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.delegate = renderer
        
        renderer.mtkView = view
        
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
    }
    
    
}

class CameraRenderer: NSObject, MTKViewDelegate, ObservableObject {
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let context: CIContext
    let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    var mtkView: MTKView?
    var buffer: CMSampleBuffer?
    var warmth: Float = 0
    var gamma: Float = 0
    
    var assetWriter: AVAssetWriter?
    var assetWriterVideoInput: AVAssetWriterInput?
    var assetWriterAudioInput: AVAssetWriterInput?
    var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var filename = ""
    var time: Double = 0
    var isCapturing: Bool = false
    var isFrontCamera: Bool = false
    
    var pixelBuffer4k: CVPixelBuffer?
    var pixelBuffer2k: CVPixelBuffer?
    
    override init() {
        
        guard let colorSpace = CGColorSpace.init(name: CGColorSpace.displayP3) else { fatalError() }
        
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        self.context = CIContext(
            mtlCommandQueue: self.commandQueue,
            options: [.name: "Renderer", .cacheIntermediates: false, .allowLowPower: false, .highQualityDownsample: true, .workingColorSpace: colorSpace])
        
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        let status4k = CVPixelBufferCreate(kCFAllocatorDefault, 2160, 3840, kCVPixelFormatType_32ARGB, attrs, &self.pixelBuffer4k)
        guard (status4k == kCVReturnSuccess) else { fatalError() }
        
        
        let status2k = CVPixelBufferCreate(kCFAllocatorDefault, 1080, 1920, kCVPixelFormatType_32ARGB, attrs, &self.pixelBuffer2k)
        guard (status2k == kCVReturnSuccess) else { fatalError() }
        
        super.init()
    }
    
    func draw(in view: MTKView) {

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in semaphore.signal() }
            
            if let drawable = view.currentDrawable, let buffer = buffer, let imageBuffer = buffer.imageBuffer {
                
                let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
                
                var image = CIImage(cvImageBuffer: imageBuffer)

                let width = Int(view.drawableSize.width)
                let height = Int(view.drawableSize.height)
                let format = view.colorPixelFormat
                
                let destination = CIRenderDestination(width: width, height: height, pixelFormat: format, commandBuffer: commandBuffer, mtlTextureProvider: { () -> MTLTexture in
                    return drawable.texture
                })
                

                if let filter = CIFilter( name: "CIFaceBalance", parameters: [
                        "inputImage" : image,
                        "inputOrigI" : 0.103905,
                        "inputOrigQ" : 0.0176465,
                        "inputStrength" : 0.5,
                        "inputWarmth" : 0.5 + CGFloat(warmth/20)
                    ]
                ) {
                    if let output = filter.outputImage { image = output }
                }
                
                if let filter = CIFilter(name: "CIGammaAdjust", parameters: ["inputImage" : image, "inputPower" : 1 + gamma/100]) {
                    if let output = filter.outputImage { image = output }
                }
                

                
                if let pixelBuffer4k = pixelBuffer4k, let pixelBuffer2k = pixelBuffer2k {
                
                    if isFrontCamera {
                        context.render(image, to: pixelBuffer2k)
                        if self.assetWriterVideoInput?.isReadyForMoreMediaData == true && isCapturing {
                            
                            self.adaptor?.append(pixelBuffer2k, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(buffer))
                        }
                    } else {
                        context.render(image, to: pixelBuffer4k)
                        if self.assetWriterVideoInput?.isReadyForMoreMediaData == true && isCapturing {
                            self.adaptor?.append(pixelBuffer4k, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(buffer))
                        }
                    }
                    
                }
                

                let scaleFactor = CGFloat(width)/image.extent.size.width
                image = image.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
                
                let origin = CGPoint(
                    x: max(image.extent.size.width - CGFloat(width), 0)/2,
                    y: max(image.extent.size.height - CGFloat(height), 0)/2
                )

                image = image.cropped(to: CGRect(origin: origin, size: view.drawableSize))
                image = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))

                let iRect = image.extent
                let backBounds = CGRect(x: 0, y: 0, width: width, height: height)
                let shiftX = round((backBounds.size.width + iRect.origin.x - iRect.size.width) * 0.5)
                let shiftY = round((backBounds.size.height + iRect.origin.y - iRect.size.height) * 0.5)
                image = image.transformed(by: CGAffineTransform(translationX: shiftX, y: shiftY))
                
                do {
                    try self.context.startTask(toClear: destination)
                    try self.context.prepareRender(image, from: backBounds, to: destination, at: CGPoint.zero)
                    try self.context.startTask(toRender: image, from: backBounds, to: destination, at: CGPoint.zero)
                } catch {
                    assertionFailure("Failed to render to preview view: \(error)")
                }
                
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

}
