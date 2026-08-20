import UIKit

/// Fetches and caches CartoDB basemap tiles, same source as the web visualizer.
actor TileCache {
    static let shared = TileCache()

    private var cache: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private func url(z: Int, x: Int, y: Int) -> URL? {
        URL(string: "https://a.basemaps.cartocdn.com/light_all/\(z)/\(x)/\(y).png")
    }

    func tile(z: Int, x: Int, y: Int) async -> UIImage? {
        let n = 1 << max(0, z)
        let wrappedX = ((x % n) + n) % n
        guard y >= 0, y < n else { return nil }
        let key = "\(z)/\(wrappedX)/\(y)"
        if let cached = cache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self, let url = await self.url(z: z, x: wrappedX, y: y) else { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
            await self.store(key: key, image: image)
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func store(key: String, image: UIImage) {
        cache[key] = image
    }

    /// Preloads every tile needed to cover `viewport` at its zoom, for a canvas of `size` points.
    func preload(viewport: Viewport, size: Double) async {
        let n = Double(1 << max(0, viewport.zoom))
        let minTileX = Int(floor(viewport.minX * n))
        let maxTileX = Int(floor(viewport.maxX * n))
        let minTileY = Int(floor(viewport.minY * n))
        let maxTileY = Int(floor(viewport.maxY * n))
        await withTaskGroup(of: Void.self) { group in
            for x in minTileX...max(minTileX, maxTileX) {
                for y in max(0, minTileY)...max(0, max(minTileY, maxTileY)) {
                    group.addTask { _ = await self.tile(z: viewport.zoom, x: x, y: y) }
                }
            }
        }
    }
}
