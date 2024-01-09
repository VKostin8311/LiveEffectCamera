//
//  LumagineCameraView.swift
//  Lumagine
//
//  Created by Владимир Костин on 20.11.2023.
//

import AVFoundation
import SwiftUI

struct LumagineCameraView: View {

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.safeAreaInsets) var saInsets
    
    @StateObject var camera = LumagineCameraViewModel()
    
    let cubes = ["None", "BW-1", "BW-2"]
    
    var body: some View {
        ZStack(){
            Color.black
            LumagineCameraPreview(renderer: camera)
                .frame(width: UIScreen.sWidth, height: camera.captureMode == .photo ? 4*UIScreen.sWidth/3 : 16*UIScreen.sWidth/9)
            
            
            HStack(spacing: 0) {
                exitButton
                Spacer()
            }
            .padding(.horizontal, 16)
            .position(x: 0.5*UIScreen.sWidth, y: saInsets.top + 16)
            VStack(){
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(cubes, id: \.self) { cube in
                            Button(action: {
                                camera.lut = cube
                            }) {
                                ZStack(){
                                    Color.white.opacity(0.5)
                                    Text(cube)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .frame(height: 24)
                        }
                    }
                }
                Slider(value: $camera.intensity, in: 0...100)
            }
            .padding(16)
            .background(content: {
                Color.orange.opacity(0.1)
            })
            .position(x: 0.5*UIScreen.sWidth, y: UIScreen.sHeight - 128 - 0.5*saInsets.bottom)
            shutterButton
                .position(x: 0.5*UIScreen.sWidth, y: UIScreen.sHeight - 44 - 0.5*saInsets.bottom)
                
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear {
            camera.captureMode = .video
        }
        .onDisappear {
            camera.stopSession()
            camera.cancellable.removeAll()
            camera.mManager.stopAccelerometerUpdates()
        }
    }
    
    var shutterButton: some View {
        ZStack(){
            Circle()
                .strokeBorder(Color.black, lineWidth: 1, antialiased: true)
                .frame(width: 72, height: 72)
            Button(action: {
                
                    if camera.isCapturing { camera.stopWriting() } else { camera.startWriting() }
                
            }) {
                ZStack(){
                    RoundedRectangle(cornerRadius: camera.captureMode == .video && camera.isCapturing ? 4 : 28)
                        .foregroundStyle(Color.red)
                        .frame(width: camera.captureMode == .video && camera.isCapturing ? 40 : 56, height: camera.captureMode == .video && camera.isCapturing ? 40 : 56)
                    RoundedRectangle(cornerRadius: camera.captureMode == .video && camera.isCapturing ? 8 : 32)
                        .foregroundStyle(Color.red)
                        .frame(width: camera.captureMode == .video && camera.isCapturing ? 48 : 64, height: camera.captureMode == .video && camera.isCapturing ? 48 : 64)
                }
            }
        }
    }
     
    var exitButton: some View {
        Button(action: {
            presentationMode.wrappedValue.dismiss()
        }) {
            ZStack(){
                RoundedRectangle(cornerRadius: 4)
                    .foregroundStyle(Color.yellow)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.black, lineWidth: 1, antialiased: true)
                Image(systemName: "xmark")
                    .resizable()
                    .foregroundStyle(Color.black)
                    .padding(6)
            }
            .frame(width: 32, height: 32)
        }
    }
    

    func flashImage(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off: return "bolt.slash.fill"
        @unknown default:  fatalError("Unsupported flash mode")
        }
    }
    
    func torchImage(_ mode: AVCaptureDevice.TorchMode) -> String {
        switch mode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off: return "bolt.slash.fill"
        @unknown default:  fatalError("Unsupported torch mode")
        }
    }
        
    
}

#Preview {
    LumagineCameraView()
}


