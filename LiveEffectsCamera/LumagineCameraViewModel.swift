//
//  LumagineCameraViewModel.swift
//  Lumagine
//
//  Created by Владимир Костин on 20.11.2023.
//

import AVFoundation
import Combine
import CoreMotion
import MetalKit
import Photos
import SwiftUI
import VideoToolbox

class LumagineCameraViewModel: NSObject, ObservableObject {
    
    @Published var isCapturing: Bool = false
    
    @Published var cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    
    @Published var position: AVCaptureDevice.Position = .back
    @Published var backDevices: [AVCaptureDevice.DeviceType] = []
    @Published var avaliable2xWideAngleCamera = false
    @Published var wideAngle2xMode = false
    
    @Published var backDevice: AVCaptureDevice.DeviceType?
    @Published var frontDevice: AVCaptureDevice.DeviceType?
    
    @Published var photoOut = AVCapturePhotoOutput()
    @Published var videoOut = AVCaptureVideoDataOutput()
    @Published var audioOut = AVCaptureAudioDataOutput()
    
    
    @Published var captureMode: CaptureMode?
    @Published var rotation: Rotation = .portrait
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var torchMode: AVCaptureDevice.TorchMode = .off
    @Published var supportedFlashModes: [AVCaptureDevice.FlashMode] = []
    @Published var supportedTorchModes: [AVCaptureDevice.TorchMode] = []
    
