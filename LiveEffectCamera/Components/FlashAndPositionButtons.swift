//
//  QCFlashAndPositionButtons.swift
//  QuantCap
//
//  Created by Владимир Костин on 27.10.2024.
//

import AVFoundation
import SwiftUI

struct FlashAndPositionButtons: View {
    
    @Environment(\.colorScheme) var colorScheme
    @Binding var supportedTorchModes: [AVCaptureDevice.TorchMode]
    @Binding var torchMode: AVCaptureDevice.TorchMode
    
    let action: () -> Void
    
    let size: CGFloat = 39.5
    
    let innerLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let outLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .bottomTrailing, endPoint: .topLeading)
    let innerDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let outDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5)], startPoint: .bottomTrailing, endPoint: .topLeading)
    
    
    var body: some View {
        ZStack() {
            Capsule()
                .strokeBorder(Color.lightWood, lineWidth: 0.67, antialiased: true)
                .frame(width: 8 + size, height: 8 + (supportedTorchModes.count > 1 ? 2*size : size))
            VStack(spacing: 1) {
                
                if supportedTorchModes.count > 1 {
                    Button(action: {
                        guard supportedTorchModes.count > 1 else { return }
                        
                        guard let index = supportedTorchModes.firstIndex(of: torchMode) else { return }
                        
                        if index == supportedTorchModes.count - 1 { torchMode = supportedTorchModes[0] }
                        else { torchMode = supportedTorchModes[index + 1] }
                    }) {
                        ZStack() {
                            ZStack {
                                Color.white
                                switch colorScheme {
                                case .dark: outDark
                                default: outLight
                                }
                            }
                            .frame(width: size, height: size)
                            .clipShape(.rect(topLeadingRadius: 0.5*size, topTrailingRadius: 0.5*size))
                            
                            ZStack {
                                Color.white
                                switch colorScheme {
                                case .dark: innerDark
                                default: innerLight
                                }
                            }
                            .frame(width: 0.9*size, height: 0.9*size)
                            .clipShape(.rect(topLeadingRadius: 0.45*size, topTrailingRadius: 0.45*size))
                            Image(systemName: torchImage(torchMode))
                                .foregroundStyle(colorScheme == .dark ? Color.lightWood : Color.black)
                                .offset(y: 2)
                        }
                        
                    }
                }
                
                Button(action: {
                    action()
                }) {
                    ZStack() {
                        ZStack {
                            Color.white
                            switch colorScheme {
                            case .dark: outDark
                            default: outLight
                            }
                        }
                        .frame(width: size, height: size)
                        .clipShape(.rect(topLeadingRadius: supportedTorchModes.count > 1 ? 0 : 0.5*size, bottomLeadingRadius: 0.5*size, bottomTrailingRadius: 0.5*size, topTrailingRadius: supportedTorchModes.count > 1 ? 0 : 0.5*size))
                        
                        ZStack {
                            Color.white
                            switch colorScheme {
                            case .dark: innerDark
                            default: innerLight
                            }
                        }
                        .frame(width: 0.9*size, height: 0.9*size)
                        .clipShape(.rect(topLeadingRadius: supportedTorchModes.count > 1 ? 0 : 0.45*size, bottomLeadingRadius: 0.45*size, bottomTrailingRadius: 0.45*size, topTrailingRadius: supportedTorchModes.count > 1 ? 0 : 0.45*size))
                        Image(systemName: "arrow.2.circlepath")
                            .rotationEffect(Angle(degrees: 30))
                            .offset(y: supportedTorchModes.count > 1 ? -2 : 0)
                            .foregroundStyle(colorScheme == .dark ? Color.lightWood : Color.black)
                    }
                    
                }
            }
        }
        
    }
    
    func torchImage(_ mode: AVCaptureDevice.TorchMode) -> String {
        switch mode {
        case .on: return "bolt"
        case .auto: return "bolt.badge.automatic"
        default: return "bolt.slash"
        }
    }
}

#Preview {
    FlashAndPositionButtons(supportedTorchModes: .constant([.off]), torchMode: .constant(.off)) {
        
    }
}
