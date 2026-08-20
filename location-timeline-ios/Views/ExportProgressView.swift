import SwiftUI
import AVKit

struct ExportProgressView: View {
    let request: VideoExportRequest
    let onDismiss: () -> Void

    @EnvironmentObject private var library: VideoLibrary
    @State private var progress: Double = 0
    @State private var statusText = "Finding places you passed through…"
    @State private var resultURL: URL?
    @State private var errorMessage: String?
    @State private var isPlaying = false

    /// Fraction of the bar spent reverse-geocoding city waypoints before rendering starts.
    private let cityLookupWeight = 0.1

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let resultURL {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Video ready")
                        .font(.title2.bold())
                    Button {
                        isPlaying = true
                    } label: {
                        Label("Watch", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    ShareLink(item: resultURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else if let errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 32)
                    Text("\(statusText) \(Int(progress * 100))%")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Exporting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .fullScreenCover(isPresented: $isPlaying) {
                if let resultURL {
                    VideoPlayer(player: AVPlayer(url: resultURL))
                        .ignoresSafeArea()
                        .overlay(alignment: .topTrailing) {
                            Button {
                                isPlaying = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                                    .padding()
                            }
                        }
                }
            }
            .task {
                await runExport()
            }
        }
    }

    private func runExport() async {
        let cities = await CityLookup.waypoints(for: request.journey) { value in
            progress = cityLookupWeight * value
        }
        statusText = "Rendering video…"
        do {
            let url = try await VideoExporter.export(request, cities: cities) { value in
                progress = cityLookupWeight + (1 - cityLookupWeight) * value
            }
            let saved = try library.add(title: request.title, temporaryFileURL: url)
            resultURL = library.url(for: saved)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
