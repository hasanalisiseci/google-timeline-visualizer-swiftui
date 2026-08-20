import Foundation

/// Camera framing for a journey: which part of the world is visible each moment, with dead-zone
/// panning and smoothed zoom. Ported 1:1 from the web visualizer's camera.ts.
enum Camera {
    private struct MovementProfile {
        var contextFraction: Double
        var minimumContextKm: Double
        var maximumContextKm: Double
        var padding: Double
        var minimumViewportSpan: Double
        var zoomOutAlpha: Double
        var zoomInAlpha: Double
        var legAware: Bool
        var fixedZoom: Bool
    }

    private static let profiles: [CameraMovement: MovementProfile] = [
        .fixed: MovementProfile(contextFraction: 0.10, minimumContextKm: 25, maximumContextKm: 350, padding: 2.6, minimumViewportSpan: 0.00060, zoomOutAlpha: 0, zoomInAlpha: 0, legAware: false, fixedZoom: true),
        .steady: MovementProfile(contextFraction: 1, minimumContextKm: 650, maximumContextKm: 650, padding: 2.8, minimumViewportSpan: 0.00060, zoomOutAlpha: 0.14, zoomInAlpha: 0.035, legAware: false, fixedZoom: false),
        .dynamic: MovementProfile(contextFraction: 0.10, minimumContextKm: 100, maximumContextKm: 350, padding: 2.2, minimumViewportSpan: 0.00045, zoomOutAlpha: 0.24, zoomInAlpha: 0.06, legAware: true, fixedZoom: false),
    ]

    private static let trackSamples = 480
    private static let deadZoneHalf = 0.20
    private static let fixedZoomPercentile = 0.80
    private static let tileZoomHysteresis = 0.15
    private static let minTileZoom = 2.0
    private static let maxTileZoom = 15.0
    private static let maxViewportSpan = 0.72
    private static let maxOverviewViewportSpan = 1.25
    private static let minOverviewViewportSpan = 0.00045
    private static let overviewPadding = 1.22
    private static let overviewSideInset = 34.0
    private static let overviewHeaderBottom = 132.0
    private static let overviewHeaderGap = 20.0
    private static let overviewBottomInset = 34.0
    private static let transferPadding = 2.8

    struct Journey {
        var worldPoints: [WorldPoint]
        var cumulativeDistanceKm: [Double]
        var totalDistanceKm: Double
    }

    private struct WorldPosition {
        var point: WorldPoint
        var distanceKm: Double
        var fromIndex: Int
        var toIndex: Int
    }

