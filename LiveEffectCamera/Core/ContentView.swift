//
//  ContentView.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import SwiftUI

struct ContentView: View {
     
    @Environment(LECViewModel.self) var model
    
    var body: some View {
        ZStack() {
            Background()
                .ignoresSafeArea()
            switch model.appState {
            case .start: ProgressView()
            case .permissions: PermissionsView()
            case .camera: CameraView()
            }
        }
    }
    
    
}

#Preview {
    ContentView()
        .environment(LECViewModel())
}
