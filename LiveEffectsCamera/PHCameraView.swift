//
//  PHCameraView.swift
//  PHLow
//
//  Created by Владимир Костин on 06.12.2022.
//

import AVFoundation
import Combine
import SwiftUI


struct PHCameraView: View {
    
    @Environment(\.safeAreaInsets) private var saInsets
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject var model: PHCameraViewModel = PHCameraViewModel()
    @StateObject var renderer: CameraRenderer = CameraRenderer()
    
    @State var isShowFIlters = false
    
    @State var warmths: Float = 0
    @State var gamma: Float = 0
    
    @State var showVideoButton = true
    
    var body: some View {
        ZStack(alignment: .center) {
            
            ZStack(alignment: .top){
                if model.isRunning {
                    PHCameraPreview(renderer: renderer)
                        .frame(width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.width*16/9, alignment: .center)
                        .scaleEffect(x: model.position == .front ? -1 : 1)
                }
                ZStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 8) {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Circle()
                                .frame(width: 52, height: 52, alignment: .center)
                                .foregroundColor(.black.opacity(0.001))
                                .overlay ( Image("XMark") )
                        }
                        Spacer()
                    }
                    VStack(alignment: .center, spacing: 0) {
                        
                        if model.captureState == .capturing {
                            HStack(alignment: .center, spacing: 5) {
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .foregroundColor(.red)
                                    .opacity(showVideoButton ? 1.0 : 0.1)
                                
                                Text(String(format:"%02d:%02d", (model.duration % 3600) / 60, model.duration % 60))
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    
                }
                
                .padding(EdgeInsets(top: saInsets.top, leading: 0, bottom: 0, trailing: 20))
            }
            
            
            
            if isShowFIlters { filterPanel }
            
            VStack(alignment: .center, spacing: 0) {
                Spacer()
                ZStack(){
                    HStack(){
                        Button(action: {
                            withAnimation { isShowFIlters.toggle() }
                        }) {
                            Image(systemName: "paintpalette")
                                .resizable()
                                .frame(width: 32, height: 32, alignment: .center)
                                .opacity(isShowFIlters ? 1.0 : 0.25)
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    HStack(alignment: .center, spacing: 18) {
                        if model.position == .back {
                            ForEach(model.backDevices, id: \.self) { device in
                                Button(action: {
                                    withAnimation { model.curBackDevice = device }
                                }) {
                                    ZStack(){
                                        Capsule()
                                            .stroke(Color.white, lineWidth: 1)
                                        Text(deviceDescript(device))
                                            .foregroundColor(.white)
                                            .font(.system(size: 12))
                                            .offset(x: 0, y: 2)
                                    }
                                    .opacity(model.curBackDevice == device ? 1.0 : 0.3)
                                }
                                .frame(width: 44, height: 20, alignment: .center)
                                
                            }
                        } else {
                            Capsule()
                                .frame(width: 44, height: 20, alignment: .center)
                                .foregroundColor(.clear)
                        }
                    }
                }
                
                ZStack(alignment: .center) {
                    HStack(alignment: .center, spacing: 28) {
                        Spacer()
                        Button(action: {
                            if model.position == .back { model.position = .front} else {model.position = .back}
                        }) {
                            Image("CameraChangePosition")
                                .resizable()
                                .frame(width: 24, height: 24, alignment: .center)
                        }
                    }
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 25))
                    videoButton
                }
                
            }
            .padding(.bottom, saInsets.bottom + 20)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear{
            model.renderer = renderer
        }
        
        .onChange(of: model.duration) { newValue in
            if newValue % 2 == 1 { withAnimation(.easeInOut(duration: 0.125)) { showVideoButton = false } }
            else { withAnimation(.easeInOut(duration: 0.125)) { showVideoButton = true }
            }
        }
        .onDisappear{
            model.stopSession()
            model.renderer = nil
            model.cancellable.removeAll()
        }
        
    }
    
    var videoButton: some View {
        Button(action: {
            model.capture()
        }) {
            ZStack(){
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 60, height: 60, alignment: .center)
                Image(model.captureState == .capturing ? "SquareVideo" : "VideoButton")
                    .resizable()
                    .frame(width: (model.captureState == .capturing ? 32 : 50), height: (model.captureState == .capturing ? 32 : 50), alignment: .center)
            }
        }
    }
    
    
    
