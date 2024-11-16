//
//  LiveEffectCameraApp.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 14.11.2024.
//

import SwiftUI

@main
struct LiveEffectCameraApp: App {
    @State var viewModel: MainViewModel
    @State var permissions: PermissionsViewModel
    @State var location: LocationViewModel
    
    init() {
        let viewModel = MainViewModel()
        self.viewModel = viewModel
        self.permissions = .init(viewModel: viewModel)
        self.location = .init()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(permissions)
                .environment(location)
        }
    }
}
