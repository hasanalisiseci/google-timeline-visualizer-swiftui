//
//  ContentView.swift
//  location-timeline-ios
//
//  Created by Hasan Ali on 20.08.2026.
//

import SwiftUI

/// App entry flow: an animated splash (extending the instant native launch screen so the brand
/// moment is actually visible), then a one-time onboarding for first launch, then the app itself.
struct ContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var isShowingSplash = true

    var body: some View {
        Group {
            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
            } else if !hasSeenOnboarding {
                OnboardingView { hasSeenOnboarding = true }
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isShowingSplash)
        .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
        .task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            isShowingSplash = false
        }
    }
}

#Preview {
    ContentView()
}
