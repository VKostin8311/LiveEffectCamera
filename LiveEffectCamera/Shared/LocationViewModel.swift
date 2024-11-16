//
//  LocationViewModel.swift
//  QuantCap
//
//  Created by Владимир Костин on 25.09.2024.
//


import Foundation
import CoreLocation
import Observation
import SwiftUI


@Observable final class LocationViewModel: NSObject, CLLocationManagerDelegate {
    
    var locationStatus = CLAuthorizationStatus.notDetermined
    var currentLocation: CLLocation?
    
    let manager: CLLocationManager = .init()
    
    override init() {
        super.init()
        self.checkPermissions()
    }
    
    func checkPermissions() {
        self.locationStatus = manager.authorizationStatus
        self.manager.delegate = self
    }
    
    func requestLocation() {
        self.manager.requestWhenInUseAuthorization()
    }
    
    func startLocation() {
        guard self.locationStatus == .authorizedWhenInUse else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()
    }
    
    func stopLocation() {
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        
        DispatchQueue.main.async {
            withAnimation { self.locationStatus = manager.authorizationStatus }
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        DispatchQueue.main.async {
            self.currentLocation = locations.first
        }
        
    }
}
