import Foundation

struct GeoPoint {
    var instant: Date
    var latitude: Double
    var longitude: Double
    var recordedDate: String?
    var timeZoneMissing: Bool = false
}

struct WorldPoint {
    var x: Double
    var y: Double
}

struct Viewport {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    var zoom: Int
}

enum CameraMovement: String, CaseIterable, Identifiable {
    case fixed, steady, dynamic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Fixed"
        case .steady: return "Steady"
        case .dynamic: return "Dynamic"
        }
    }
}

struct CameraFrame {
    var centerX: Double
    var centerY: Double
    var spanY: Double
    var zoom: Int
}

struct CameraTrack {
    var frames: [CameraFrame]
    var aspect: Double
}

struct MonthOption: Identifiable, Hashable {
    var key: String
    var label: String
    var id: String { key }
}

struct TimelineFrame {
    var journeyProgress: Double
    var outroProgress: Double
}

/// Everything needed to render any frame of a journey without re-deriving it. Mirrors `PreparedJourney` from the web renderer.
struct PreparedJourney {
    var points: [GeoPoint]
    var worldPoints: [WorldPoint]
    var overviewRouteSegments: [[WorldPoint]]
    var cumulativeDistanceKm: [Double]
    var totalDistanceKm: Double
    var cameraTrack: CameraTrack
    var overviewViewport: Viewport
}

enum VideoSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
    /// Multiplier on the base suggested duration — >1 plays slower (longer video), <1 faster.
    var durationMultiplier: Double {
        switch self {
        case .slow: return 1.6
        case .normal: return 1.0
        case .fast: return 0.6
        }
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers, miles
    var id: String { rawValue }
    var label: String { self == .kilometers ? "km" : "mi" }
    func convert(fromKm km: Double) -> Double { self == .kilometers ? km : km * 0.621371 }
}
