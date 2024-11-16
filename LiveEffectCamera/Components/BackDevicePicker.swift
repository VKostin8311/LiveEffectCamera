//
//  QCBackDevicePicker.swift
//  QuantCap
//
//  Created by Владимир Костин on 26.10.2024.
//

import AVFoundation
import SwiftUI

struct BackDevicePicker: View {
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(CameraViewModel.self) var camera
    
    @Binding var backDevice: BackDeviceType
    @Binding var cameraPosition: AVCaptureDevice.Position
    @Binding var block2x: Bool
    
    var body: some View {
        
        HStack(spacing: 8) {
            
            ForEach(block2x ? camera.backDevices.filter({$0 != .wideAngleX2}) : camera.backDevices, id: \.self) { device in
                Button(action: {
                    withAnimation(.spring(duration: 0.25)) { backDevice = device }
                    camera.start(with: cameraPosition, and: device)
                }) {
                    ZStack {
                        if backDevice == device {
                            RingActiveButtonCircle(size: 32)
                        } else {
                            RingButtonCircle(isWriting: .constant(false), size: 32)
                        }
                        Text("\(deviceDescript(device))X")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colorScheme == .dark && backDevice != device ? Color.lightWood : Color.black)
                            
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
            }
        }
        .padding(4)
        .background{
            Capsule()
                .strokeBorder(Color.lightWood, lineWidth: 0.67, antialiased: true)
        }
        
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
