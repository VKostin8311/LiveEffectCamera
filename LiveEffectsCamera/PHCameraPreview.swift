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
    
    @StateObject var renderer: PHCameraViewModel
     
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