    @Published var lut: String = "None"
    @Published var intensity: Float = 100
    @Published var duration: Int = 0
    
     
    let sessionQueue = DispatchQueue(label: "session", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit)
    let videoQueue = DispatchQueue(label: "video", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    let session = AVCaptureSession()
    let mManager = CMMotionManager()
    let mtkView: MTKView
    let mtlDevice: MTLDevice
    
    private var textureCache: CVMetalTextureCache?
    let commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState
    
    var cancellable: Set<AnyCancellable> = []
    var vDevice = AVCaptureDevice.default(for: .video)!
    
    private var sampleBuffer: CMSampleBuffer?
    private var assetWriter: AVAssetWriter?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var vInput: AVAssetWriterInput?
    private var aInput: AVAssetWriterInput?
    private var sessionAtSourceTime: CMTime?
    
    private var cubeBuffer: (MTLBuffer, MTLBuffer)?
    
    private let neutralLutArray = [SIMD4<Float>(0.0, 0.0, 0.0, 1.0), SIMD4<Float>(1.0, 0.0, 0.0, 1.0), SIMD4<Float>(0.0, 1.0, 0.0, 1.0), SIMD4<Float>(1.0, 1.0, 0.0, 1.0), SIMD4<Float>(0.0, 0.0, 1.0, 1.0), SIMD4<Float>(1.0, 0.0, 1.0, 1.0), SIMD4<Float>(0.0, 1.0, 1.0, 1.0), SIMD4<Float>(1.0, 1.0, 1.0, 1.0)]
    
    override init() {
        
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else { fatalError("Can not create MTL Device") }
        self.mtlDevice = mtlDevice
        self.mtkView = MTKView(frame: .zero, device: self.mtlDevice)
        
        if let layer = self.mtkView.layer as? CAMetalLayer {
            //layer.wantsExtendedDynamicRangeContent = true
            //layer.pixelFormat = .rgba16Float
            let name = CGColorSpace.extendedDisplayP3
            layer.colorspace = CGColorSpace(name: name)
        }
        
        guard let commandQueue = self.mtlDevice.makeCommandQueue() else { fatalError("Can not create command queue") }
        self.commandQueue = commandQueue
        
        guard let library = mtlDevice.makeDefaultLibrary() else { fatalError("Could not create Metal Library") }
        guard let function = library.makeFunction(name: "cameraKernel") else { fatalError("Unable to create gpu kernel") }
        do {
            self.computePipelineState = try self.mtlDevice.makeComputePipelineState(function: function)
        } catch {
            fatalError("Unable to create compute pipelane state")
        }
         
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, self.mtlDevice, nil, &self.textureCache) == kCVReturnSuccess else { fatalError("Unable to allocate texture cache.") }
        
        super.init()
        
        mtkView.delegate = self
        
        setupMotionManager()
        
        $cameraAuthStatus
            .sink { value in
                switch value {
                case .authorized:
                    self.backDevices = self.getAvaliableBackDevices()
                    self.frontDevice = self.getAvaliableFrontDevice()
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { result in
                        DispatchQueue.main.async { self.cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                default:
                    guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
                    if UIApplication.shared.canOpenURL(settings) {
                        UIApplication.shared.open(settings, options: [:]) { value in
                            DispatchQueue.main.async { self.cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video) }
                        }
                    }
                }
            }
            .store(in: &cancellable)
        $micAuthStatus
            .debounce(for: 1, scheduler: RunLoop.main)
            .sink { value in
                switch value {
                case .authorized: break
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .audio) { result in
                        DispatchQueue.main.async { self.micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                default:
                    guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
                    if UIApplication.shared.canOpenURL(settings) {
                        UIApplication.shared.open(settings, options: [:]) { value in
                            DispatchQueue.main.async { self.micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio) }
                        }
                    }
                }
            }
            .store(in: &cancellable)
        $backDevices
            .sink { value in
                if value.isEmpty { return }
                self.backDevice = self.setDefaultDevice()
            }
            .store(in: &cancellable)
        $backDevice
            .sink { value in
                guard let value = value else { return }
                guard let captureMode = self.captureMode else { return }
                switch captureMode {
                case .photo: self.startPhotoSession(with: value, in: self.position)
                case .video: self.startVideoSession(with: value, in: self.position)
                }
            }
            .store(in: &cancellable)
        $position
            .dropFirst()
            .sink { value in
                var device: AVCaptureDevice.DeviceType?
                
                switch value {
                case .back: device = self.backDevice
                case .front: device = self.frontDevice
                default: return
                }
                
                guard let device = device else { return }
                guard let captureMode = self.captureMode else { return }
                
                switch captureMode {
                case .photo: self.startPhotoSession(with: device, in: value)
                case .video: self.startVideoSession(with: device, in: value)
                }
            }
            .store(in: &cancellable)
        $captureMode
            .dropFirst()
            .sink { value in
                
                if value == .photo {
                    DispatchQueue.main.async { self.position = .back }
                    return
                }
                var device: AVCaptureDevice.DeviceType?
                
                switch self.position {
                case .back: device = self.backDevice
                case .front: device = self.frontDevice
                default: return
                }
        
                guard let device = device, let value = value else { return }
                switch value {
                case .photo: self.startPhotoSession(with: device, in: self.position)
                case .video: self.startVideoSession(with: device, in: self.position)
                }
            }
            .store(in: &cancellable)
        $lut
            .dropFirst()
            .sink { value in
                DispatchQueue.global(qos: .userInteractive).async {
                    guard let data = self.loadLUT(value) else {
                        DispatchQueue.main.async { self.cubeBuffer = nil }
                        return
                    }
                    let size = Int(cbrtf(Float(data.count)))
                    let sizeBuffer = self.mtlDevice.makeBuffer(bytes: [size], length: MemoryLayout<Int>.size)!
                    let buffer = self.mtlDevice.makeBuffer(bytes: data, length: data.count * MemoryLayout<SIMD4<Float>>.stride, options: [])!
                    
                    DispatchQueue.main.async { self.cubeBuffer = (sizeBuffer, buffer) }
                }
                
            
            }
            .store(in: &cancellable)
    }
    
    func setupMotionManager() {
        
        mManager.accelerometerUpdateInterval = 0.25
        mManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
            if error != nil { print(error as Any) }
            
            if let data = data {
                
                let x = data.acceleration.x
                let y = data.acceleration.y
                
                let delta = abs(abs(x) - abs(y))
                
                if delta < 0.5 { return }
                
                if -y > x && x > y {
                    self.rotation = .portrait
                    //withAnimation { self.rotateImage = 0 }
                }
                else if -y < x && x > y {
                    self.rotation = .landscapeLeft
//                    withAnimation {
//                        if self.rotateImage == 180 { self.rotateImage = 270 }
//                        else { self.rotateImage = -90 }
//                    }
                }
                else if x < y && -x < y {
                    self.rotation = .upsideDown
                    //withAnimation { self.rotateImage = 180 }
                }
                else {
                    self.rotation = .landscapeRight
                    //withAnimation { self.rotateImage = 90 }
                }
            
                
            } else {
                print("Нет данных акселерометра")
            }
        }
    }
    
