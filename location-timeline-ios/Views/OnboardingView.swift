import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private static let accent = Color(red: 1, green: 0.34, blue: 0.6)

    private struct Page {
        var icon: String
        var title: String
        var subtitle: String
    }

    private let pages: [Page] = [
        Page(
            icon: "point.topleft.down.curvedto.point.bottomright.up.fill",
            title: "Turn Your Timeline Into a Video",
            subtitle: "Import your Google Maps Timeline and get back an animated journey video — the camera follows your route, entirely on your phone."
        ),
        Page(
            icon: "mappin.and.ellipse",
            title: "Zooms Into Every City",
            subtitle: "Long trips get an overview, local moving-around gets a close-up. Live captions show which city you're in and the distance covered so far."
        ),
        Page(
            icon: "square.and.arrow.down.on.square",
            title: "Bring Your Own Timeline",
            subtitle: "In Google Maps, tap your profile → Settings → Personal content → Export Timeline data. Nothing is uploaded anywhere — everything after that happens on this device."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { onFinish() }
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(height: 44)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Self.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Self.accent.opacity(0.12))
                    .frame(width: 168, height: 168)
                Image(systemName: page.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Self.accent)
                    .symbolEffect(.bounce, value: self.page)
            }
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
