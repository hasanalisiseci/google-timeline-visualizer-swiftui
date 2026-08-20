import Foundation

/// Builds a `PreparedJourney` from raw points: projects to world space, unwraps antimeridian
/// crossings, and derives the camera track. Mirrors `prepareJourney` in the web renderer.
enum Journey {
    static func prepare(points: [GeoPoint], size: Double, cameraMovement: CameraMovement) -> PreparedJourney? {
        guard !points.isEmpty else { return nil }
        let projected = points.map { Geo.project(latitude: $0.latitude, longitude: $0.longitude) }
        let worldPoints = Geo.unwrapWorldPoints(projected)
        let cumulative = Geo.cumulativeDistances(points)
        let totalDistanceKm = cumulative.last ?? 0
        let cameraJourney = Camera.Journey(worldPoints: worldPoints, cumulativeDistanceKm: cumulative, totalDistanceKm: totalDistanceKm)
        let cameraTrack = Camera.buildCameraTrack(cameraJourney, size: size, movement: cameraMovement)
        let overviewViewport = Camera.overviewViewport(cameraJourney, size: size)
        return PreparedJourney(
            points: points,
            worldPoints: worldPoints,
            overviewRouteSegments: Geo.overviewRouteSegments(worldPoints),
            cumulativeDistanceKm: cumulative,
            totalDistanceKm: totalDistanceKm,
            cameraTrack: cameraTrack,
            overviewViewport: overviewViewport
        )
    }

    /// Suggested journey playback duration: proportional to distance, clamped to a sane range,
    /// then scaled by the user's chosen speed.
    static func suggestedDurationSeconds(totalDistanceKm: Double, speed: VideoSpeed = .normal) -> Double {
        max(6, min(40, 6 + totalDistanceKm / 400)) * speed.durationMultiplier
    }
}
