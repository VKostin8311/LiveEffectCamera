//
//  CameraView.swift
//  QuantCap
//
//  Created by Владимир Костин on 26.09.2024.
//

import AVKit
import AVFoundation
import SwiftUI

struct CameraView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @Environment(PermissionsViewModel.self) var permissions
    @Environment(LocationViewModel.self) var location
    
    @State var camera: CameraViewModel = .init()
    
    @AppStorage("backDevice") var backDevice: BackDeviceType = .wideAngle
    @AppStorage("cameraPosition") var cameraPosition: AVCaptureDevice.Position = .back
    @AppStorage("showGrid") var showGrid: Bool = false
    
    let block2x = false
    
    var focusGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                
                if let resultFocus = camera.resultFocus {
                    camera.currentFocus = -Float(gesture.translation.width/400)
                    let result = max(0.0, min(1.0, camera.currentFocus + resultFocus))
                    camera.focusImageVisibleSeconds = 3
                    
                    guard camera.hardware.session.isRunning else { return }
                    
                    try? camera.activeDevice?.lockForConfiguration()
                    camera.activeDevice?.setFocusModeLocked(lensPosition: result)
                    camera.activeDevice?.unlockForConfiguration()
                    
                } else {
                    camera.resultFocus = camera.lensPosition
                }
            }
            .onEnded { gesture in
                camera.resultFocus = nil
                camera.currentFocus = 0
                camera.focusImageVisibleSeconds = 3
            }
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack() {
                Background()
                     
                ZStack() {
                    CameraPreview(camera: camera)
                    if showGrid {
                        HStack(spacing: 0) {
                            Spacer()
                            Color.white.opacity(0.4).frame(width: 1)
                            Spacer()
                            Color.white.opacity(0.4).frame(width: 1)
                            Spacer()
                        }
                        
                        VStack(spacing: 0) {
                            Spacer()
                            Color.white.opacity(0.4).frame(height: 1)
                            Spacer()
                            Color.white.opacity(0.4).frame(height: 1)
                            Spacer()
                        }
                        
                        let angle = Int((camera.inclination*360/(2*Double.pi)) - 0.5)
                        let match = (angle == 0 || angle == -90 || angle == -180 || angle == -270)
                        let height = 16*geo.size.width/9
                        Rectangle()
                            .strokeBorder(
                                match ? Color.accentColor : Color.white.opacity(0.4),
                                lineWidth: match ? 3 : 1,
                                antialiased: true)
                            .frame(
                                width: camera.orientation.rawValue > 2 ? height/3 : geo.size.width/3,
                                height: camera.orientation.rawValue > 2 ? geo.size.width/3 : height/3)
                            .rotationEffect(Angle(radians: camera.inclination))
                    }
                    if let image = camera.focusImage {
                        Image(image, scale: 1, label: Text(""))
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.lightWood, lineWidth: 2, antialiased: true)
                            }
                        
                    }
                }
                .frame(width: geo.size.width, height: 16*geo.size.width/9)
                .position(x: 0.5*geo.size.width, y: 8*geo.size.width/9)
                
                if let poi = camera.pointOfInterest {
                    Capsule()
                        .strokeBorder(Color.lightWood, lineWidth: 2.0/3.0, antialiased: true)
                        .frame(
                            width: camera.orientation.rawValue > 2 ? 96 : 64,
                            height: camera.orientation.rawValue > 2 ? 64 : 96)
                        .opacity(camera.isAdjustingFocus || camera.isAdjustingExposure ? 1.0 : 0.5)
                        .position(x: poi.x, y: poi.y)
                        
                }
                
                VStack(spacing: 0) {
                    
                    if camera.isWriting {
                        HStack(alignment: .center, spacing: 5) {
                            Circle()
                                .frame(width: 6, height: 6)
                                .foregroundStyle(Color.red)
                                .opacity(camera.duration % 2 == 1 ? 1.0 : 0.1)
                            Text(String(format:"%02d:%02d", (camera.duration % 3600) / 60, camera.duration % 60))
                                .foregroundStyle(Color.red)
                                .font(.system(size: 14))
                        }
                        .padding(.top, 48)
                    }
                        
                    Spacer()
                     
                    lutSelector
                    
                    if camera.activeDevice?.isLockingFocusWithCustomLensPositionSupported == true {
                        lensPositioner
                    }
                     
                    BackDevicePicker(backDevice: $backDevice, cameraPosition: $cameraPosition, block2x: .constant(block2x))
                        .environment(camera)
                        .padding(.bottom, camera.isClassicDevice ? 8 : 16)
                    ZStack() {
                        @Bindable var camera = camera
                        
                        HStack() {
                            ZStack() {
                                Image("PreViewTest")
                                    .resizable()
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .padding(4)
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.lightWood, lineWidth: 0.67, antialiased: true)
                            }
                            .frame(width: 88, height: 88)
                            Spacer()
                             
                            Button(action: {
                                withAnimation { camera.showNoise.toggle() }
                            }) {
                                ZStack() {
                                    if camera.showNoise {
                                        RingActiveButtonCircle(size: 32)
                                    } else {
                                        RingButtonCircle(isWriting: .constant(false), size: 32)
                                    }
                                    Image("Noise")
                                        .clipShape(Circle())
                                }
                            }
                            .frame(width: 48, height: 48)
                            
                            
                            FlashAndPositionButtons(supportedTorchModes: $camera.supportedTorchModes, torchMode: $camera.torchMode) {
                                cameraPosition = cameraPosition == .back ? .front : .back
                                camera.start(with: cameraPosition, and: backDevice)
                            }
                        }
                        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        
                        CaptureButton(isWriting: $camera.isWriting) {
                            if camera.isWriting { camera.stopWriting() } else { camera.startWriting() }
                        }
                    }
                }
                .padding(.bottom, camera.isClassicDevice ? 8 : 44)
                
                Image(systemName: "squareshape.split.3x3")
                    .foregroundStyle(showGrid ? Color.accentColor : Color.midGreen)
                    .scaleEffect(1.5)
                    .position(x: geo.size.width/2, y: 80)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.25)) { showGrid.toggle() }
                    }
            }
        }
        .ignoresSafeArea()
        .onChange(of: location.currentLocation) { _, newValue in
            camera.location = newValue
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            location.startLocation()
            camera.prepareCamera()
            camera.start(with: cameraPosition, and: backDevice)
        }
        .onChange(of: camera.torchMode) { _, newValue in
            
            guard let activeDevice = camera.activeDevice else { return }
            
            if activeDevice.isTorchAvailable {
                do {
                    try activeDevice.lockForConfiguration()
                    activeDevice.torchMode = newValue
                    activeDevice.unlockForConfiguration()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            camera.stopSession()
            location.stopLocation()
            camera.hardware.mManager.stopAccelerometerUpdates()
            camera.cancellable.removeAll()
            camera.audioSession.removeObserver(camera, forKeyPath: "outputVolume", context: nil)
            try? camera.audioSession.setActive(false)
        }
    }
    
    var lutSelector: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                
                Button(action: {
                    withAnimation(.spring(duration: 0.25)) {
                        camera.selectedLUT = nil
                        camera.load(lut: camera.selectedLUT ?? "@")
                    }
                }) {
                    ZStack () {
                        Capsule()
                            .foregroundStyle(Color.deepBrown)
                        Text("NONE")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.lightGreen)
                            .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                
                ForEach(camera.luts, id: \.self) { lut in
                    Button(action: {
                        withAnimation(.spring(duration: 0.25)) {
                            camera.selectedLUT = lut
                            camera.load(lut: camera.selectedLUT ?? "@")
                        }
                    }) {
                        ZStack () {
                            Capsule()
                                .foregroundStyle(Color.deepBrown)
                            Text(lut)
                                .font(.system(size: 14, weight: camera.selectedLUT == lut ? .semibold : .regular))
                                .foregroundStyle(camera.selectedLUT == lut ? Color.accentColor : Color.lightGreen)
                                .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                
                        }
                    }
                }
            }
            .frame(height: 32)
            .padding(16)
        }
        .padding(.bottom, 16)
    }
    
    var lensPositioner: some View {
        ZStack(){
            Color.white
                .opacity(0.125)
            GeometryReader() { geometry in
                ForEach(0...50, id: \.self) { i in
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", Double(i)/50))
                            .opacity(i % 5 == 0 ? 1 : 0)
                            .font(.system(size: 8))
                            .frame(height: 20)
                        Rectangle()
                            .foregroundStyle(i % 5 == 0 ? Color.lightWood : Color.white)
                            .frame(width: 1)
                    }
                    .position(x: 0.5*geometry.size.width + CGFloat(i*8) - CGFloat(camera.lensPosition*400) , y: 0.5*geometry.size.height)
                    .opacity(1 - min(1, 3*abs((Double(i)/50) - Double(camera.lensPosition))) )
                }
                VStack(spacing: 0) {
                    Spacer()
                    Color.accentColor
                        .frame(width: 2, height: 30)
                }
                .position(x: 0.5*geometry.size.width, y: 0.5*geometry.size.height)
                
            }
            .frame(height: 40)
            Color.white.opacity(0.004)
                .gesture( focusGesture )
        }
        .frame(height: 64)
    }
    
    func deviceDescript(_ type: BackDeviceType) -> String {
        switch type {
        case .ultraWide: return ".5"
        case .wideAngle: return "1"
        case .wideAngleX2: return "2"
        case .telephoto: return "\(camera.maxOpticalZoom)"
        }
       
    }
    
}



#Preview {
    CameraView()
        .environment(PermissionsViewModel(viewModel: MainViewModel()))
        .environment(LocationViewModel())
}
