//
//  ContentView.swift
//  LiveEffectsCamera
//
//  Created by Владимир Костин on 10.01.2023.
//

import SwiftUI

struct ContentView: View {
    
    
    @State var showCamera: Bool = false
    
    var body: some View {
        ZStack {
            Color.gray
            Button(action: {showCamera.toggle()}) {
                Text("Start camera")
            }
            .buttonStyle(BorderedButtonStyle())
        }
        
        .fullScreenCover(isPresented: $showCamera) {
            
        }
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
