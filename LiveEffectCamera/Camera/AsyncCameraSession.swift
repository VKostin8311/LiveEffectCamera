//
//  AsyncCameraSession.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

@preconcurrency import AVFoundation

actor AsyncCameraSession: NSObject {
	 
	let session: AVCaptureSession = .init()
	let videoOut: AVCaptureVideoDataOutput = .init()
	let audioOut: AVCaptureAudioDataOutput = .init()
	
	private let outputQueue = DispatchQueue(label: "Output Queue")
	
	var activeDevice: AVCaptureDevice?
	var cameraStatus: SessionStatus = .init()
	var camera: CameraViewModel?
	 
	private var keyValueObservations = [NSKeyValueObservation]()
	
	let beginCapture: SystemSoundID = 1117
	let endCapture: SystemSoundID = 1118
	let sessionQueue = DispatchQueue(label: "session", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit)
	
	
	override init() {
		
		super.init()
		
	}
	
	func stopSession() {
		
		if let activeDevice = activeDevice, session.isRunning {
			
			do {
				try activeDevice.lockForConfiguration()
				
				if activeDevice.isExposurePointOfInterestSupported {
					activeDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
					activeDevice.setExposureTargetBias(0) { _ in }
				}
				
				if activeDevice.isExposureModeSupported(.continuousAutoExposure) { activeDevice.exposureMode = .continuousAutoExposure }
				
				
				if activeDevice.isFocusPointOfInterestSupported { activeDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
				if activeDevice.isFocusModeSupported(.continuousAutoFocus) { activeDevice.focusMode = .continuousAutoFocus }
				
				activeDevice.unlockForConfiguration()
				
			} catch {
				print(error.localizedDescription)
			}
			 
			session.stopRunning()
			
		}
	   
		session.inputs.forEach{session.removeInput($0)}
		session.outputs.forEach{session.removeOutput($0)}

	}
	
	func startVideoSession(with status: SessionStatus, frontDevice: AVCaptureDevice.DeviceType?, settings: CameraVideoSettings) {

		do {
			stopSession()
			
			session.beginConfiguration()
			session.sessionPreset = .inputPriority
			
			switch status.position {
			case .front:
				guard let front = frontDevice, let device = AVCaptureDevice.default(front, for: .video, position: .front) else { return }
				activeDevice = device
			case .back:
				switch status.backDevice {
				case .ultraWideAngleCamera:
					guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) else { return }
					activeDevice = device
				case .wideAngleCamera, .wideAngleX2Camera:
					guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
					activeDevice = device
				case .telephotoCamera:
					guard let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) else { return }
					activeDevice = device
				}
			}
			
			guard let activeDevice = activeDevice else { return }
			
			var formats = activeDevice.formats
			
			if !formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty}).isEmpty {
				formats = formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty})
			}
			
			if !formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"}).isEmpty {
				formats = formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"})
			}
			
			
			let (bestFormat, bestFrameRateRange) = getVideoFormat(from: formats, for: status.videoResolution.rawValue, frameRate: status.frameRate.rawValue)
			
			if let bestFormat = bestFormat {
				try activeDevice.lockForConfiguration()
				activeDevice.activeFormat = bestFormat
				activeDevice.unlockForConfiguration()
			}
			
			let vInput = try AVCaptureDeviceInput(device: activeDevice)
			if session.canAddInput(vInput) { session.addInput(vInput) }
			
			videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]

			if let camera = camera {
				videoOut.setSampleBufferDelegate(camera, queue: outputQueue)
			}
			
			if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
			
			if let connection = videoOut.connection(with: .video) {
				connection.videoRotationAngle = 90
				connection.isVideoMirrored = status.position == .front ? status.isVideoMirrored : false
				connection.preferredVideoStabilizationMode = .standard
			}
			
			if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
				let aDevice = AVCaptureDevice.default(for: .audio)!
				let aInput = try AVCaptureDeviceInput(device: aDevice)
				if session.canAddInput(aInput) { session.addInput(aInput) }
				
				if let camera = camera {
					audioOut.setSampleBufferDelegate(camera, queue: outputQueue)
				}
				
				if session.canAddOutput(audioOut) { session.addOutput(audioOut) }
			}
			
			self.session.commitConfiguration()
			self.session.startRunning()
			
			guard self.session.isRunning else { return }
			
			try activeDevice.lockForConfiguration()
			
			if let frameRateRange = bestFrameRateRange {
				
				let maxFrameRate = Int32(1/frameRateRange.minFrameDuration.seconds)
				let rate = min(maxFrameRate, Int32(status.frameRate.rawValue))
				
				activeDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: rate)
				activeDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: rate)
				
			}
			
			if status.position == .back && status.backDevice == .wideAngleX2Camera {
				activeDevice.videoZoomFactor = 2.0
			} else {
				activeDevice.videoZoomFactor = 1.0
			}
			
			activeDevice.unlockForConfiguration()
			
			cameraStatus = status
			
		} catch {
			print(error.localizedDescription)
		}

	}
	
	func apply(status: SessionStatus) {
		cameraStatus = status
	}
	
	func addModel(camera: CameraViewModel) {
		self.camera = camera
	}
	
	func getVideoFormat(from formats: [AVCaptureDevice.Format], for resolution: Int, frameRate: Int) -> (AVCaptureDevice.Format?, AVFrameRateRange?){
		
		var result: (AVCaptureDevice.Format?, AVFrameRateRange?) = (nil, nil)
		
		for format in formats {
			
			let height = format.formatDescription.dimensions.height
			let width = format.formatDescription.dimensions.width
			
			var needWidth: Int32 = 1280
			
			if resolution == 1080 { needWidth = 1920 }
			else if resolution == 2160 { needWidth = 3840 }
			
			for range in format.videoSupportedFrameRateRanges {
				if height == resolution && width == needWidth {
					if range.maxFrameRate >= Float64(frameRate) { return (format, range) }
					else { result = (format, range) }
				}
			}
		}
		
		return result
	}
	
	
	 
}
