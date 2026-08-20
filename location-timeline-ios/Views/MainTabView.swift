import SwiftUI

struct MainTabView: View {
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
    MainTabView()
}
