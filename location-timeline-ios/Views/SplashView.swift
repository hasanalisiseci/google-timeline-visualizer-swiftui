import SwiftUI

/// A custom splash shown right after the native (instant, static) launch screen — same dark
/// background and route/marker mark, but animated, so the brand moment actually gets seen instead
/// of flashing by. `ContentView` holds this on screen for a fixed duration before moving on.
struct SplashView: View {
    private static let accent = Color(red: 1, green: 0.34, blue: 0.6)
    private static let background = Color(red: 0.07, green: 0.08, blue: 0.13)

    @State private var trim: CGFloat = 0
    @State private var markerScale: CGFloat = 0.2
    @State private var markerOpacity: Double = 0
    @State private var titleOpacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.10, blue: 0.16), Self.background],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    ZStack {
                        routePath(size: size)
                            .trim(from: 0, to: trim)
                            .stroke(Self.accent, style: StrokeStyle(lineWidth: size * 0.052, lineCap: .round, lineJoin: .round))
                            .shadow(color: Self.accent.opacity(0.6), radius: size * 0.05)
                        marker(size: size)
                            .scaleEffect(markerScale)
                            .opacity(markerOpacity)
                    }
                }
                .frame(width: 180, height: 180)

                Text("Google Timeline Visualizer")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(titleOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9)) { trim = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.75)) {
                markerScale = 1
                markerOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.5).delay(1.0)) {
                titleOpacity = 1
            }
        }
    }

    private func routePath(size: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size * 0.20, y: size * 0.74))
            path.addCurve(
                to: CGPoint(x: size * 0.52, y: size * 0.60),
                control1: CGPoint(x: size * 0.32, y: size * 0.82),
                control2: CGPoint(x: size * 0.38, y: size * 0.68)
            )
            path.addCurve(
                to: CGPoint(x: size * 0.74, y: size * 0.30),
                control1: CGPoint(x: size * 0.68, y: size * 0.51),
                control2: CGPoint(x: size * 0.64, y: size * 0.38)
            )
        }
    }

    private func marker(size: CGFloat) -> some View {
        let center = CGPoint(x: size * 0.74, y: size * 0.30)
        let outerRadius = size * 0.085
        return ZStack {
            Circle()
                .fill(.white)
                .frame(width: outerRadius * 2, height: outerRadius * 2)
                .shadow(color: Self.accent.opacity(0.6), radius: size * 0.05)
            Circle()
                .fill(Self.accent)
                .frame(width: outerRadius * 1.1, height: outerRadius * 1.1)
        }
        .position(center)
    }
}

#Preview {
    SplashView()
}
