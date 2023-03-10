//
//  PHCameraViewModel.swift
//  PHLow
//
//  Created by Владимир Костин on 06.12.2022.
//

import AVFoundation
import Combine
import CoreMotion
import SwiftUI
import MetalKit


class PHCameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    // Authorization status
    @Published var cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    
    //Devices
    @Published var backDevices: [AVCaptureDevice.DeviceType] = []
    @Published var frontDevice: AVCaptureDevice.DeviceType?
    @Published var curBackDevice: AVCaptureDevice.DeviceType?
    
    @Published var position: AVCaptureDevice.Position = .back
    @Published var orientation = AVCaptureVideoOrientation.portrait
    
    @Published var session = AVCaptureSession()
    
    @Published var photoOut = AVCapturePhotoOutput()
    @Published var videoOut = AVCaptureVideoDataOutput()
    @Published var audioOut = AVCaptureAudioDataOutput()
    
    @Published var isRunning = false
   
    @Published var captureState = CaptureState.idle
    
    @Published var duration: Int = 0
    
    @Published var warmth: Float = 0
    @Published var gamma: Float = 0
    
    var cancellable: Set<AnyCancellable> = []
    
    var vDevice = AVCaptureDevice.default(for: .video)!
    
    private var keyValueObservations = [NSKeyValueObservation]()
    private var lastFrameTimeStamp: CMTime = .zero
    private var firstFrameTimeStamp: CMTime = .zero
    
    var mtkView: MTKView?
    private var buffer: CMSampleBuffer?
    private var videoWriter: VideoWriter?

    let sessionQueue = DispatchQueue(label: "session", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit)
    let videoQueue = DispatchQueue(label: "video", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    
    let mManager = CMMotionManager()
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let context: CIContext
    let colorSpace: CGColorSpace
    
    override init() {
        
        guard let colorSpace = CGColorSpace.init(name: CGColorSpace.displayP3_HLG) else { fatalError() }
        self.colorSpace = colorSpace
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        self.context = CIContext(
            mtlDevice: self.device,
            options: [.cacheIntermediates: true, .allowLowPower: false, .highQualityDownsample: true, .workingColorSpace: self.colorSpace])
        
        super.init()
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
            .sink { value in
                switch value {
                case .authorized:
                    self.backDevices = self.getAvaliableBackDevices()
                    self.frontDevice = self.getAvaliableFrontDevice()
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
                self.curBackDevice = self.setDefaultDevice()
            }
            .store(in: &cancellable)
        $curBackDevice
            .sink { value in
                guard let value = value else { return }
                self.setupMotionManager()
                self.startNewSession(with: value, in: self.position)
            }
            .store(in: &cancellable)
        $position
            .dropFirst()
            .sink { value in
                var device: AVCaptureDevice.DeviceType?
                
                switch value {
                case .back: device = self.curBackDevice
                case .front: device = self.frontDevice
                default: return
                }
                
                guard let device = device else { return }
                self.startNewSession( with: device, in: value)
            }
            .store(in: &cancellable)
       
        
    }
    
    deinit {
        print("Deinit camera view model")
    }
    
    enum CaptureState {
        case idle, start, starting, writing, ending, end
    }
    
    func getAvaliableBackDevices() -> [AVCaptureDevice.DeviceType] {
        
        var devices: [AVCaptureDevice.DeviceType] = []
        
        if let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            devices.append(device.deviceType)
        }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            devices.append(device.deviceType)
        }
        if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            devices.append(device.deviceType)
        }

        return devices
    }
    
    func getAvaliableFrontDevice() -> AVCaptureDevice.DeviceType? {
        
        let discoverSession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTelephotoCamera, .builtInTripleCamera, .builtInUltraWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
        
        let devices = discoverSession.devices
        
        return devices.first?.deviceType
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
    
    func startNewSession(with device: AVCaptureDevice.DeviceType, in position: AVCaptureDevice.Position){
        
        sessionQueue.async {
            self.stopSession()
            
            do {
                if position == .back {
                    
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd4K3840x2160
                    
                    self.vDevice = AVCaptureDevice.default(device, for: .video, position: position)!
                    
                    let vInput = try AVCaptureDeviceInput(device: self.vDevice)
                    if self.session.canAddInput(vInput) { self.session.addInput(vInput) }
                    
                    let settings: [String : Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                    ]
                    
                    self.videoOut.videoSettings = settings
                    self.videoOut.alwaysDiscardsLateVideoFrames = true
                    self.videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                    if self.session.canAddOutput(self.videoOut) {
                        self.session.addOutput(self.videoOut)
                    }
                    
                    self.videoOut.connection(with: .video)?.videoOrientation = .portrait
                    
                    guard let connection = self.videoOut.connection(with: .video) else {return}
                    if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
                    
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                        let aDevice = AVCaptureDevice.default(for: .audio)!
                        let aInput = try AVCaptureDeviceInput(device: aDevice)
                        if self.session.canAddInput(aInput) { self.session.addInput(aInput) }
                        
                        self.audioOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                        if self.session.canAddOutput(self.audioOut) { self.session.addOutput(self.audioOut) }
                    }
                    
                } else if position == .front {
                    
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .hd1920x1080
                    
                    self.vDevice = AVCaptureDevice.default(device, for: .video, position: position)!
                    
                    let vInput = try AVCaptureDeviceInput(device: self.vDevice)
                    if self.session.canAddInput(vInput) { self.session.addInput(vInput) }
                    
                    let settings: [String : Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
                    ]
                    
                    self.videoOut.videoSettings = settings
                    self.videoOut.alwaysDiscardsLateVideoFrames = true
                    self.videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                    if self.session.canAddOutput(self.videoOut) {
                        self.session.addOutput(self.videoOut)
                    }
                    
                    self.videoOut.connection(with: .video)?.videoOrientation = .portrait
                    
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                        let aDevice = AVCaptureDevice.default(for: .audio)!
                        let aInput = try AVCaptureDeviceInput(device: aDevice)
                        if self.session.canAddInput(aInput) { self.session.addInput(aInput) }
                        
                        self.audioOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                        if self.session.canAddOutput(self.audioOut) { self.session.addOutput(self.audioOut) }
                    }
                    
                }
                
                self.session.commitConfiguration()
                self.session.startRunning()
                
                if self.session.isRunning {
                    DispatchQueue.main.async { self.isRunning = true }
                }
                
            } catch {
                print(error.localizedDescription)
            }
            
        }
        
    }
    
    func stopSession() {
        
        if self.session.isRunning {
            
            DispatchQueue.main.async {
                self.isRunning = false
            }
            if self.captureState == .writing {
                DispatchQueue.main.async { self.captureState = .end }
            }
            
            self.session.stopRunning()
        }
        
        self.session.inputs.forEach{self.session.removeInput($0)}
        self.session.outputs.forEach{self.session.removeOutput($0)}
    
        self.keyValueObservations.forEach{ $0.invalidate() }
        self.keyValueObservations.removeAll()
        
    }
    
    func setupMotionManager() {
        mManager.accelerometerUpdateInterval = 0.25
        mManager.startAccelerometerUpdates(to: OperationQueue.main) { (data, error) in
            if error != nil { print(error as Any) }
            
            if let data = data {
                let x = data.acceleration.x
                let y = data.acceleration.y
                
                if -y > x && x > y { self.orientation = .portrait }
                else if -y < x && x > y { self.orientation = .landscapeLeft }
                else if x < y && -x < y { self.orientation = .portraitUpsideDown }
                else { self.orientation = .landscapeRight }
            
            } else {
                print("No data")
            }
        }
    }
    
    func capture() {
        
        if captureState == .writing {
            DispatchQueue.main.async { self.captureState = .end }
        }
        
        if captureState == .idle {
            DispatchQueue.main.async { self.captureState = .start }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if self.captureState == .ending { return }
        
        if connection == videoOut.connection(with: .video) {
            self.buffer = sampleBuffer
            self.mtkView?.draw()
        }
        
        switch self.captureState {
        case .start:
            DispatchQueue.main.async { self.captureState = .starting }
            let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let fileName = UUID().uuidString
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(fileName).mov")
            guard let vSettings = self.videoOut.recommendedVideoSettingsForAssetWriter(writingTo: .mov) else { return }
            guard let aSettings = self.audioOut.recommendedAudioSettingsForAssetWriter(writingTo: .mov) else { return }
            do {
                self.videoWriter = try VideoWriter(url, vSettings, self.orientation, aSettings, timeStamp.timescale)
                
                if self.videoWriter?.startWriting(at: timeStamp) == true {
                    self.firstFrameTimeStamp = timeStamp
                    DispatchQueue.main.async { self.captureState = .writing }
                } else {
                    print("Failed start writing")
                }
            } catch {
                print(error)
            }
            
        case .end:
            DispatchQueue.main.async { self.captureState = .ending }
            self.videoWriter?.endWriting() { result in
                print("HANDLER")
                guard result != nil else { return }
                DispatchQueue.main.async { self.captureState = .idle }
                self.videoWriter = nil
                
            }
        case .writing:
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            DispatchQueue.main.async { self.duration = Int(timestamp.seconds - self.firstFrameTimeStamp.seconds) }
            if connection == audioOut.connection(with: .audio) {
                self.videoWriter?.addAudioSample(sampleBuffer)
            }
        default: return
        }

    }

}

