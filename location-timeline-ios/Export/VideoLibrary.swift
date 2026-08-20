import Foundation
import Combine

struct VideoMedia: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var fileName: String
}

/// Persists generated videos under Documents/Videos with a JSON sidecar for metadata.
/// ponytail: JSON file instead of Core Data/SwiftData — a handful of records, no queries needed.
@MainActor
final class VideoLibrary: ObservableObject {
    @Published private(set) var items: [VideoMedia] = []

    private let directory: URL
    private let indexURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        indexURL = directory.appendingPathComponent("index.json")
        load()
    }

    func url(for media: VideoMedia) -> URL {
        directory.appendingPathComponent(media.fileName)
    }

    func add(title: String, temporaryFileURL: URL) throws -> VideoMedia {
        let media = VideoMedia(id: UUID(), title: title, createdAt: Date(), fileName: "\(UUID().uuidString).mp4")
        try FileManager.default.moveItem(at: temporaryFileURL, to: url(for: media))
        items.insert(media, at: 0)
        save()
        return media
    }

    func delete(_ media: VideoMedia) {
        try? FileManager.default.removeItem(at: url(for: media))
        items.removeAll { $0.id == media.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL), let decoded = try? JSONDecoder().decode([VideoMedia].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL)
    }
}
