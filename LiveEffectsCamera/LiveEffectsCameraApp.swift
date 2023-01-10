//
//  LiveEffectsCameraApp.swift
//  LiveEffectsCamera
//
//  Created by Владимир Костин on 10.01.2023.
//

import SwiftUI

@main
struct LiveEffectsCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap {
                $0 as? UIWindowScene
            }
            .flatMap {
                $0.windows
            }
            .first {
                $0.isKeyWindow
            }
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        UIApplication.shared.keyWindow?.safeAreaInsets.swiftUiInsets ?? EdgeInsets()
    }
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
}

private extension UIEdgeInsets {
    var swiftUiInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}


extension Color {
    
    init(ciColor: CIColor) {
        let r = ciColor.red
        let g = ciColor.green
        let b = ciColor.blue
        let a = ciColor.alpha
        
        self.init(
            .sRGB,
            red: Double(r),
            green: Double(g),
            blue:  Double(b),
            opacity: Double(a)
        )
    }
    
    init(hex: String?) {
        
        if hex == nil {
            
            self.init(
                .sRGB,
                red: Double(255) / 255,
                green: Double(255) / 255,
                blue:  Double(255) / 255,
                opacity: Double(0) / 255
            )
            
        } else {
            
            let hex = hex!.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let a, r, g, b: UInt64
            switch hex.count {
            case 3: // RGB (12-bit)
                (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6: // RGB (24-bit)
                (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8: // ARGB (32-bit)
                (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default:
                (a, r, g, b) = (1, 1, 1, 0)
            }
            
            self.init(
                .sRGB,
                red: Double(r) / 255,
                green: Double(g) / 255,
                blue:  Double(b) / 255,
                opacity: Double(a) / 255
            )
        }
    }
    
}
