//
//  PHCameraViewModel.swift
//  PHLow
//
//  Created by Владимир Костин on 06.12.2022.
//

import AVFoundation
import Combine
import CoreMotion
import Foundation
import SwiftUI
//
class PHCameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
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
   
    @Published var isCapturing = false
    @Published var captureState = CaptureState.idle
    
    @Published var duration: Int = 0
    
    var cancellable: Set<AnyCancellable> = []
    var renderer: CameraRenderer?
    var vDevice = AVCaptureDevice.default(for: .video)!
    
    private var keyValueObservations = [NSKeyValueObservation]()
    private var lastFrameTimeStamp: CMTime = .zero
    private var firstFrameTimeStamp: CMTime = .zero

    let sessionQueue = DispatchQueue(label: "session", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .inherit)
    let videoQueue = DispatchQueue(label: "video", qos: .userInitiated, attributes: .concurrent, autoreleaseFrequency: .workItem)
    
    let mManager = CMMotionManager()
    
    override init() {
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
        case idle, start, starting, capturing, end, ending
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
                    self.renderer?.isFrontCamera = false
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
                    self.renderer?.isFrontCamera = true
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
                if self.captureState == .capturing {
                    self.captureState = .end
                }
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
        switch captureState {
        case .idle:
            captureState = .start
        case .capturing:
            captureState = .end
        default:
            break
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let renderer = renderer else { return }
        
        if connection == videoOut.connection(with: .video) {
            renderer.buffer = sampleBuffer
            renderer.mtkView?.draw()
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        switch captureState {
        case .start:
            DispatchQueue.main.async { self.captureState = .starting }
            
            renderer.filename = UUID().uuidString
            let videoPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(renderer.filename).mov")
            
            do {
                let writer = try AVAssetWriter(outputURL: videoPath, fileType: .mov)
                let videoSettings = videoOut.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoInput.mediaTimeScale = timestamp.timescale
                videoInput.expectsMediaDataInRealTime = true
                
                
                switch self.orientation {
                    
                case .portraitUpsideDown:
                    videoInput.transform = CGAffineTransform(rotationAngle: .pi)
                case .landscapeRight:
                    videoInput.transform = CGAffineTransform(rotationAngle: .pi*3/2)
                case .landscapeLeft:
                    videoInput.transform = CGAffineTransform(rotationAngle: .pi/2)
                default:
                    videoInput.transform = CGAffineTransform(rotationAngle: 0)
                }
                
                
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
                if writer.canAdd(videoInput) {
                    writer.add(videoInput)
                    renderer.assetWriterVideoInput = videoInput
                }
                
                let audioSettings = audioOut.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                
                if writer.canAdd(audioInput) == true {
                    writer.add(audioInput)
                    renderer.assetWriterAudioInput = audioInput
                }
                
                writer.movieTimeScale = timestamp.timescale
                
                renderer.assetWriter = writer
                renderer.adaptor = adaptor
                
                writer.startWriting()
                
                print(writer.status.rawValue)
                
                if writer.status == .writing {
                    renderer.isCapturing = true
                    DispatchQueue.main.async { self.captureState = .capturing }
                    
                    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    
                    self.firstFrameTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                } else {
                    self.captureState = .idle
                }
            } catch {
                self.captureState = .idle
            }
            
        case .capturing:
            DispatchQueue.main.async { self.duration = Int(timestamp.seconds - self.firstFrameTimeStamp.seconds) }
            
            if connection == audioOut.connection(with: .audio) {
                if renderer.assetWriterAudioInput?.isReadyForMoreMediaData == true {
                    renderer.assetWriterAudioInput?.append(sampleBuffer)
                }
            }
            
            break
        case .end:
            guard renderer.assetWriterVideoInput?.isReadyForMoreMediaData == true,
                  renderer.assetWriterAudioInput?.isReadyForMoreMediaData == true else { return }
                  //renderer.assetWriter!.status != .failed else { break }
            
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(renderer.filename).mov")
            
            renderer.isCapturing = false
            
            renderer.assetWriterVideoInput?.markAsFinished()
            renderer.assetWriterAudioInput?.markAsFinished()
            
            renderer.assetWriter?.endSession(atSourceTime: timestamp)
            
            renderer.assetWriter?.finishWriting {
                DispatchQueue.main.async { self.captureState = .idle }
               
                renderer.assetWriter = nil
                renderer.assetWriterVideoInput = nil
                renderer.assetWriterAudioInput = nil
            }
            
        default:
            break
        }
        
    }
    
        
    
    
}


