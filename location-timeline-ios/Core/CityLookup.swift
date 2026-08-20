import CoreLocation

/// Reverse-geocodes a sparse set of waypoints along a journey so the video can caption "which city
/// am I in right now" as it plays. ponytail: sequential CLGeocoder calls capped at ~25 stops —
/// CLGeocoder only allows one in-flight request per instance and is rate-limited, so this stays
/// cheap and safe; a bigger journey just samples less densely instead of calling more.
enum CityLookup {
    struct Waypoint {
        var distanceKm: Double
        var city: String
    }

    static func waypoints(for journey: PreparedJourney, progress: @escaping (Double) -> Void) async -> [Waypoint] {
        guard !journey.points.isEmpty else { return [] }
        let minGapKm = max(20, journey.totalDistanceKm / 24)
        var indices = [0]
        var lastDistance = journey.cumulativeDistanceKm[0]
        for index in 1..<journey.points.count {
            let distance = journey.cumulativeDistanceKm[index]
            if distance - lastDistance >= minGapKm {
                indices.append(index)
                lastDistance = distance
            }
        }
        if indices.last != journey.points.count - 1 { indices.append(journey.points.count - 1) }

        let geocoder = CLGeocoder()
        var results: [Waypoint] = []
        for (step, index) in indices.enumerated() {
            let point = journey.points[index]
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                let city = placemark.locality ?? placemark.administrativeArea ?? placemark.country ?? "—"
                results.append(Waypoint(distanceKm: journey.cumulativeDistanceKm[index], city: city))
            }
            progress(Double(step + 1) / Double(indices.count))
        }
        let collapsed = results.reduce(into: [Waypoint]()) { collapsed, waypoint in
            if collapsed.last?.city != waypoint.city { collapsed.append(waypoint) }
        }
        return collapsed.isEmpty ? results : collapsed
    }
}
