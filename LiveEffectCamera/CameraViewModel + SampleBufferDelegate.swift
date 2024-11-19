//
//  CameraViewModel + SampleBufferDelegate.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 14.11.2024.
//

import AVFoundation
import CoreImage
import Foundation

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if connection == hardware.videoOut.connection(with: .video) {
            self.sampleBuffer = sampleBuffer
            self.hardware.preview.draw()
            
            if self.focusImageVisibleSeconds > 0 {
                if let buffer = sampleBuffer.imageBuffer {
                    var ciImage = CIImage(cvImageBuffer: buffer)
                    
                    let center: CGPoint = CGPoint(x: ciImage.extent.size.width/2, y: ciImage.extent.size.height/2)
                    let point = CGPoint(x: center.x - 100, y: center.y - 100)
                    let size = CGSize(width: 200, height: 200)
                    
                    ciImage = ciImage.cropped(to: CGRect(origin: point, size: size))
                    
                    let image = self.hardware.context.createCGImage(ciImage, from: ciImage.extent)
                    
                    DispatchQueue.main.async { self.focusImage = image }
                }
                
                
                self.focusImageVisibleSeconds -= self.activeDevice?.activeVideoMinFrameDuration.seconds ?? 0
                
                
            } else if self.focusImage != nil {
                DispatchQueue.main.async { self.focusImage = nil }
            }
        }
        
        guard canWrite() else { return }
        
        if let sessionAtSourceTime = sessionAtSourceTime {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let duration = Int(timestamp.seconds - sessionAtSourceTime.seconds)
                if self.duration < duration { self.duration = duration }
            }
        } else {
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionAtSourceTime = timestamp
        }
        
        if connection == hardware.audioOut.connection(with: .audio) && self.aInput?.isReadyForMoreMediaData == true {
            self.hardware.writeQueue.async {
                self.aInput?.append(sampleBuffer)
            }
        }
        
        
    }
    
    
}
