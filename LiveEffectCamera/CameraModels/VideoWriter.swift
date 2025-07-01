//
//  VideoWriter.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//


import AVFoundation
import CoreLocation
import UIKit
import VideoToolbox

actor VideoWriter {
	
	let assetWriter: AVAssetWriter
	let vInput: AVAssetWriterInput
	let aInput: AVAssetWriterInput
	let location: CLLocation?
	
	var duration: Double = 0
	var status: VideoWriter.Status = .idle
	
	private var sessionAtSourceTime: CMTime?
	private var audioBuffer: [CMSampleBuffer] = []
	 
	init(frameRate: Int, videoOut: AVCaptureVideoDataOutput, audioOut: AVCaptureAudioDataOutput, quality: VideoQuality, orientation: VideoOrientation, location: CLLocation?) {
		guard let width = videoOut.videoSettings["Width"] as? Int else { fatalError() }
		guard let height = videoOut.videoSettings["Height"] as? Int else { fatalError() }
		
		let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("VideoOutput.MOV")
		
		if FileManager.default.fileExists(atPath: url.path) {
			try? FileManager.default.removeItem(at: url)
		}
		
		var vSettings = videoOut.recommendedVideoSettingsForAssetWriter(writingTo: .mov) ?? [:]
		let aSettings = audioOut.recommendedAudioSettingsForAssetWriter(writingTo: .mov) ?? [:]
		
		var compressionSettings: [String: Any] = vSettings["AVVideoCompressionPropertiesKey"] as! [String: Any]
		compressionSettings["ExpectedFrameRate"] = frameRate
		
		switch quality {
		case .normal: compressionSettings["AverageBitRate"] = Int(0.1*Double(frameRate))*width*height
		case .high: compressionSettings["AverageBitRate"] = Int(0.125*Double(frameRate))*width*height
		case .max: compressionSettings["AverageBitRate"] = Int(0.15*Double(frameRate))*width*height
		}
		
		compressionSettings["ProfileLevel"] = kVTProfileLevel_HEVC_Main_AutoLevel
		vSettings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
											  AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
												   AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
		
		vSettings["AVVideoCompressionPropertiesKey"] = compressionSettings

		do {
			let assetWriter = try AVAssetWriter(url: url, fileType: AVFileType.mov)
			assetWriter.movieFragmentInterval = CMTimeMakeWithSeconds(10.0, preferredTimescale: 1)
			assetWriter.shouldOptimizeForNetworkUse = false
			
			
			let vInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: vSettings)
			vInput.expectsMediaDataInRealTime = true
			
			switch orientation {
			case .portraitUpsideDown: vInput.transform = CGAffineTransform(rotationAngle: .pi)
			case .landscapeRight: vInput.transform = CGAffineTransform(rotationAngle: .pi*3/2)
			case .landscapeLeft: vInput.transform = CGAffineTransform(rotationAngle: .pi/2)
			default: vInput.transform = CGAffineTransform(rotationAngle: 0)
			}
		
			if assetWriter.canAdd(vInput) { assetWriter.add(vInput) }

			let aInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: aSettings)
			
			aInput.expectsMediaDataInRealTime = true
		
			if assetWriter.canAdd(aInput) { assetWriter.add(aInput) }
			
			self.assetWriter = assetWriter
			self.vInput = vInput
			self.aInput = aInput
			self.location = location
			
		} catch {
			fatalError(error.localizedDescription)
		}
	}
	
	func startRecording(at sourceTime: CMTime) async {
		if status != .idle { return }
	 
		assetWriter.metadata = makeAVMetaData(with: location)
		let result = assetWriter.startWriting()
		guard result else { fatalError("Couldn't start writing") }
		
		status = .starting
		
		let startingTimeDelay = CMTimeMakeWithSeconds(0.5, preferredTimescale: 1000000000)
		let startTimeToUse = CMTimeAdd(sourceTime, startingTimeDelay)
		
		sessionAtSourceTime = startTimeToUse
		
		assetWriter.startSession(atSourceTime: startTimeToUse)
		
		if assetWriter.status == .writing {
			status = .recording
		} else {
			status = .idle
		}
		
	}
	
	func stopRecording() async -> URL? {
		status = .finishing
	
		guard assetWriter.status == .writing else { return nil }
		
		vInput.markAsFinished()
		aInput.markAsFinished()
		await assetWriter.finishWriting()
		
		let url = assetWriter.outputURL
			
		let asset = AVAsset(url: url)
		
		do {
			let isPlayable = try await asset.load(.isPlayable)
			guard isPlayable else {
				// Is not playable
				try FileManager.default.removeItem(at: url)
				return nil
			}
		} catch {
			return nil
		}
		 
		return url
	}
	
	func avaliableNewAudio(_ buffer: CMSampleBuffer) async {

		guard status == .recording else { return }
		audioBuffer.append(buffer)
	}
	
	func avaliableNewVideo(_ buffer: CMSampleBuffer) async {
		
		guard let sessionAtSourceTime = sessionAtSourceTime else { return }
		let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
		if sessionAtSourceTime.seconds > timestamp.seconds { return }
		
		guard assetWriter.status == .writing && vInput.isReadyForMoreMediaData else { return }
	
		duration = timestamp.seconds - sessionAtSourceTime.seconds

		vInput.append(buffer)
		
		await flushAudioBuffer(upTo: timestamp)
	}
	
	private func flushAudioBuffer(upTo time: CMTime) async {
		
		var processed: [CMSampleBuffer] = []
		for sampleBuffer in audioBuffer {
			let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
			if sampleTime <= time && aInput.isReadyForMoreMediaData {
				aInput.append(sampleBuffer)
				processed.append(sampleBuffer)
			}
		}
		
		audioBuffer.removeAll { processed.contains($0) }
	}
	
	func makeAVMetaData(with location: CLLocation?) -> [AVMetadataItem] {
		var result: [AVMetadataItem] = []
		
		if let location = location {
			
			let accuracyItem = AVMutableMetadataItem()
			accuracyItem.keySpace = AVMetadataKeySpace("mdta")
			accuracyItem.key = "com.apple.quicktime.location.accuracy.horizontal" as any NSCopying & NSObjectProtocol
			accuracyItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.location.accuracy.horizontal")
			accuracyItem.dataType = "com.apple.metadata.datatype.UTF-8"
			accuracyItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
			accuracyItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
			accuracyItem.value = location.horizontalAccuracy.magnitude as any NSCopying & NSObjectProtocol
			accuracyItem.extraAttributes = [
				AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
				AVMetadataExtraAttributeKey("dataType") : 1
			]
			
			result.append(accuracyItem)
			
			let latitudeFormatter = NumberFormatter()
			latitudeFormatter.maximumFractionDigits = 4
			latitudeFormatter.minimumFractionDigits = 4
			latitudeFormatter.maximumIntegerDigits = 2
			latitudeFormatter.minimumIntegerDigits = 2
			latitudeFormatter.positivePrefix = "+"
			latitudeFormatter.decimalSeparator = "."
			
			let latitude = latitudeFormatter.string(from: location.coordinate.latitude as NSNumber) ?? "+00.0001"
			
			let longitudeFormatter = NumberFormatter()
			longitudeFormatter.maximumFractionDigits = 4
			longitudeFormatter.minimumFractionDigits = 4
			longitudeFormatter.maximumIntegerDigits = 3
			longitudeFormatter.minimumIntegerDigits = 3
			longitudeFormatter.positivePrefix = "+"
			longitudeFormatter.decimalSeparator = "."
			
			let longitude =  longitudeFormatter.string(from: location.coordinate.longitude as NSNumber) ?? "+000.0001"
			
			let altitudeFormatter = NumberFormatter()
			altitudeFormatter.maximumFractionDigits = 3
			altitudeFormatter.minimumFractionDigits = 3
			altitudeFormatter.maximumIntegerDigits = 4
			altitudeFormatter.minimumIntegerDigits = 3
			altitudeFormatter.positivePrefix = "+"
			altitudeFormatter.decimalSeparator = "."
			
			
			let altitude = altitudeFormatter.string(from: location.altitude as NSNumber) ?? "+001.000"
			
			let locationItem = AVMutableMetadataItem()
			locationItem.keySpace = AVMetadataKeySpace("mdta")
			locationItem.key = AVMetadataKey.quickTimeMetadataKeyLocationISO6709 as any NSCopying & NSObjectProtocol
			locationItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.location.ISO6709")
			locationItem.dataType = "com.apple.metadata.datatype.UTF-8"
			locationItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
			locationItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
			locationItem.value = "\(latitude)\(longitude)\(altitude)/" as any NSCopying & NSObjectProtocol
			locationItem.extraAttributes = [
				AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
				AVMetadataExtraAttributeKey("dataType") : 1
			]
			
			result.append(locationItem)
		}
		
		let makeItem = AVMutableMetadataItem()
		makeItem.keySpace = AVMetadataKeySpace("mdta")
		makeItem.key = AVMetadataKey.quickTimeMetadataKeyMake as any NSCopying & NSObjectProtocol
		makeItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.make")
		makeItem.dataType = "com.apple.metadata.datatype.UTF-8"
		makeItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		makeItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		makeItem.value = "Phlow Inc." as any NSCopying & NSObjectProtocol
		makeItem.extraAttributes = [
			AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
			AVMetadataExtraAttributeKey("dataType") : 1
		]
		
		result.append(makeItem)
		
		let modelItem = AVMutableMetadataItem()
		modelItem.keySpace = AVMetadataKeySpace("mdta")
		modelItem.key = AVMetadataKey.quickTimeMetadataKeyModel as any NSCopying & NSObjectProtocol
		modelItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.model")
		modelItem.dataType = "com.apple.metadata.datatype.UTF-8"
		modelItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		modelItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		modelItem.value = "iPhone" as any NSCopying & NSObjectProtocol
		modelItem.extraAttributes = [
			AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
			AVMetadataExtraAttributeKey("dataType") : 1
		]
		
		result.append(modelItem)
		
		
		let softwareItem = AVMutableMetadataItem()
		softwareItem.keySpace = AVMetadataKeySpace("mdta")
		softwareItem.key = AVMetadataKey.quickTimeMetadataKeySoftware as any NSCopying & NSObjectProtocol
		softwareItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.software")
		softwareItem.dataType = "com.apple.metadata.datatype.UTF-8"
		softwareItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		softwareItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		softwareItem.value = self.appNameAndVersion() as any NSCopying & NSObjectProtocol
		softwareItem.extraAttributes = [
			AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
			AVMetadataExtraAttributeKey("dataType") : 1
		]
		
		result.append(softwareItem)
		
		let creationDateItem = AVMutableMetadataItem()
		creationDateItem.keySpace = AVMetadataKeySpace("mdta")
		creationDateItem.key = AVMetadataKey.quickTimeUserDataKeyCreationDate as any NSCopying & NSObjectProtocol
		creationDateItem.identifier = AVMetadataIdentifier("mdta/com.apple.quicktime.creationdate")
		creationDateItem.dataType = "com.apple.metadata.datatype.UTF-8"
		creationDateItem.time = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		creationDateItem.duration = CMTime(value: 0, timescale: 0, flags: CMTimeFlags(rawValue: 0), epoch: 0)
		creationDateItem.value = Date() as any NSCopying & NSObjectProtocol
		creationDateItem.extraAttributes = [
			AVMetadataExtraAttributeKey("dataTypeNamespace"): "com.apple.quicktime.mdta",
			AVMetadataExtraAttributeKey("dataType") : 1
		]
		
		result.append(creationDateItem)
		return result
		
	}
	
	func appNameAndVersion() -> String {
		let dictionary = Bundle.main.infoDictionary!
		let version = dictionary["CFBundleShortVersionString"] as! String
		let name = dictionary["CFBundleName"] as! String
		return "\(name) v\(version)"
	}
	
	enum Status {
		case idle
		case starting
		case recording
		case finishing
	}
}
