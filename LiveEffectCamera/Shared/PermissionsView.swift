//
//  PermissionsView.swift
//  QuantCap
//
//  Created by Владимир Костин on 24.09.2024.
//

import SwiftUI

struct PermissionsView: View {
    
    @Environment(MainViewModel.self) var viewModel
    @Environment(PermissionsViewModel.self) var permissions
    @Environment(LocationViewModel.self) var location
     
    var body: some View {
        ZStack(alignment: .top) {
            Background()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("\tFirst, to start creating, the QuantCap app needs to access your Camera and Camera Roll.")
                    .font(.system(size: 16, weight: .medium))
                
                Text("\tDon't worry, \(Text("we don't collect or process your private data in any way.").font(.system(size: 16, weight: .semibold)))")
                    .font(.system(size: 16, weight: .regular))
                
                if permissions.camAuthStatus != .authorized {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        
                        HStack(alignment: .center, spacing: 8) {
                            Image("Camera")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 44, height: 44)
                            Text("Provide access to the camera so that you can take amazing photos")
                                .font(.system(size: 14, weight: .regular))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Button(action: {
                            permissions.requestCameraAccess()
                        }) {
                            ZStack() {
                                Capsule()
                                    .foregroundStyle(Color.white)
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(height: 44)
                    }
                }
                
                if permissions.micAuthStatus != .authorized {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        
                        HStack(alignment: .center, spacing: 8) {
                            Image("Microphone")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 44, height: 44)
                            Text("Provide access to the microphone so that you can take amazing photos")
                                .font(.system(size: 14, weight: .regular))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Button(action: {
                            permissions.requestMicrophoneAccess()
                        }) {
                            ZStack() {
                                Capsule()
                                    .foregroundStyle(Color.white)
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(height: 44)
                    }
                }
                
                if permissions.phAuthStatus != .authorized {
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        
                        HStack(alignment: .center, spacing: 8) {
                            Image("CameraRoll")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 44, height: 36)
                            Text("Provide access to the library so that we can save your photos")
                                .font(.system(size: 14, weight: .regular))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Button(action: {
                            permissions.requestPHAccess()
                        }) {
                            ZStack() {
                                Capsule()
                                    .foregroundStyle(Color.white)
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(height: 44)
                        
                    }
                }
                
                if location.locationStatus.rawValue < 3  {
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        
                        HStack(alignment: .center, spacing: 8) {
                            Image("Location")
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 44, height: 44)
                            Text("Provide access to your location so that we can add geo tags to your photos")
                                .font(.system(size: 14, weight: .regular))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Button(action: {
                            location.requestLocation()
                        }) {
                            ZStack() {
                                Capsule()
                                    .foregroundStyle(Color.white)
                                Text("Continue")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(height: 44)
                        
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: permissions.camAuthStatus) { _, newValue in
            if newValue == .authorized && permissions.micAuthStatus == .authorized && permissions.phAuthStatus == .authorized && location.locationStatus.rawValue >= 3 {
                withAnimation(.spring(duration: 0.2)) { viewModel.appState = .camera }
            }
        }
        
        .onChange(of: permissions.micAuthStatus) { _, newValue in
            if newValue == .authorized && permissions.camAuthStatus == .authorized && permissions.phAuthStatus == .authorized && location.locationStatus.rawValue >= 3 {
                withAnimation(.spring(duration: 0.2)) { viewModel.appState = .camera }
            }
        }
        
        .onChange(of: permissions.phAuthStatus) { _, newValue in
            if permissions.camAuthStatus == .authorized && permissions.micAuthStatus == .authorized && newValue == .authorized && location.locationStatus.rawValue >= 3 {
                withAnimation(.spring(duration: 0.2)) { viewModel.appState = .camera }
            }
        }
        
        .onChange(of: location.locationStatus) { _, newValue in
           
            if permissions.camAuthStatus == .authorized && permissions.micAuthStatus == .authorized && permissions.phAuthStatus == .authorized && newValue.rawValue >= 3 {
                withAnimation(.spring(duration: 0.2)) { viewModel.appState = .camera }
            }
        }
    }
}

#Preview {
    PermissionsView()
        .environment(PermissionsViewModel(viewModel: MainViewModel()))
        .environment(LocationViewModel())
        .environment(MainViewModel())
}
