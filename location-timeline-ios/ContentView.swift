//
//  ContentView.swift
//  location-timeline-ios
//
//  Created by Hasan Ali on 20.08.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var library = VideoLibrary()

    var body: some View {
        TabView {
            VideoLibraryView()
                .tabItem { Label("Videos", systemImage: "film") }
            NewVideoView()
                .tabItem { Label("New Video", systemImage: "plus.circle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(library)
    }
}

#Preview {
    ContentView()
}
