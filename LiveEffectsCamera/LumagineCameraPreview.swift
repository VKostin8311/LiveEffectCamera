//
//  LumagineCameraPreview.swift
//  Lumagine
//
//  Created by Владимир Костин on 07.12.2023.
//

import AVFoundation
import MediaPlayer
import Metal
import MetalKit
import SwiftUI

struct LumagineCameraPreview: UIViewRepresentable {
    
    @StateObject var renderer: LumagineCameraViewModel

    func makeUIView(context: Context) -> MTKView {
         
        renderer.mtkView.framebufferOnly = false
        renderer.mtkView.backgroundColor = .clear
        renderer.mtkView.enableSetNeedsDisplay = false
        renderer.mtkView.isPaused = true
        renderer.mtkView.isUserInteractionEnabled = true
        
        let gesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.tapped(_ :)))
        renderer.mtkView.addGestureRecognizer(gesture)
    
        return renderer.mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        
    }
    
    func makeCoordinator() -> LumagineCameraPreview.Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {

        var parent: LumagineCameraPreview
        
        init(_ parent: LumagineCameraPreview) {
            self.parent = parent
            super.init()
        }
        

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            print("Preview point: \(point)")
        }
        
        
    }
    
}
