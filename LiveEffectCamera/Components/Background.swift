//
//  QCBackground.swift
//  QuantCap
//
//  Created by Владимир Костин on 25.09.2024.
//

import SwiftUI

struct Background: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        switch colorScheme {
        case .light:
            LinearGradient(colors: [Color.lightGreen, Color.midGreen], startPoint: .leading, endPoint: .trailing)
        default:
            LinearGradient(colors: [Color.midGreen, Color.deepGreen], startPoint: .leading, endPoint: .trailing)
        }
    }
}

#Preview {
    Background()
}
