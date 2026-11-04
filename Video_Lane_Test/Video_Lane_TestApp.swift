//
//  Video_Lane_TestApp.swift
//  Video_Lane_Test
//
//  Created by Oliver Paver on 3/4/25.
//

import SwiftUI

@main
struct Video_Lane_TestApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                            ContentView()
                                .tabItem { Label("Image", systemImage: "photo") }
                            VideoContentView()
                                .tabItem { Label("Video", systemImage: "video") }
                             
                        }
        }
    }
}
