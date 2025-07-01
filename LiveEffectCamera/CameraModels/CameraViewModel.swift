//
//  CameraViewModel.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

@preconcurrency import AVFoundation
import Combine
import CoreMotion
import Observation
import Photos
import SwiftUI


@Observable @MainActor final class CameraViewModel: NSObject, @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate, @preconcurrency AVCaptureAudioDataOutputSampleBufferDelegate {
	
	var cameraStatus: SessionStatus {
		didSet {
			save(cameraStatus, to: cameraStateURL)
			Task() {
				var needWarmUp: Bool = false
				if await session.session.isRunning == false {
					needWarmUp = true
					try? await Task.sleep(for: .milliseconds(250))
				}
				
				await session.startVideoSession(with: cameraStatus, frontDevice: frontDevice, settings: videoSettings)
				load(lut: videoSettings.selectedPreset)
				
				
				if needWarmUp {
					try? await Task.sleep(for: .milliseconds(100))
					
					var vSettings = await session.videoOut.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? [:]
			
					let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoOutput.MOV")
					
					if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
					
					let assetWriter = try AVAssetWriter(url: url, fileType: AVFileType.mov)
					
					let vInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: vSettings)
					vInput.expectsMediaDataInRealTime = true
					if assetWriter.canAdd(vInput) { assetWriter.add(vInput) }
					
					let result = assetWriter.startWriting()
					
					if result {
						assetWriter.startSession(atSourceTime: .zero)
						
						vInput.markAsFinished()
						assetWriter.cancelWriting()
						
					}
				}
			}
		}
	}
	
	var videoSettings: CameraVideoSettings  {
		didSet {
			save(videoSettings, to: videoSettingsURL)
			load(lut: videoSettings.selectedPreset)
		}
	}
	
	var backDevices: [BackDeviceType] = []
	var frontDevice: AVCaptureDevice.DeviceType?
	var maxOpticalZoom: Int = 2
	var avaliableBackFrameRates: [BackDeviceType : [VideoFrameRate]] = [:]
	var avaliableFrontFrameRates: [VideoFrameRate] = []
	var duration: Double = 0
	
	var preview: DisplayLayerView?
	
	var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
	
	var latestSample: Unchecked<CMSampleBuffer>? {
		sampleBroadcaster.wrappedValue
	}
	
	@ObservationIgnored var orientation: VideoOrientation = .portrait
	@ObservationIgnored var layerSize: CGSize = .zero
	@ObservationIgnored var cancellables: Set<AnyCancellable> = []
	@ObservationIgnored var writer: VideoWriter?
	@ObservationIgnored private var textureCache: CVMetalTextureCache?
	@ObservationIgnored private var cubeBuffer: (MTLBuffer, MTLBuffer)?
	@ObservationIgnored private var lastPreviewSampleTime: Double = 0
	
	
	let session: AsyncCameraSession = .init()
	
	let mManager: CMMotionManager = .init()
	private let device: MTLDevice
	private let commandQueue: MTLCommandQueue
	private let computePipelineState: MTLComputePipelineState
	private let cameraStateURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(".cameraState.json")
	private let videoSettingsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(".videoSettings.json")
	private let toBackground = NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
	private let toForeground = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
	private let thermal = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
	private let sampleSource = AsyncSource<Unchecked<CMSampleBuffer>>()
	private let sampleBroadcaster = Broadcaster<Unchecked<CMSampleBuffer>>()
	private let neutralLutArray = [
		SIMD4<Float>(0.0, 0.0, 0.0, 1.0),
		SIMD4<Float>(1.0, 0.0, 0.0, 1.0),
		SIMD4<Float>(0.0, 1.0, 0.0, 1.0),
		SIMD4<Float>(1.0, 1.0, 0.0, 1.0),
		SIMD4<Float>(0.0, 0.0, 1.0, 1.0),
		SIMD4<Float>(1.0, 0.0, 1.0, 1.0),
		SIMD4<Float>(0.0, 1.0, 1.0, 1.0),
		SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
	]
	
	let presets: [String] = ["Ava", "Byers", "Cobi", "Django", "Faded", "Hyla", "Korben", "Lenox", "Milo", "Nah", "Neon", "Pitaya", "Reeve", "Remy", "Teigen", "Trent", "Tweed", "Undeniable", "Vireo", "WellSee", "Zed"]
	
	override init() {
		do {
			let cameraStateData = try Data(contentsOf: cameraStateURL)
			self.cameraStatus = try JSONDecoder().decode(SessionStatus.self, from: cameraStateData)
		} catch {
			self.cameraStatus = SessionStatus()
		}
		
		do {
			let settingsData = try Data(contentsOf: videoSettingsURL)
			self.videoSettings = try JSONDecoder().decode(CameraVideoSettings.self, from: settingsData)
		} catch {
			self.videoSettings = CameraVideoSettings()
		}
		
		guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Can not create MTL Device") }
		self.device = device
		
		guard let commandQueue = self.device.makeCommandQueue() else { fatalError("Can not create command queue") }
		self.commandQueue = commandQueue
		
		
		guard let library = device.makeDefaultLibrary() else { fatalError("Could not create Metal Library") }
		guard let function = library.makeFunction(name: "cameraKernel") else { fatalError("Unable to create gpu kernel") }
		do {
			self.computePipelineState = try self.device.makeComputePipelineState(function: function)
		} catch {
			fatalError("Unable to create compute pipelane state")
		}
		 
		guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.device, nil, &self.textureCache) == kCVReturnSuccess else { fatalError("Unable to allocate texture cache.") }

		 
		super.init()
		
		prepareCamera()
		setupMotionManager()
		
		self.preview = DisplayLayerView(frame: .zero)
		
		sampleBroadcaster.broadcast(stream: sampleSource.stream)

		
		toBackground
			.dropFirst()
			.sink { _ in
				Task() {
					await self.writer?.stopRecording()
				}
			}
			.store(in: &cancellables)
		
		toForeground
			.sink { _ in
				DispatchQueue.main.async { self.preview = nil }
				
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					self.preview = DisplayLayerView(frame: .zero)
				}
			}
			.store(in: &cancellables)
		thermal
			.sink { value in
				Task() { @MainActor in
					self.thermalState = ProcessInfo.processInfo.thermalState
				}
			}
			.store(in: &cancellables)
		
		Task() {
			await session.addModel(camera: self)
		}
		
	}
	
	func prepareCamera() {
		backDevices = avaliableBackDevices()
		frontDevice = avaliableFrontDevice()
		
		for backDevice in backDevices {
			
			var device: AVCaptureDevice?
			
			switch backDevice {
			case .ultraWideAngleCamera: device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
			case .wideAngleCamera, .wideAngleX2Camera: device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
			case .telephotoCamera: device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
			}
			guard let device = device else { continue }
			
			var formats = device.formats
			
			if !formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty}).isEmpty {
				formats = formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty})
			}
			
			if !formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"}).isEmpty {
				formats = formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"})
			}
			 
			let (_, bestFrameRateRange) = getVideoFormat(from: formats, for: 2160, frameRate: 120)
			
			if let frameRateRange = bestFrameRateRange {
				let maxRate = Int(1/frameRateRange.minFrameDuration.seconds)
				
				var rates: [VideoFrameRate] = []
				
				for rate in VideoFrameRate.allCases {
					if maxRate >= rate.rawValue { rates.append(rate) }
				}
				
				avaliableBackFrameRates[backDevice] = rates
			}
			
			
		}
		
		if let frontDevice = frontDevice, let device = AVCaptureDevice.default(frontDevice, for: .video, position: .front) {
			var formats = device.formats
			
			if !formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty}).isEmpty {
				formats = formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty})
			}
			
			if !formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"}).isEmpty {
				formats = formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"})
			}
			
			let (_, bestFrameRateRange) = getVideoFormat(from: formats, for: 2160, frameRate: 120)
			
			if let frameRateRange = bestFrameRateRange {
				let maxRate = Int(1/frameRateRange.minFrameDuration.seconds)
				
				var rates: [VideoFrameRate] = []
				
				for rate in VideoFrameRate.allCases {
					if maxRate >= rate.rawValue { rates.append(rate) }
				}
				
				avaliableFrontFrameRates = rates
			}
		}
		 
		if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
			let factors = device.virtualDeviceSwitchOverVideoZoomFactors
			if factors.count == 2 {
				DispatchQueue.main.async { self.maxOpticalZoom = Int(truncating: factors[1])/Int(truncating: factors[0]) }
			}
		}
	}
	
	func avaliableBackDevices() -> [BackDeviceType] {
		var result: [BackDeviceType] = []
		
		if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil { result.append(.ultraWideAngleCamera) }
		if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
			result.append(.wideAngleCamera)
			if !device.formats.filter({!$0.secondaryNativeResolutionZoomFactors.filter({$0 == 2.0}).isEmpty}).isEmpty { result.append(.wideAngleX2Camera) }
		}
		if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil { result.append(.telephotoCamera) }
	
		return result
	}
	 
	func avaliableFrontDevice() -> AVCaptureDevice.DeviceType? {
		
		let discoverSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTelephotoCamera, .builtInTripleCamera, .builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
		
		let devices = discoverSession.devices
		
		return devices.map({$0.deviceType}).last
	}
	
	func setupMotionManager() {
		
		mManager.accelerometerUpdateInterval = 0.1
		
		mManager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] (data, error) in
			
			if let data = data {
				
				let x = data.acceleration.x
				let y = data.acceleration.y
				
				let delta = abs(abs(x) - abs(y))
				
				if delta < 0.75 { return }
				 
				DispatchQueue.main.async {
					guard let self else { return }
					
					if -y > x && x > y {
						self.orientation = .portrait
					}
					else if -y < x && x > y {
						self.orientation = .landscapeLeft
					}
					else if x < y && -x < y {
						self.orientation = .portraitUpsideDown
					}
					else {
						self.orientation = .landscapeRight
					}
				}
				
				
			} else {
				print("No accelerometer data")
			}
		}
		

	}
	 
	func save<E: Encodable>(_ value: E, to url: URL) {
		Task(priority: .background) {
			do {
				let data = try JSONEncoder().encode(value)
				try data.write(to: url, options: .atomic)
			} catch {
				print(error.localizedDescription)
			}
		}
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
	
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		
		if connection == output.connection(with: .video) {
			render(sampleBuffer)
		}
		
		if connection == output.connection(with: .audio) {
			
			Task() {
				if await writer?.status == .recording {
					await writer?.avaliableNewAudio(sampleBuffer)
				}
			}
		}
		
	}
	
	func render(_ sampleBuffer: CMSampleBuffer) {
		
		guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
		
		let (inputLuminance, inputCrominance) = makeTexture(from: buffer)
		guard let inputLuminance, let inputCrominance else { return }
		
		guard let commandBuffer = commandQueue.makeCommandBuffer(), let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
		
		set(computeCommandEncoder, inputLuminance: inputLuminance, inputCrominance: inputCrominance, stamp: stamp)
		
		
		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()
		
		replaceBytes(in: buffer, from: inputLuminance, and: inputCrominance)
		 
		
		let sec = stamp.seconds
		
		if sec - lastPreviewSampleTime >= 0.02 {
			let newBuffer = makeSampleBufferByReplacingImageBuffer(of: sampleBuffer, with: buffer)
			lastPreviewSampleTime = sec
			sampleSource.continuation.yield(Unchecked(wrappedValue: newBuffer))
		}
		
		Task() {
			
			if await writer?.status == .idle {
				let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
				await writer?.startRecording(at: stamp)
			} else if await writer?.status == .recording {
				
				let writingBuffer = self.makeSampleBufferByReplacingImageBuffer(of: sampleBuffer, with: buffer)
				await writer?.avaliableNewVideo(writingBuffer)

				let duration = await writer?.duration ?? 0
				
				await MainActor.run { self.duration = duration }
				
			}
		}
	}
	
	func makeTexture(from imageBuffer: CVImageBuffer) -> (MTLTexture?, MTLTexture?) {
		
		guard let textureCache = textureCache else { return (nil, nil)}
		
		let width = CVPixelBufferGetWidth(imageBuffer)
		let height = CVPixelBufferGetHeight(imageBuffer)

		
		var luminanceCVTexture: CVMetalTexture?
		CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, .r8Unorm, width, height, 0, &luminanceCVTexture)

		var crominanceCVTexture: CVMetalTexture?
		CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, imageBuffer, nil, .rg8Unorm, width/2, height/2, 1, &crominanceCVTexture)
		
		guard let luminanceCVTexture = luminanceCVTexture, let crominanceCVTexture = crominanceCVTexture else { return (nil, nil)}
		
		return (CVMetalTextureGetTexture(luminanceCVTexture), CVMetalTextureGetTexture(crominanceCVTexture))
	}
	
	func set(_ encoder: MTLComputeCommandEncoder, inputLuminance: MTLTexture, inputCrominance: MTLTexture, stamp: CMTime) {
		encoder.setComputePipelineState(computePipelineState)
		encoder.setTexture(inputLuminance, index: 0)
		encoder.setTexture(inputCrominance, index: 1)
		
		if let cubeBuffer = cubeBuffer {
			encoder.setBuffer(cubeBuffer.0, offset: 0, index: 0)
			encoder.setBuffer(cubeBuffer.1, offset: 0, index: 1)
		} else {
			let lutSizeBuffer = device.makeBuffer(bytes: [2], length: MemoryLayout<Int>.size)
			encoder.setBuffer(lutSizeBuffer, offset: 0, index: 0)
			let lutBuffer = device.makeBuffer(bytes: neutralLutArray, length: neutralLutArray.count * MemoryLayout<SIMD4<Float>>.stride, options: [])
			encoder.setBuffer(lutBuffer, offset: 0, index: 1)
		}
		encoder.dispatchThreadgroups(inputLuminance.threadGroups(), threadsPerThreadgroup: inputLuminance.threadGroupCount())
		encoder.endEncoding()
	}
	
	func replaceBytes(in imageBuffer: CVImageBuffer, from luminanceTexture: MTLTexture, and crominanceTexture: MTLTexture) {
		
		CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
		let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
		let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1)
		
		guard let liminanceBytes = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0),
			  let chrominanceBytes = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1)
		else { return }
		
		luminanceTexture.getBytes(liminanceBytes, bytesPerRow: lumaBytesPerRow, from: MTLRegionMake2D(0, 0, luminanceTexture.width, luminanceTexture.height), mipmapLevel: 0)
		crominanceTexture.getBytes(chrominanceBytes, bytesPerRow: chromaBytesPerRow, from: MTLRegionMake2D(0, 0, crominanceTexture.width, crominanceTexture.height), mipmapLevel: 0)
		
		CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
	}
	
	func makeSampleBufferByReplacingImageBuffer(of sampleBuffer: CMSampleBuffer, with imageBuffer: CVPixelBuffer) -> CMSampleBuffer {
		
		var timingInfo = CMSampleTimingInfo()
		guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == 0 else { return sampleBuffer }
		
		var outputSampleBuffer: CMSampleBuffer?
		var newFormatDescription: CMFormatDescription?
		CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: imageBuffer, formatDescriptionOut: &newFormatDescription)
		guard let formatDescription = newFormatDescription else { return sampleBuffer }
		
		CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &outputSampleBuffer)
		
		return outputSampleBuffer ?? sampleBuffer
	}
	
	func load(lut: String) {
		
		guard let url = Bundle.main.url(forResource: lut, withExtension: "data"),
			  let data = try? Data(contentsOf: url)
		else {
			self.cubeBuffer = nil
			return
		}
		
		guard data.count % 4 == 0, !data.isEmpty
		else {
			self.cubeBuffer = nil
			return
		}
		
		let size = Int(cbrtf(Float(data.count/16)))
		let sizeBuffer = self.device.makeBuffer(bytes: [size], length: MemoryLayout<Int>.size)!
		
		var bytes = [UInt8]()
		bytes.append(contentsOf: data)
		
		let buffer = self.device.makeBuffer(bytes: bytes, length: data.count/4 * MemoryLayout<Float>.stride, options: [])!
		
		self.cubeBuffer = (sizeBuffer, buffer)

	}
	
	func startWriting(with location: CLLocation?) async {
		 
		guard let activeDevice = await session.activeDevice else { return }
		let videoOut = await session.videoOut
		let audioOut = await session.audioOut
		let frameRate = Int(1/activeDevice.activeVideoMinFrameDuration.seconds)

		let writer = VideoWriter(frameRate: frameRate, videoOut: videoOut, audioOut: audioOut, quality: videoSettings.videoQuality, orientation: orientation, location: location)

		await MainActor.run {
			self.writer = writer
		}
	}
	
	func stopWriting() async {

		guard let writer = writer else { return }

		let url = await writer.stopRecording()

		guard let url = url else { return }
		
		do {
			try await PHPhotoLibrary.shared().performChanges {
				let request = PHAssetCreationRequest.forAsset()
				request.addResource(with: .video, fileURL: url, options: nil)
			}
		} catch {
			print("Error saving video: \(error.localizedDescription)")
		}
		

		await MainActor.run {
			self.writer = nil
			self.duration = 0
		}
		 
	}
	
}

