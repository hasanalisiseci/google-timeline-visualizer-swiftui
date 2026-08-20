import SwiftUI
import AVKit

struct VideoLibraryView: View {
    @EnvironmentObject private var library: VideoLibrary
    @State private var playingURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if library.items.isEmpty {
                    ContentUnavailableView("No videos yet", systemImage: "film", description: Text("Create your first journey video from the New Video tab."))
                } else {
                    List {
                        ForEach(library.items) { media in
                            Button {
                                playingURL = library.url(for: media)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(media.title).font(.headline)
                                    Text(media.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet { library.delete(library.items[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Videos")
            .fullScreenCover(item: Binding(get: { playingURL.map(IdentifiableURL.init) }, set: { playingURL = $0?.url })) { wrapper in
                VideoPlayer(player: AVPlayer(url: wrapper.url))
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            playingURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .padding()
                        }
                    }
            }
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}
