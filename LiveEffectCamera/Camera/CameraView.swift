//
//  CameraView.swift
//  QuantCap
//
//  Created by Владимир Костин on 26.09.2024.
//

import AVKit
import AVFoundation
import SwiftUI

struct CameraView: View {
    
    @State var camera: CameraViewModel = .init()
	@State var location: LocationViewModel = .init()
    
    var body: some View {
        GeometryReader { geo in
			Background()
			
			if let preview = camera.preview, let latestSample = camera.latestSample {
				SampleBufferView(camera: camera, preview: preview, sampleBuffer: latestSample)
					.frame(width: geo.size.width, height: 16*geo.size.width/9)
					.position(x: geo.size.width/2, y: geo.size.width*8/9)
					.scaleEffect(x: !camera.cameraStatus.isVideoMirrored && camera.cameraStatus.position == .front ? -1 : 1)
					.statusBarHidden(true)
					.onAppear { camera.layerSize = CGSize(width: geo.size.width, height: 16*geo.size.width/9) }
			}
			
			ScrollViewReader { proxy in
			
				ScrollView(.horizontal) {
					HStack(alignment: .center, spacing: 16) {
						ForEach(camera.presets, id: \.self) { preset in
							Button(action: {
								withAnimation(.spring(duration: 0.25)) {
									camera.videoSettings.selectedPreset = preset
									proxy.scrollTo(preset, anchor: .center)
								}
							}) {
								Text(preset)
									.foregroundStyle(Color.black)
									.padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
									.background{
										Capsule()
											.foregroundStyle(camera.videoSettings.selectedPreset == preset ? Color.accentColor : Color.white)
									}
							}
							.id(preset)
						}
					}
					.padding(EdgeInsets(top: 8, leading: 32, bottom: 8, trailing: 32))
				}
				.onAppear {
					guard !camera.videoSettings.selectedPreset.isEmpty, camera.presets.contains(camera.videoSettings.selectedPreset) else { return }
					
					withAnimation(.spring(duration: 0.25)) {
						proxy.scrollTo(camera.videoSettings.selectedPreset, anchor: .center)
					}
					
				}
			}
			.position(x: geo.size.width/2, y: geo.size.height - 144)
			
#if DEBUG
			
			thermo
				.position(x: 32, y: 64)
#endif
			
			CaptureButton(isWriting: .constant(camera.duration > 0)) {
				Task {
					if camera.duration > 0 {
						await camera.stopWriting()
					} else {
						await camera.startWriting(with: location.currentLocation)
					}
				}
			}
			.position(x: geo.size.width/2, y: geo.size.height - 72)
			
        }
		.ignoresSafeArea()
		.onAppear {
			location.startLocation()
			camera.load(lut: camera.videoSettings.selectedPreset)
			Task() {
				try? await Task.sleep(for: .milliseconds(250))
				
				await camera.session.startVideoSession(with: camera.cameraStatus, frontDevice: camera.frontDevice, settings: camera.videoSettings)
				 
			}
		}
		.onDisappear {
			Task() {
				await camera.session.stopSession()
			}
			location.stopLocation()
			camera.mManager.stopAccelerometerUpdates()
			camera.cancellables.removeAll()
		}
    }
  
	var thermo: some View {
		switch camera.thermalState {
		case .nominal:
			Image(systemName: "thermometer.low")
				.scaleEffect(1.5)
				.foregroundStyle(Color.green)
		case .fair:
			Image(systemName: "thermometer.medium")
				.scaleEffect(1.5)
				.foregroundStyle(Color.yellow)
		case .serious:
			Image(systemName: "thermometer.high")
				.scaleEffect(1.5)
				.foregroundStyle(Color.orange)
		case .critical:
			Image(systemName: "thermometer.high")
				.scaleEffect(1.5)
				.foregroundStyle(Color.red)
		@unknown default:
			Image(systemName: "thermometer.low")
				.scaleEffect(1.5)
				.foregroundStyle(Color.clear)
		}
	}
	
}



#Preview {
    CameraView()
}