    var filterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            PHSliderH(value: $gamma, center: .constant(0), title: "GAMMA", opacity: .constant(1), id: .constant(""), from: -100, to: 100)
            PHSliderH(value: $warmths, center: .constant(0), title: "WARMTH", opacity: .constant(1), id: .constant(""), from: -100, to: 100)
        }
        .padding(.vertical, 8)
        .background( Color.white.opacity(0.5) )
        
        .onChange(of: gamma) { newValue in
            renderer.gamma = newValue
        }
        .onChange(of: warmths) { newValue in
            renderer.warmth = newValue
        }
    }
    
    
    func flashImage(_ fMode: AVCaptureDevice.FlashMode) -> String {
        switch fMode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off: return "bolt.slash.fill"
        @unknown default:  fatalError("Unsupported flash mode")
        }
    }
    
    func torchImage(_ fMode: AVCaptureDevice.TorchMode) -> String {
        switch fMode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off: return "bolt.slash.fill"
        @unknown default:  fatalError("Unsupported torch mode")
        }
    }
    
    func deviceDescript(_ type: AVCaptureDevice.DeviceType) -> String {
        if type == .builtInTelephotoCamera {return "3X"}
        if type == .builtInUltraWideCamera {return "0.5X"}
        if type == .builtInWideAngleCamera {return "1X"}
        return ""
    }
    
}


struct PHSliderH: View {
    
    @Binding var value: Float
    @Binding var center: Float
    let title: String
    @Binding var opacity: CGFloat
    @Binding var id: String
    let from: Float
    let to: Float
    
    
    @State var scale: CGFloat = 1
    
    let c: CGFloat = 14
    let d: CGFloat = 16
    let p: CGFloat = 16

    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    let click = UISelectionFeedbackGenerator()
    
    var body: some View {
        GeometryReader() { geo in
        
            VStack(alignment: .center, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    Text(title)
                        .kerning(1)
                    Spacer()
                    Text(String(Int(value)))
                }
                .font(.system(size: 10, weight: .regular, design: .default))
                .frame(width: geo.size.width - 2*p)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: geo.size.width, height: 24, alignment: .center)
                    Rectangle()
                        .opacity(0.2)
                        .frame(width: geo.size.width - 2*p, height: 2)
                        .offset(x: p, y: 0)
                    Rectangle()
                        .opacity(0.2)
                        .frame(width: 1, height: 24)
                        .offset(x: CGFloat(center)*scale + CGFloat(-from)*scale - 0.5 + p, y: 0)
                    ZStack(){
                        Capsule().foregroundColor(.white)
                        Capsule().strokeBorder(Color.black, lineWidth: 1, antialiased: true)
                    }
                    .frame(width: d + CGFloat(abs(value - center))*scale, height: d)
                    
                    .offset(x: CGFloat(center)*scale + CGFloat(-from)*scale - d/2 + p, y: 0)
                    .offset(x: value < center ? CGFloat(value - center)*scale : 0, y: 0)
                    Circle()
                        .foregroundColor(.white)
                        .overlay(
                            ZStack(){
                                Circle()
                                    .foregroundColor(Color(hex: "#F2EAE0"))
                                Circle()
                                    .strokeBorder(Color(hex: "#E3D0B7"), lineWidth: 1, antialiased: true)
                            }
                                .frame(width: 6, height: 6, alignment: .center)
                        )
                    
                        .frame(width: c, height: c)
                        .offset(x: CGFloat(value - from)*scale - c/2 + p, y: 0)
                        .onTapGesture(count: 2, perform: {
                            withAnimation { value = center }
                        })
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged{ gesture in
                                    let result = Float(Int(gesture.location.x/scale)) + from
                                    if result >= from && result <= to { value = result }
                                }
                                .onEnded { _ in
                                    impactMed.impactOccurred()
                                }
                        )
                }
                
            }
            .opacity(id == title ? 1.0 : opacity)
            .onAppear{
                scale = (geo.size.width - 2*p)/CGFloat(to - from)
            }
            .onChange(of: value) { newValue in
                if id != title { id = title }
                if newValue == center { impactMed.impactOccurred() }
                else { click.selectionChanged() }
            }
        }
        .frame(height: 36)
    }
}
