//
//  CaptureButton.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//


import SwiftUI


struct CaptureButton: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isWriting: Bool
    
    let action: () -> Void
    
    let innerLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let innerDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let outLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .bottomTrailing, endPoint: .topLeading)
    let outDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.gray.opacity(0.5)], startPoint: .bottomTrailing, endPoint: .topLeading)
    
    var body: some View {
        
        Button(action: {
            action()
        }) {
            ZStack {
                RingButtonCircle(isWriting: $isWriting, size: 80)
                
                Circle()
                    .strokeBorder(Color.lightWood, lineWidth: 0.67, antialiased: true)
                    .frame(width: 88, height: 88)
                
            }
        }
		.buttonStyle(.plain)
    }
}