extension PHCameraViewModel: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { return }
    
    
    func draw(in view: MTKView) {
        
        guard let drawable = view.currentDrawable, let commandBuffer = commandQueue.makeCommandBuffer(), let buffer = buffer else { return }
        
        guard let imageBuffer = buffer.imageBuffer else { return }
        var image = CIImage(cvImageBuffer: imageBuffer)
        
        if let filter = CIFilter( name: "CIFaceBalance", parameters: [
                "inputImage" : image,
                "inputOrigI" : 0.103905,
                "inputOrigQ" : 0.0176465,
                "inputStrength" : 0.5,
                "inputWarmth" : 0.5 + CGFloat(warmth/20)
            ]
        ) {
            if let output = filter.outputImage { image = output }
        }
        
        if let filter = CIFilter(name: "CIGammaAdjust", parameters: ["inputImage" : image, "inputPower" : 1 + gamma/100]) {
            if let output = filter.outputImage { image = output }
        }
        
        if self.captureState == .writing {
            context.render(image, to: imageBuffer)
            self.videoWriter?.addVideoFrame(imageBuffer, at: CMSampleBufferGetPresentationTimeStamp(buffer))
            image = CIImage(cvImageBuffer: imageBuffer)
        }
        let width = Int(view.drawableSize.width)
        
        let scaleFactor = CGFloat(width)/image.extent.size.width
        image = image.transformed(by: CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        
        context.render(image, to: drawable.texture, commandBuffer: commandBuffer, bounds: image.extent, colorSpace: self.colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

class VideoWriter {
    
    let assetWriter: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    
    var status: AVAssetWriter.Status = .unknown
    
    init(_ url: URL, _ vSettings: [String: Any], _ orientation: AVCaptureVideoOrientation, _ aSettings: [String: Any], _ timeScale: CMTimeScale) throws {
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.mediaTimeScale = timeScale
        switch orientation {
        case .portraitUpsideDown: videoInput.transform = CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight: videoInput.transform = CGAffineTransform(rotationAngle: .pi*3/2)
        case .landscapeLeft: videoInput.transform = CGAffineTransform(rotationAngle: .pi/2)
        default: videoInput.transform = CGAffineTransform(rotationAngle: 0)
        }
        
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        audioInput.expectsMediaDataInRealTime = true
        
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        assetWriter.movieTimeScale = timeScale
        
        if assetWriter.canAdd(videoInput) { self.assetWriter.add(videoInput); print("Video Input is added")}
        if assetWriter.canAdd(audioInput) { self.assetWriter.add(audioInput); print("Audio Input is added")}

    }
    
    deinit {
        print("DEINIT VIDEO WRITER")
    }
    
    func startWriting(at timeStamp: CMTime) -> Bool {
        if assetWriter.startWriting() {
            if assetWriter.status == .writing {
                self.assetWriter.startSession(atSourceTime: timeStamp)
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    func endWriting( _ handler: @escaping (URL?) -> Void){
        
        guard videoInput.isReadyForMoreMediaData && audioInput.isReadyForMoreMediaData else {
            handler(nil)
            return
        }
        
        guard assetWriter.status == .writing else {
            handler(nil)
            return
        }
        
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        print("MARKED AS FINISHED")
        
        assetWriter.finishWriting {
            if self.assetWriter.status == .completed {
                print("✅ WRITER STATUS: COMPLETED")
                handler(self.assetWriter.outputURL)
                return
            }
        }
    }
    
    func addAudioSample(_ buffer: CMSampleBuffer) {
        if audioInput.isReadyForMoreMediaData { audioInput.append(buffer) }
    }
    
    func addVideoFrame(_ imageBuffer: CVImageBuffer, at timeStamp: CMTime) {
        if videoInput.isReadyForMoreMediaData {
            adaptor.append(imageBuffer, withPresentationTime: timeStamp)
        }
    }
}
