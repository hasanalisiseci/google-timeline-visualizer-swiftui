import Foundation

/// Web Mercator projection + journey geometry helpers. Ported 1:1 from the web visualizer's geo.ts.
enum Geo {
    static func project(latitude: Double, longitude: Double) -> WorldPoint {
        let lat = max(-85.05112878, min(85.05112878, latitude))
        let sinLat = sin(lat * .pi / 180)
        return WorldPoint(
            x: (longitude + 180) / 360,
            y: max(0, min(1, 0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * .pi)))
        )
    }

    static func unwrapWorldPoints(_ points: [WorldPoint]) -> [WorldPoint] {
        guard !points.isEmpty else { return [] }
        var output = [points[0]]
        for index in 1..<points.count {
            var x = points[index].x
            let previousX = output[index - 1].x
            while x - previousX > 0.5 { x -= 1 }
            while x - previousX < -0.5 { x += 1 }
            output.append(WorldPoint(x: x, y: points[index].y))
        }
        return output
    }

    private static func wrapNear(_ value: Double, _ reference: Double) -> Double {
        value - floor(value - reference + 0.5)
    }

    static func overviewRouteSegments(_ points: [WorldPoint]) -> [[WorldPoint]] {
        guard !points.isEmpty else { return [] }
        let referenceX = points.last?.x ?? 0.5
        let lowerEdge = referenceX - 0.5
        let upperEdge = referenceX + 0.5
        let wrapped = points.map { WorldPoint(x: wrapNear($0.x, referenceX), y: $0.y) }
        var segments: [[WorldPoint]] = [[wrapped[0]]]
        for index in 1..<wrapped.count {
            let previous = wrapped[index - 1]
            let current = wrapped[index]
            let delta = current.x - previous.x
            if abs(delta) <= 0.5 {
                segments[segments.count - 1].append(current)
                continue
            }
            let crossingRight = delta < -0.5
            let adjustedCurrentX = current.x + (crossingRight ? 1 : -1)
            let exitX = crossingRight ? upperEdge : lowerEdge
            let enterX = crossingRight ? lowerEdge : upperEdge
            let fraction = (exitX - previous.x) / (adjustedCurrentX - previous.x)
            let crossingY = previous.y + (current.y - previous.y) * fraction
            segments[segments.count - 1].append(WorldPoint(x: exitX, y: crossingY))
            segments.append([WorldPoint(x: enterX, y: crossingY), current])
        }
        return segments
    }

    static func worldBounds(_ points: [WorldPoint]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return (minX, maxX, minY, maxY)
    }

    static func viewportFor(_ points: [WorldPoint], size: Double) -> Viewport {
        let bounds = worldBounds(points)
        let centerX = (bounds.minX + bounds.maxX) / 2
        let centerY = (bounds.minY + bounds.maxY) / 2
        let span = max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY, 0.002) * 1.28
        let zoom = Int(max(2, min(15, floor(log2(size / (256 * span))))))
        return Viewport(
            minX: centerX - span / 2, maxX: centerX + span / 2,
            minY: max(0, centerY - span / 2), maxY: min(1, centerY + span / 2),
            zoom: zoom
        )
    }

    static func haversineKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        return 6371.0088 * 2 * asin(min(1, sqrt(h)))
    }

    static func cumulativeDistances(_ points: [GeoPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var distances = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            distances[index] = distances[index - 1] + haversineKm(points[index - 1], points[index])
        }
        return distances
    }
}
