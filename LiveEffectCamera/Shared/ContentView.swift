//
//  ContentView.swift
//  QuantCap
//
//  Created by Владимир Костин on 24.09.2024.
//

import SwiftUI

struct ContentView: View {
     
    @Environment(MainViewModel.self) var model
    
    var body: some View {
        ZStack() {
            Background()
                .ignoresSafeArea()
            switch model.appState {
            case .start: EmptyView()
            case .permissions: PermissionsView()
            case .camera: CameraView()
            }
        }
    }
    
    
}

#Preview {
    ContentView()
        .environment(MainViewModel())
}