    func getAvaliableBackDevices() -> [AVCaptureDevice.DeviceType] {
        
        var devices: [AVCaptureDevice.DeviceType] = []
        
        if let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) { devices.append(device.deviceType) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) { devices.append(device.deviceType) }
        if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) { devices.append(device.deviceType) }

        return devices
    }
    
    func getAvaliableFrontDevice() -> AVCaptureDevice.DeviceType? {
        
        let discoverSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTelephotoCamera, .builtInTripleCamera, .builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
        
        let devices = discoverSession.devices
        
        for device in devices {
            print("DEVICE: \(device.deviceType)")
        }
        
        return devices.last?.deviceType
    }
    
    func setDefaultDevice() -> AVCaptureDevice.DeviceType? {
        
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
            return .builtInWideAngleCamera
        }
        if AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil {
            return .builtInUltraWideCamera
        }
        if AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) != nil {
            return .builtInTelephotoCamera
        }
        
        return nil
    }
    
    func startVideoSession(with device: AVCaptureDevice.DeviceType, in position: AVCaptureDevice.Position) {
        
        sessionQueue.async {
            
            do {
                self.stopSession()
                
                self.session.beginConfiguration()
                self.session.sessionPreset = .inputPriority
                
                self.vDevice = AVCaptureDevice.default(device, for: .video, position: position)!
                
                var formats = self.vDevice.formats.filter({$0.isVideoHDRSupported == true})//.filter({!$0.supportedColorSpaces.filter({$0 == .HLG_BT2020}).isEmpty})
                
                if !formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"}).isEmpty {
                    formats = formats.filter({$0.formatDescription.mediaSubType.description == "'420v'"})
                }
                
                let (bestFormat, bestFrameRateRange) = self.getVideoFormat(from: formats, for: 2160, frameRate: 60)
                
                if let bestFormat = bestFormat, let bestFrameRateRange = bestFrameRateRange {
                    
                    print("BEST FORMAT: \(bestFormat.formatDescription)")
                    
                    let minDuration = bestFrameRateRange.minFrameDuration
                    let maxDuration = bestFrameRateRange.maxFrameDuration
                    
                    try self.vDevice.lockForConfiguration()
                    self.vDevice.activeFormat = bestFormat
                    self.vDevice.activeVideoMinFrameDuration = minDuration
                    self.vDevice.activeVideoMaxFrameDuration = maxDuration
                    self.vDevice.automaticallyAdjustsVideoHDREnabled = true
                    if self.vDevice.isFocusModeSupported(.continuousAutoFocus) { self.vDevice.focusMode = .continuousAutoFocus }
                    if self.vDevice.isExposureModeSupported(.continuousAutoExposure) { self.vDevice.exposureMode = .continuousAutoExposure }
                    self.vDevice.unlockForConfiguration()
                }
                
                let vInput = try AVCaptureDeviceInput(device: self.vDevice)
                if self.session.canAddInput(vInput) { self.session.addInput(vInput) }
                
                let settings: [String : Any] = [
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value:  kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                ]
                
                self.videoOut.videoSettings = settings
                self.videoOut.alwaysDiscardsLateVideoFrames = false
                
                
                self.videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(self.videoOut) {
                    self.session.addOutput(self.videoOut)
                }
                
                self.videoOut.connection(with: .video)?.videoRotationAngle = self.rotation.rawValue
                
                if self.videoOut.connection(with: .video)?.isVideoStabilizationSupported == true {
                    self.videoOut.connection(with: .video)?.preferredVideoStabilizationMode = .standard
                }
                
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                    let aDevice = AVCaptureDevice.default(for: .audio)!
                    let aInput = try AVCaptureDeviceInput(device: aDevice)
                    if self.session.canAddInput(aInput) { self.session.addInput(aInput) }
                    
                    self.audioOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                    if self.session.canAddOutput(self.audioOut) { self.session.addOutput(self.audioOut) }
                }
                
                self.session.commitConfiguration()
                
                self.session.startRunning()
                
                if self.session.isRunning { print("Session is running") }

            } catch {
                print(error)
            }
            
        }
    }
    
    func startPhotoSession(with device: AVCaptureDevice.DeviceType, in position: AVCaptureDevice.Position) {
        
        sessionQueue.async {
            
            do {
                self.stopSession()
                
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
            
                self.vDevice = AVCaptureDevice.default(device, for: .video, position: position)!
                
                if let format = self.vDevice.formats.filter({$0.isHighestPhotoQualitySupported}).first {
                    try self.vDevice.lockForConfiguration()
                    self.vDevice.activeFormat = format
                    self.vDevice.unlockForConfiguration()
                }
                
                let vInput = try AVCaptureDeviceInput(device: self.vDevice)
                if self.session.canAddInput(vInput) { self.session.addInput(vInput) }

                if self.session.canAddOutput(self.photoOut) {
                    self.session.addOutput(self.photoOut)
                    if let dimension = self.vDevice.activeFormat.supportedMaxPhotoDimensions.sorted(by: {$0.width*$0.height > $1.width*$1.height}).first {
                        self.photoOut.maxPhotoDimensions = dimension
                    }
                    self.photoOut.maxPhotoQualityPrioritization = .quality
                }
                
                if self.session.canAddOutput(self.videoOut) {
        
                    self.session.addOutput(self.videoOut)
                    self.videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                    
                    self.videoOut.alwaysDiscardsLateVideoFrames = true
                    let videoConnection = self.videoOut.connection(with: .video)
                    videoConnection?.videoRotationAngle = 90
                    self.videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                    
                }
                
                if self.videoOut.connection(with: .video)?.isVideoStabilizationSupported == true {
                    self.videoOut.connection(with: .video)?.preferredVideoStabilizationMode = .auto
                }
                
                self.session.commitConfiguration()
                self.session.startRunning()
                
                if self.session.isRunning { print("Session is running") }
                
                
            } catch {
                print(error)
            }
            
        }
    }
     
    func stopSession() {
        if self.session.isRunning {
            
            if self.assetWriter?.status == .writing { self.stopWriting() }
            
            self.session.stopRunning()
        }
        
        self.session.inputs.forEach{self.session.removeInput($0)}
        self.session.outputs.forEach{self.session.removeOutput($0)}
    
    }
    
    func getVideoFormat(from formats: [AVCaptureDevice.Format], for resolution: Int, frameRate: Int) -> (AVCaptureDevice.Format?, AVFrameRateRange?){
        
        for format in formats {
            
            let height = format.formatDescription.dimensions.height
            let width = format.formatDescription.dimensions.width
            
            var needWidth: Int32 = 1280
            
            if resolution == 1080 { needWidth = 1920 }
            else if resolution == 2160 { needWidth = 3840 }
            
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= Float64(frameRate) && height == resolution && width == needWidth {
                    return (format, range)
                }
            }
        }
        
        return (nil, nil)
    }
    
    func setupWriter(for range: VideoDynamicRange, with format: VideoFormat) {
        
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(UUID().uuidString).\(format == .mp4 ? "MP4" : "MOV")")
        
        guard let aSettings = self.audioOut.recommendedAudioSettingsForAssetWriter(writingTo: format == .mp4 ? .mp4 : .mov) else { return }
        guard var vSettings = self.videoOut.recommendedVideoSettingsForAssetWriter(writingTo: format == .mp4 ? .mp4 : .mov) else { return }
        
        guard let width = self.videoOut.videoSettings["Width"] as? Int else { return }
        guard let height = self.videoOut.videoSettings["Height"] as? Int else { return }
        
        var compressionSettings: [String: Any] = vSettings["AVVideoCompressionPropertiesKey"] as! [String: Any]
        
        switch format {
        case .mp4:
            compressionSettings["AverageBitRate"] = Int(0.15/self.vDevice.activeVideoMinFrameDuration.seconds)*width*height
        case .hevc:
            compressionSettings["AverageBitRate"] = Int(0.125/self.vDevice.activeVideoMinFrameDuration.seconds)*width*height
            switch range {
            case .sdr:
                compressionSettings["ProfileLevel"] = kVTProfileLevel_HEVC_Main_AutoLevel
                vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                                      AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                                           AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
            case .hdr10:
                compressionSettings["ProfileLevel"] = kVTProfileLevel_HEVC_Main10_AutoLevel
                vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                                                      AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                                                           AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
            case .dolbyVision:
                compressionSettings["ProfileLevel"] = kVTProfileLevel_HEVC_Main10_AutoLevel
                vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                                                      AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                                                           AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
            }
        }
        
        vSettings["AVVideoCompressionPropertiesKey"] = compressionSettings
     
        do {
            
            self.assetWriter = try AVAssetWriter(url: url, fileType: format == .mp4 ?  AVFileType.mp4 : AVFileType.mov)
            assetWriter?.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, preferredTimescale: 1000)
            //Add video input
            self.vInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: vSettings)
            self.vInput?.expectsMediaDataInRealTime = true
            
            switch self.rotation {
            case .upsideDown: vInput?.transform = CGAffineTransform(rotationAngle: .pi)
            case .landscapeRight: vInput?.transform = CGAffineTransform(rotationAngle: .pi*3/2)
            case .landscapeLeft: vInput?.transform = CGAffineTransform(rotationAngle: .pi/2)
            default: vInput?.transform = CGAffineTransform(rotationAngle: 0)
            }
            
            guard vInput != nil else { return }
            
            let sourcePixelBufferAttributes:[String:AnyObject] = [kCVPixelBufferPixelFormatTypeKey as String:NSNumber(value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
                                                                            kCVPixelBufferWidthKey as String:NSNumber(value: width),
                                                                            kCVPixelBufferHeightKey as String:NSNumber(value: height)]
            
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vInput!, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
            if self.assetWriter?.canAdd(vInput!) == true { assetWriter?.add(vInput!) }
            
            //Add audio input
            self.aInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: aSettings)
            self.aInput?.expectsMediaDataInRealTime = true
            
            guard aInput != nil else { return }
            if self.assetWriter?.canAdd(aInput!) == true { assetWriter?.add(aInput!) }
            
            self.assetWriter?.startWriting()
            
        }
        catch let error {
            debugPrint(error.localizedDescription)
        }
    }
    
    func canWrite() -> Bool {
        return isCapturing && assetWriter != nil && assetWriter?.status == .writing
    }
    
    func startWriting() {
        sessionQueue.async {
            self.setupWriter(for: .sdr, with: .hevc)
            guard !self.isCapturing else { return }
            
            DispatchQueue.main.async {
                withAnimation(.spring(duration: 0.25)) { self.isCapturing = true }
            }
            
            self.sessionAtSourceTime = nil
        }
    }
    
    func stopWriting() {
        guard isCapturing else { return }
        withAnimation(.spring(duration: 0.25)) { isCapturing = false }
        self.vInput?.markAsFinished()
        self.aInput?.markAsFinished()
        
        Task {
            await self.assetWriter?.finishWriting()
            
            self.sessionAtSourceTime = nil
            guard let url = self.assetWriter?.outputURL else { return }
            
            print(url.absoluteString)
            
            self.assetWriter = nil
            self.vInput = nil
            self.aInput = nil
            
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: url, options: nil)
                        
                    }, completionHandler: { _, error in
                        if let error = error {
                            print("💥Error occurred while saving asset to photo library: \(error)")
                        } else {
                            print("🔥 SUCCESS")
                        }
                    })
                }
                
            }
        }
    }
    
    func generateNeutralLUT(_ size: Int) -> [SIMD4<Float>]{
        
        let date = Date()
        var result: [SIMD4<Float>] = []
    
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let vector = SIMD4(x: Float(red) / Float(size-1), y: Float(green) / Float(size-1), z: Float(blue) / Float(size-1), w: 1.0)
                    result.append(vector)
                }
            }
        }
        
        print("Genetare duration: \(Date().timeIntervalSince(date))")
        return result
    }
    
    func loadLUT(_ name: String) -> [SIMD4<Float>]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "data") else { return nil }
        
        do {
            
            var data = try Data(contentsOf: url)
            var result: [SIMD4<Float>] = []
            while !data.isEmpty {
                let r = Data([data.removeFirst(), data.removeFirst(), data.removeFirst(), data.removeFirst()])
                let g = Data([data.removeFirst(), data.removeFirst(), data.removeFirst(), data.removeFirst()])
                let b = Data([data.removeFirst(), data.removeFirst(), data.removeFirst(), data.removeFirst()])
                let a = Data([data.removeFirst(), data.removeFirst(), data.removeFirst(), data.removeFirst()])
                
                let matrix = SIMD4(x: r.float, y: g.float, z: b.float, w: a.float)
                result.append(matrix)
            }
            
            return result
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
    
    enum Rotation: CGFloat {
        case portrait = 90
        case landscapeLeft = 0
        case landscapeRight = 180
        case upsideDown = 270
    }
    
    enum VideoDynamicRange: String {
        case sdr = "SDR"
        case hdr10 = "HDR10"
        case dolbyVision = "Dolby Vision"
    }
    
    enum VideoFormat: String {
        case mp4 = "MP4"
        case hevc = "HEVC"
    }
    
    
}

