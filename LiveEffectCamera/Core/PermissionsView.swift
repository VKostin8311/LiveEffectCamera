//
//  PermissionsView.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import SwiftUI

struct PermissionsView: View {
    
    @Environment(LECViewModel.self) var viewModel
    @Environment(PermissionsViewModel.self) var permissions
    @Environment(LocationViewModel.self) var location
     
    var body: some View {
        ZStack(alignment: .top) {
            Background()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text("\tFirst, to start creating, the Live Effect Camera app needs to access your Hardware and Camera Roll.")
                    .font(.system(size: 16, weight: .medium))
                
                Text("\tDon't worry, \(Text("we don't collect or process your private data in any way.").font(.system(size: 16, weight: .semibold)))")
                    .font(.system(size: 16, weight: .regular))
                
                if permissions.camAuthStatus != .authorized {
                    
					PermissionRow(imageName: "Camera", message: "Provide access to the camera so that you can take amazing videos") {
						permissions.requestCameraAccess()
					}
				
                }
                
                if permissions.micAuthStatus != .authorized {
                    
					PermissionRow(imageName: "Microphone", message: "Provide access to the microphone so that you can record beautiful videos with sound") {
						permissions.requestMicrophoneAccess()
					}
					
                }
                
                if permissions.phAuthStatus != .authorized {
                    
					PermissionRow(imageName: "CameraRoll", message: "Provide access to the library so that we can save your movies") {
						permissions.requestPHAccess()
					}

                }
                
                if location.locationStatus.rawValue < 3  {
                    
					PermissionRow(imageName: "Location", message: "Provide access to your location so that we can add geo tags to your videos") {
						location.requestLocation()
					}
                    
                }
            }
            .padding(20)
        }
        .onChange(of: permissions.camAuthStatus) { _, _ in
			checkStatus()
        }
        
        .onChange(of: permissions.micAuthStatus) { _, _ in
			checkStatus()
        }
        
        .onChange(of: permissions.phAuthStatus) { _, _ in
			checkStatus()
        }
        
        .onChange(of: location.locationStatus) { _, _ in
			checkStatus()
        }
    }
	
	struct PermissionRow: View {
		let imageName: String
		let message: String
		let action: () -> Void
		
		var body: some View {
			VStack(alignment: .leading, spacing: 12) {
				Divider()
				
				HStack(alignment: .center, spacing: 8) {
					Image(imageName)
						.resizable()
						.renderingMode(.template)
						.frame(width: 40, height: 40)
					Text(message)
						.font(.system(size: 14, weight: .regular))
						.fixedSize(horizontal: false, vertical: true)
				}
				
				Button(action: {
					action()
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
	
	
	func checkStatus() {
		if permissions.camAuthStatus == .authorized && permissions.micAuthStatus == .authorized && permissions.phAuthStatus == .authorized && location.locationStatus.rawValue >= 3 {
			withAnimation(.spring(duration: 0.2)) { viewModel.appState = .camera }
		}
	}
	
	
}

#Preview {
    PermissionsView()
        .environment(PermissionsViewModel(viewModel: LECViewModel()))
        .environment(LocationViewModel())
        .environment(LECViewModel())
}
