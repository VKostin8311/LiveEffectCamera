//
//  QCRingActiveButtonCircle.swift
//  QuantCap
//
//  Created by Владимир Костин on 26.10.2024.
//

import SwiftUI

struct RingActiveButtonCircle: View {
   
    let size: CGFloat
    
    let inner: LinearGradient = .init(colors: [Color.accent, Color.lightWood], startPoint: .topLeading, endPoint: .bottomTrailing)
    let out: LinearGradient = .init(colors: [Color.accent, Color.lightWood], startPoint: .bottomTrailing, endPoint: .topLeading)
    
    var body: some View {
        ZStack() {
            ZStack() {
                out
            }
                .frame(width: size, height: size)
                .clipShape(Circle())
            ZStack() {
                inner
            }
                .frame(width: 0.9*size, height: 0.9*size)
                .clipShape(Circle())
        }
    }
}

#Preview {
    RingActiveButtonCircle(size: 80)
}