    private struct Leg {
        var startKm: Double
        var endKm: Double
        var isTransfer: Bool
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, value)) }

    private static func lowerBound(_ values: [Double], _ target: Double) -> Int {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < target { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func upperBound(_ values: [Double], _ target: Double) -> Int {
        var low = 0, high = values.count
        while low < high {
            let mid = (low + high) / 2
            if values[mid] <= target { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func transferThreshold(_ cumulativeDistanceKm: [Double]) -> Double {
        guard cumulativeDistanceKm.count > 1 else { return 120 }
        var ordinary: [Double] = []
        for i in 1..<cumulativeDistanceKm.count {
            let d = cumulativeDistanceKm[i] - cumulativeDistanceKm[i - 1]
            if d > 0 && d < 120 { ordinary.append(d) }
        }
        ordinary.sort()
        if ordinary.isEmpty { return 120 }
        let typical = median(ordinary)
        let deviation = median(ordinary.map { abs($0 - typical) }.sorted())
        return clamp(max(typical * 3, typical + deviation * 6), 60, 120)
    }

    private static func buildLegs(_ journey: Journey) -> [Leg] {
        guard journey.worldPoints.count >= 2, journey.totalDistanceKm > 0 else { return [] }
        let threshold = transferThreshold(journey.cumulativeDistanceKm)
        var legs: [Leg] = []
        var localStartKm = 0.0
        for index in 1..<journey.cumulativeDistanceKm.count {
            let startKm = journey.cumulativeDistanceKm[index - 1]
            let endKm = journey.cumulativeDistanceKm[index]
            if endKm - startKm < max(1, threshold) { continue }
            if startKm > localStartKm { legs.append(Leg(startKm: localStartKm, endKm: startKm, isTransfer: false)) }
            legs.append(Leg(startKm: startKm, endKm: endKm, isTransfer: true))
            localStartKm = endKm
        }
        if journey.totalDistanceKm > localStartKm {
            legs.append(Leg(startKm: localStartKm, endKm: journey.totalDistanceKm, isTransfer: false))
        }
        return legs
    }

    private static func legAt(_ legs: [Leg], _ distanceKm: Double, _ totalDistanceKm: Double) -> Leg {
        guard !legs.isEmpty else { return Leg(startKm: 0, endKm: totalDistanceKm, isTransfer: false) }
        let target = clamp(distanceKm, 0, totalDistanceKm)
        var selected = legs[0]
        for leg in legs {
            if leg.startKm > target { break }
            selected = leg
        }
        return selected
    }

    private static func worldPositionAtDistance(_ journey: Journey, _ distanceKm: Double) -> WorldPosition {
        if journey.worldPoints.isEmpty {
            return WorldPosition(point: WorldPoint(x: 0.5, y: 0.5), distanceKm: 0, fromIndex: 0, toIndex: 0)
        }
        if journey.worldPoints.count == 1 || journey.totalDistanceKm <= 0 {
            return WorldPosition(point: journey.worldPoints[0], distanceKm: 0, fromIndex: 0, toIndex: 0)
        }
        let target = clamp(distanceKm, 0, journey.totalDistanceKm)
        let to = Int(clamp(Double(lowerBound(journey.cumulativeDistanceKm, target)), 1, Double(journey.worldPoints.count - 1)))
        let from = to - 1
        let segmentDistance = journey.cumulativeDistanceKm[to] - journey.cumulativeDistanceKm[from]
        let fraction = segmentDistance <= 0 ? 0 : clamp((target - journey.cumulativeDistanceKm[from]) / segmentDistance, 0, 1)
        return WorldPosition(
            point: WorldPoint(
                x: journey.worldPoints[from].x + (journey.worldPoints[to].x - journey.worldPoints[from].x) * fraction,
                y: journey.worldPoints[from].y + (journey.worldPoints[to].y - journey.worldPoints[from].y) * fraction
            ),
            distanceKm: target, fromIndex: from, toIndex: to
        )
    }

    private static func worldPositionAtProgress(_ journey: Journey, _ progress: Double) -> WorldPosition {
        worldPositionAtDistance(journey, journey.totalDistanceKm * clamp(progress, 0, 1))
    }

    private static func unwrapNear(_ value: Double, _ reference: Double) -> Double {
        var result = value
        while result - reference > 0.5 { result -= 1 }
        while result - reference < -0.5 { result += 1 }
        return result
    }

    private static func clampCenterY(_ centerY: Double, _ spanY: Double) -> Double {
        let half = spanY / 2
        return half >= 0.5 ? 0.5 : clamp(centerY, half, 1 - half)
    }

    private static func tileZoom(_ size: Double, _ aspect: Double, _ spanY: Double) -> Int {
        Int(clamp(floor(log2(max(1, size) / (256 * spanY * aspect))), minTileZoom, maxTileZoom))
    }

    struct SafeArea { var left: Double; var top: Double; var right: Double; var bottom: Double }

    static func overviewSafeArea(_ size: Double) -> SafeArea {
        let scale = size / 720
        return SafeArea(
            left: overviewSideInset * scale,
            top: (overviewHeaderBottom + overviewHeaderGap) * scale,
            right: size - overviewSideInset * scale,
            bottom: size - overviewBottomInset * scale
        )
    }

    static func overviewViewport(_ journey: Journey, size: Double) -> Viewport {
        let bounds = Geo.worldBounds(journey.worldPoints)
        let contentCenterX = (bounds.minX + bounds.maxX) / 2
        let contentCenterY = (bounds.minY + bounds.maxY) / 2
        let contentSpanX = max(bounds.maxX - bounds.minX, minOverviewViewportSpan)
        let contentSpanY = max(bounds.maxY - bounds.minY, minOverviewViewportSpan)
        let safe = overviewSafeArea(size)
        let safeWidth = max(1, safe.right - safe.left)
        let safeHeight = max(1, safe.bottom - safe.top)
        let worldPerPixel = max(contentSpanX / safeWidth, contentSpanY / safeHeight) * overviewPadding
        let spanX = max(worldPerPixel * size, minOverviewViewportSpan)
        let spanY = clamp(worldPerPixel * size, minOverviewViewportSpan, maxOverviewViewportSpan)
        let viewportMinX = contentCenterX - ((safe.left + safe.right) / 2) * worldPerPixel
        var viewportMinY = contentCenterY - ((safe.top + safe.bottom) / 2) * worldPerPixel
        if spanY <= 1 { viewportMinY = clamp(viewportMinY, 0, 1 - spanY) }
        return Viewport(
            minX: viewportMinX, maxX: viewportMinX + spanX,
            minY: viewportMinY, maxY: viewportMinY + spanY,
            zoom: Int(clamp(floor(log2(max(1, size) / (256 * spanX))), minTileZoom, maxTileZoom))
        )
    }

    static func blendViewport(_ from: Viewport, _ to: Viewport, _ fraction: Double, _ size: Double) -> Viewport {
        let amount = clamp(fraction, 0, 1)
        let fromCenterX = (from.minX + from.maxX) / 2
        let toCenterX = unwrapNear((to.minX + to.maxX) / 2, fromCenterX)
        let centerX = fromCenterX + (toCenterX - fromCenterX) * amount
        let centerY = (from.minY + from.maxY) / 2 + ((to.minY + to.maxY) / 2 - (from.minY + from.maxY) / 2) * amount
        let fromSpanY = max(from.maxY - from.minY, minOverviewViewportSpan)
        let toSpanY = max(to.maxY - to.minY, minOverviewViewportSpan)
        let spanY = clamp(exp(log(fromSpanY) + (log(toSpanY) - log(fromSpanY)) * amount), minOverviewViewportSpan, maxOverviewViewportSpan)
        let adjustedCenterY = clampCenterY(centerY, spanY)
        return Viewport(
            minX: centerX - spanY / 2, maxX: centerX + spanY / 2,
            minY: adjustedCenterY - spanY / 2, maxY: adjustedCenterY + spanY / 2,
            zoom: Int(clamp(floor(log2(max(1, size) / (256 * spanY))), minTileZoom, maxTileZoom))
        )
    }

    private static func stabilizedTileZoom(_ previous: Int, _ continuous: Double) -> Int {
        var zoom = Double(previous)
        while zoom < maxTileZoom && continuous >= zoom + 1 + tileZoomHysteresis { zoom += 1 }
        while zoom > minTileZoom && continuous < zoom - tileZoomHysteresis { zoom -= 1 }
        return Int(clamp(zoom, minTileZoom, maxTileZoom))
    }

    private static func rawViewport(_ journey: Journey, _ progress: Double, _ size: Double, _ movement: MovementProfile, _ legs: [Leg]) -> Viewport {
        let current = worldPositionAtProgress(journey, progress)
        let proportionalContextKm = clamp(journey.totalDistanceKm * movement.contextFraction, movement.minimumContextKm, movement.maximumContextKm)
        let leg = movement.legAware ? legAt(legs, current.distanceKm, journey.totalDistanceKm) : nil
        // Ordinary (non-transfer) legs are local driving/walking within one area — zoom to that
        // area's own extent instead of the whole-trip context, so a city stop reads as a city, not
        // a dot on a country-wide view.
        let contextKm: Double
        let lookaheadLimitKm: Double
        if let leg {
            if leg.isTransfer {
                contextKm = leg.endKm - leg.startKm
            } else {
                let legSpanKm = leg.endKm - leg.startKm
                contextKm = clamp(max(legSpanKm, 5) * 1.4, 5, movement.maximumContextKm)
            }
            lookaheadLimitKm = leg.endKm
        } else {
            contextKm = proportionalContextKm
            lookaheadLimitKm = journey.totalDistanceKm
        }
        let padding = leg?.isTransfer == true ? transferPadding : movement.padding
        let rangeStartKm = leg?.startKm ?? 0
        let tailDistance = max(rangeStartKm, current.distanceKm - contextKm)
        let lookaheadDistance = min(lookaheadLimitKm, current.distanceKm + contextKm)
        var focus = [worldPositionAtDistance(journey, tailDistance).point]
        let startIndex = lowerBound(journey.cumulativeDistanceKm, tailDistance)
        let endIndex = upperBound(journey.cumulativeDistanceKm, lookaheadDistance)
        if startIndex < endIndex {
            for index in startIndex..<endIndex where index >= 0 && index < journey.worldPoints.count {
                focus.append(journey.worldPoints[index])
            }
        }
        focus.append(current.point)
        focus.append(worldPositionAtDistance(journey, lookaheadDistance).point)

        let centerX = current.point.x
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for point in focus {
            let x = unwrapNear(point.x, centerX)
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let contentSpanX = max(0.00015, maxX - minX)
        let contentSpanY = max(0.00015, maxY - minY)
        let aspect = 1.0
        let spanY = clamp(max(contentSpanY * padding, contentSpanX * padding / aspect), movement.minimumViewportSpan, maxViewportSpan)
        let adjustedCenterY = clampCenterY(current.point.y, spanY)
        return Viewport(
            minX: centerX - spanY * aspect / 2, maxX: centerX + spanY * aspect / 2,
            minY: adjustedCenterY - spanY / 2, maxY: adjustedCenterY + spanY / 2,
            zoom: tileZoom(size, aspect, spanY)
        )
    }

    private static func frameToViewport(_ frame: CameraFrame, _ aspect: Double) -> Viewport {
        let halfY = frame.spanY / 2
        let halfX = frame.spanY * aspect / 2
        return Viewport(
            minX: frame.centerX - halfX, maxX: frame.centerX + halfX,
            minY: frame.centerY - halfY, maxY: frame.centerY + halfY,
            zoom: frame.zoom
        )
    }

    static func buildCameraTrack(_ journey: Journey, size: Double, movement cameraMovement: CameraMovement) -> CameraTrack {
        let aspect = 1.0
        let movement = profiles[cameraMovement]!
        let legs = buildLegs(journey)
        let rawSamples: [(viewport: Viewport, marker: WorldPoint)] = (0...trackSamples).map { sample in
            let progress = Double(sample) / Double(trackSamples)
            return (rawViewport(journey, progress, size, movement, legs), worldPositionAtProgress(journey, progress).point)
        }
        var fixedSpanY: Double? = nil
        if movement.fixedZoom {
            let sorted = rawSamples.map { $0.viewport.maxY - $0.viewport.minY }.sorted()
            let idx = min(sorted.count - 1, Int(Double(trackSamples) * fixedZoomPercentile))
            fixedSpanY = sorted[idx]
        }
        var frames: [CameraFrame] = []
        for sample in rawSamples {
            let raw = sample.viewport
            let rawCenterX = (raw.minX + raw.maxX) / 2
            let rawCenterY = (raw.minY + raw.maxY) / 2
            let rawSpanY = clamp(fixedSpanY ?? (raw.maxY - raw.minY), movement.minimumViewportSpan, maxViewportSpan)
            guard let previous = frames.last else {
                frames.append(CameraFrame(centerX: rawCenterX, centerY: clampCenterY(rawCenterY, rawSpanY), spanY: rawSpanY, zoom: tileZoom(size, aspect, rawSpanY)))
                continue
            }
            let zoomAlpha = rawSpanY > previous.spanY ? movement.zoomOutAlpha : movement.zoomInAlpha
            let spanY = movement.fixedZoom
                ? rawSpanY
                : clamp(exp(log(previous.spanY) + (log(rawSpanY) - log(previous.spanY)) * zoomAlpha), movement.minimumViewportSpan, maxViewportSpan)
            let spanX = spanY * aspect
            let markerX = unwrapNear(sample.marker.x, previous.centerX)
            var centerX = previous.centerX
            var centerY = previous.centerY
            let deadHalfX = spanX * deadZoneHalf
            let deadHalfY = spanY * deadZoneHalf
            if markerX < centerX - deadHalfX { centerX = markerX + deadHalfX }
            else if markerX > centerX + deadHalfX { centerX = markerX - deadHalfX }
            if sample.marker.y < centerY - deadHalfY { centerY = sample.marker.y + deadHalfY }
            else if sample.marker.y > centerY + deadHalfY { centerY = sample.marker.y - deadHalfY }
            centerY = clampCenterY(centerY, spanY)
            let continuousZoom = log2(max(1, size) / (256 * spanX))
            frames.append(CameraFrame(centerX: centerX, centerY: centerY, spanY: spanY, zoom: stabilizedTileZoom(previous.zoom, continuousZoom)))
        }
        return CameraTrack(frames: frames, aspect: aspect)
    }

    static func viewport(at track: CameraTrack, progress: Double) -> Viewport {
        if track.frames.count == 1 { return frameToViewport(track.frames[0], track.aspect) }
        let position = clamp(progress, 0, 1) * Double(track.frames.count - 1)
        let fromIndex = Int(clamp(floor(position), 0, Double(track.frames.count - 1)))
        let toIndex = min(fromIndex + 1, track.frames.count - 1)
        let fraction = position - Double(fromIndex)
        let from = track.frames[fromIndex]
        let to = track.frames[toIndex]
        return frameToViewport(CameraFrame(
            centerX: from.centerX + (to.centerX - from.centerX) * fraction,
            centerY: from.centerY + (to.centerY - from.centerY) * fraction,
            spanY: exp(log(from.spanY) + (log(to.spanY) - log(from.spanY)) * fraction),
            zoom: fraction < 0.5 ? from.zoom : to.zoom
        ), track.aspect)
    }
}
