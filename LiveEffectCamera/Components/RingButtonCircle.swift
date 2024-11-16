//
//  QCRingButtonCircle.swift
//  QuantCap
//
//  Created by Владимир Костин on 26.10.2024.
//

import SwiftUI

struct RingButtonCircle: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    @Binding var isWriting: Bool
    
    let size: CGFloat
    
    let innerLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let outLight: LinearGradient = .init(colors: [Color.gray, Color.gray.opacity(0.25)], startPoint: .bottomTrailing, endPoint: .topLeading)
    let innerDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    let outDark: LinearGradient = .init(colors: [Color.black.opacity(0.75), Color.black.opacity(0.5)], startPoint: .bottomTrailing, endPoint: .topLeading)
    
    var body: some View {
        ZStack() {
            ZStack {
                Color.white
                switch colorScheme {
                case .dark: outDark
                default: outLight
                }
            }
            .frame(width: isWriting ? 0.5*size : size, height: isWriting ? 0.5*size : size)
            .clipShape(.rect(cornerRadius: isWriting ? 0.0875*size : 0.5*size))
            
            ZStack {
                Color.white
                switch colorScheme {
                case .dark: innerDark
                default: innerLight
                }
            }
            .frame(width: isWriting ? 0.45*size : 0.9*size, height: isWriting ? 0.45*size : 0.9*size)
            .clipShape(.rect(cornerRadius: isWriting ? 0.0625*size : 0.45*size))
        }
    }
}

#Preview {
    RingButtonCircle(isWriting: .constant(true), size: 80)
}