extension LumagineCameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
       
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    
        if connection == videoOut.connection(with: .video) {
            self.sampleBuffer = sampleBuffer
            self.mtkView.draw()
        }
        
        guard canWrite() else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if let sourceTime = sessionAtSourceTime {
            DispatchQueue.main.async {
                let duration = Int(timestamp.seconds - sourceTime.seconds)
                if self.duration < duration { self.duration = duration }
            }
        } else {
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionAtSourceTime = timestamp
        }
        
        if connection == audioOut.connection(with: .audio) && self.aInput?.isReadyForMoreMediaData == true {
            self.aInput?.append(sampleBuffer)
        }
    }
    
}

extension LumagineCameraViewModel: MTKViewDelegate {
    
    func draw(in view: MTKView) {
         
        guard let sampleBuffer = sampleBuffer, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        var luminanceCVTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, imageBuffer, nil, .r8Unorm, width, height, 0, &luminanceCVTexture)
        
        var crominanceCVTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, imageBuffer, nil, .rg8Unorm, width/2, height/2, 1, &crominanceCVTexture)
        
        guard let luminanceCVTexture = luminanceCVTexture,
              let inputLuminance = CVMetalTextureGetTexture(luminanceCVTexture),
              let crominanceCVTexture = crominanceCVTexture,
              let inputCrominance = CVMetalTextureGetTexture(crominanceCVTexture)
        else { return }
        
        self.mtkView.drawableSize = CGSize(width: width, height: height)
        guard let drawable: CAMetalDrawable = self.mtkView.currentDrawable else { fatalError("Failed to create drawable") }
        
        if let commandBuffer = commandQueue.makeCommandBuffer(), let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() {
            
            computeCommandEncoder.setComputePipelineState(computePipelineState)
            computeCommandEncoder.setTexture(inputLuminance, index: 0)
            computeCommandEncoder.setTexture(inputCrominance, index: 1)
            computeCommandEncoder.setTexture(drawable.texture, index: 2)
             
            if let cubeBuffer = self.cubeBuffer {
                computeCommandEncoder.setBuffer(cubeBuffer.0, offset: 0, index: 0)
                computeCommandEncoder.setBuffer(cubeBuffer.1, offset: 0, index: 1)
                computeCommandEncoder.setBytes([self.intensity/100], length: MemoryLayout<Float>.size, index: 2)
            } else {
                
                let lutSizeBuffer = self.mtlDevice.makeBuffer(bytes: [2], length: MemoryLayout<Int>.size)
                computeCommandEncoder.setBuffer(lutSizeBuffer, offset: 0, index: 0)
                  
                let lutBuffer = self.mtlDevice.makeBuffer(bytes: neutralLutArray, length: neutralLutArray.count * MemoryLayout<SIMD4<Float>>.stride, options: [])
                computeCommandEncoder.setBuffer(lutBuffer, offset: 0, index: 1)
                computeCommandEncoder.setBytes([0], length: MemoryLayout<Float>.size, index: 2)
                 
            }

            computeCommandEncoder.dispatchThreadgroups(inputLuminance.threadGroups(), threadsPerThreadgroup: inputLuminance.threadGroupCount())
            computeCommandEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.addCompletedHandler { buffer in
                
                guard let adaptor = self.adaptor else { return }
                guard self.isCapturing && self.assetWriter?.status == .writing && self.sessionAtSourceTime != nil && self.vInput?.isReadyForMoreMediaData == true  else { return }
                
                var pixelBuffer: CVPixelBuffer?
                
                let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
                guard let pixelBuffer = pixelBuffer, pixelBufferStatus == kCVReturnSuccess else { return }
        
                CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                
                let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                
                guard let liminanceBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0), let chrominanceBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
                else { return }
                
                inputLuminance.getBytes(liminanceBytes, bytesPerRow: lumaBytesPerRow, from: MTLRegionMake2D(0, 0, inputLuminance.width, inputLuminance.height), mipmapLevel: 0)
                inputCrominance.getBytes(chrominanceBytes, bytesPerRow: chromaBytesPerRow, from: MTLRegionMake2D(0, 0, inputCrominance.width, inputCrominance.height), mipmapLevel: 0)
                
                if (!adaptor.append(pixelBuffer, withPresentationTime: stamp)) { print("Problem appending pixel buffer at time: \(stamp)") }
                
                print("DID ADD NEW BUFFER")
                
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
}

extension MTLTexture {
    
    func threadGroupCount() -> MTLSize {
        return MTLSizeMake(8, 8, 1)
    }
    
    func threadGroups() -> MTLSize {
        let groupCount = threadGroupCount()
        return MTLSize(width: (Int(width) + groupCount.width-1)/groupCount.width,
                       height: (Int(height) + groupCount.height-1)/groupCount.height,
                       depth: 1)
    }
}

extension Data {
    
    var float: Float {
        get {
            let value = self.withUnsafeBytes{$0.load(as: Float.self)}
            return value
        }
    }
}

extension UIScreen {
    
    static let sWidth = UIScreen.main.bounds.width
    static let sHeight = UIScreen.main.bounds.height

}

enum CaptureMode {
    case photo
    case video
}
