//
//  AssetItem.swift
//  LiveEffectsCamera
//
//  Created by Владимир Костин on 10.01.2023.
//

import AVKit
import AVFoundation
import SwiftUI

struct AssetItem: View {
    
    @State var file: URL
    
    @State var image = UIImage()
    
    @State var showVideo = false
    @State var player: AVPlayer?
    
    var body: some View {
        ZStack(){
            Color.gray
            Button(action: {
                let playerItem = AVPlayerItem(url: file)
                self.player = AVPlayer(playerItem: playerItem)
                if player != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                        showVideo.toggle()
                    }
                }
            }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: (UIScreen.main.bounds.size.width - 54)/3, height: (UIScreen.main.bounds.size.width - 54)/3, alignment: .center)
        .clipped()
        .onAppear{
            imageFromVideo(url: file, at: 0) { image in
                if let image = image {
                    self.image = image
                }
            }
        }
        .sheet(isPresented: $showVideo, onDismiss: {
            player = nil
        }) {
            VideoPlayer(player: player)
        }
    }
    
    func imageFromVideo(url: URL, at time: TimeInterval, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let asset = AVURLAsset(url: url)

            let assetIG = AVAssetImageGenerator(asset: asset)
            assetIG.appliesPreferredTrackTransform = true
            assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels

            let cmTime = CMTime(seconds: time, preferredTimescale: 60)
            let thumbnailImageRef: CGImage
            do {
                thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
            } catch let error {
                print("Error: \(error)")
                return completion(nil)
            }

            DispatchQueue.main.async {
                let initImage = UIImage(cgImage: thumbnailImageRef, scale: 1.0, orientation: .up)
                completion(initImage)
            }
        }
    }
    
    
}
