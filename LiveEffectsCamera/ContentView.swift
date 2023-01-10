//
//  ContentView.swift
//  LiveEffectsCamera
//
//  Created by Владимир Костин on 10.01.2023.
//

import SwiftUI

struct ContentView: View {
    
    
    @State var showCamera: Bool = false
    
    @State var files: [URL] = []
    
    let gridItems = [
        GridItem(.fixed((UIScreen.main.bounds.size.width - 54)/3)),
        GridItem(.fixed((UIScreen.main.bounds.size.width - 54)/3)),
        GridItem(.fixed((UIScreen.main.bounds.size.width - 54)/3))]
    
    let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    
    var body: some View {
        VStack {
            
            ScrollView(){
                
                LazyVGrid(columns: gridItems, alignment: .center, spacing: 11) {
                    ForEach(files, id: \.self) { url in
                        AssetItem(file: url)
                    }
                    
                }
            }
            
            Button(action: {showCamera.toggle()}) {
                Text("Start camera")
            }
            .buttonStyle(BorderedButtonStyle())
            .padding(.bottom, 20)
        }
        .onAppear{
            guard let documentDirectory = documentDirectory else { return }
            do {
                files = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
            } catch {
                return
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            guard let documentDirectory = documentDirectory else { return }
            do {
                files = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
            } catch {
                return
            }
        }) {
            PHCameraView()
        }
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
