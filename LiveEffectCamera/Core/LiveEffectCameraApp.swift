//
//  LiveEffectCameraApp.swift
//  LiveEffectCamera
//
//  Created by Владимир Костин on 01.07.2025.
//

import SwiftUI

@main
struct LiveEffectCameraApp: App {
    @State var viewModel: LECViewModel
    @State var permissions: PermissionsViewModel
    @State var location: LocationViewModel
    
    init() {
        let viewModel = LECViewModel()
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
