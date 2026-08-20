import UIKit

/// Draws one frame of a journey animation: basemap tiles, travelled path, head marker, and a
/// title/date label. Mirrors drawFrame() in the web visualizer's renderer.ts, using Core Graphics
/// instead of Canvas2D.
enum FrameRenderer {
    struct Options {
        var title: String
        var periodLabel: String
        var distanceUnit: DistanceUnit = .kilometers
        var cityWaypoints: [CityLookup.Waypoint] = []
    }

    private static func worldToCanvas(_ point: WorldPoint, viewport: Viewport, size: Double) -> CGPoint {
        let spanX = viewport.maxX - viewport.minX
        let spanY = viewport.maxY - viewport.minY
        return CGPoint(
            x: (point.x - viewport.minX) / spanX * size,
            y: (point.y - viewport.minY) / spanY * size
        )
    }

    static func requiredTiles(viewport: Viewport) -> [(z: Int, x: Int, y: Int)] {
        let n = 1 << max(0, viewport.zoom)
        let minTileX = Int(floor(viewport.minX * Double(n)))
        let maxTileX = Int(floor(viewport.maxX * Double(n)))
        let minTileY = max(0, Int(floor(viewport.minY * Double(n))))
        let maxTileY = min(n - 1, Int(floor(viewport.maxY * Double(n))))
        guard maxTileY >= minTileY else { return [] }
        var tiles: [(Int, Int, Int)] = []
        for x in minTileX...maxTileX {
            for y in minTileY...maxTileY { tiles.append((viewport.zoom, x, y)) }
        }
        return tiles
    }

    /// Renders a frame at `progress` (0...1 across the whole animation incl. outro) into a bitmap.
    /// `journeyDurationSeconds` must be the same speed-adjusted value the caller used to size the
    /// overall frame count, or the journey/outro split here will drift out of sync with it.
    static func render(journey: PreparedJourney, progress: Double, journeyDurationSeconds: Double, size: Double, options: Options, tiles: [String: UIImage]) async -> UIImage {
        let timelineFrame = JourneyAnimation.frame(atOverallProgress: progress, journeyDurationSeconds: journeyDurationSeconds)

        let liveViewport = Camera.viewport(at: journey.cameraTrack, progress: timelineFrame.journeyProgress)
        let outroEase = JourneyAnimation.easeOutCubic(timelineFrame.outroProgress)
        let viewport = outroEase > 0 ? Camera.blendViewport(liveViewport, journey.overviewViewport, outroEase, size) : liveViewport

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))

            let n = Double(1 << max(0, viewport.zoom))
            for (z, x, y) in requiredTiles(viewport: viewport) {
                let wrappedX = ((x % Int(n)) + Int(n)) % Int(n)
                guard let image = tiles["\(z)/\(wrappedX)/\(y)"] else { continue }
                let tileWorldSize = 1 / n
                let originWorld = WorldPoint(x: Double(x) * tileWorldSize, y: Double(y) * tileWorldSize)
                let topLeft = worldToCanvas(originWorld, viewport: viewport, size: size)
                let bottomRight = worldToCanvas(WorldPoint(x: originWorld.x + tileWorldSize, y: originWorld.y + tileWorldSize), viewport: viewport, size: size)
                image.draw(in: CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
            }

            let travelledDistanceKm = journey.totalDistanceKm * timelineFrame.journeyProgress
            drawPath(cg, journey: journey, viewport: viewport, size: size, travelledDistanceKm: travelledDistanceKm)
            if timelineFrame.outroProgress < 1 {
                drawMarker(cg, journey: journey, viewport: viewport, size: size, journeyProgress: timelineFrame.journeyProgress, alpha: 1 - outroEase)
            }
            drawLabel(cg, size: size, options: options, alpha: 1 - CGFloat(outroEase) * 0.4)
            if !options.cityWaypoints.isEmpty {
                let currentCity = options.cityWaypoints.last(where: { $0.distanceKm <= travelledDistanceKm })?.city
                    ?? options.cityWaypoints.first?.city ?? ""
                // Fade in quickly at the start, then stay on screen through the outro — the
                // distance travelled is the payoff, it shouldn't vanish right when the video ends.
                let statsAlpha = min(1, CGFloat(timelineFrame.journeyProgress) * 12)
                drawStats(cg, size: size, city: currentCity, travelledKm: travelledDistanceKm, unit: options.distanceUnit, alpha: statsAlpha)
            }
        }
    }

    private static func canvasPoints(_ points: [WorldPoint], viewport: Viewport, size: Double) -> [CGPoint] {
        points.map { worldToCanvas($0, viewport: viewport, size: size) }
    }

    private static func drawPath(_ cg: CGContext, journey: PreparedJourney, viewport: Viewport, size: Double, travelledDistanceKm: Double) {
        guard journey.worldPoints.count > 1 else { return }
        cg.saveGState()
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        // Full route, faint.
        cg.setStrokeColor(UIColor(red: 0.93, green: 0.25, blue: 0.55, alpha: 0.35).cgColor)
        cg.setLineWidth(max(2, size / 220))
        for segment in journey.overviewRouteSegments where segment.count > 1 {
            let pts = canvasPoints(segment, viewport: viewport, size: size)
            cg.addLines(between: pts)
        }
        cg.strokePath()

        // Travelled portion, bright.
        let travelledDistance = travelledDistanceKm
        var travelled: [WorldPoint] = []
        for (index, distance) in journey.cumulativeDistanceKm.enumerated() {
            if distance <= travelledDistance {
                travelled.append(journey.worldPoints[index])
            } else {
                if let last = travelled.last, index > 0 {
                    let previousDistance = journey.cumulativeDistanceKm[index - 1]
                    let span = distance - previousDistance
                    let fraction = span > 0 ? (travelledDistance - previousDistance) / span : 0
                    let previous = journey.worldPoints[index - 1]
                    let point = journey.worldPoints[index]
                    travelled.append(WorldPoint(x: previous.x + (point.x - previous.x) * fraction, y: previous.y + (point.y - previous.y) * fraction))
                    _ = last
                }
                break
            }
        }
        if travelled.count > 1 {
            cg.setStrokeColor(UIColor(red: 0.98, green: 0.16, blue: 0.47, alpha: 0.95).cgColor)
            cg.setLineWidth(max(3, size / 150))
            let pts = canvasPoints(travelled, viewport: viewport, size: size)
            cg.addLines(between: pts)
            cg.strokePath()
        }
        cg.restoreGState()
    }

    private static func drawMarker(_ cg: CGContext, journey: PreparedJourney, viewport: Viewport, size: Double, journeyProgress: Double, alpha: Double) {
        let cameraJourney = Camera.Journey(worldPoints: journey.worldPoints, cumulativeDistanceKm: journey.cumulativeDistanceKm, totalDistanceKm: journey.totalDistanceKm)
        let position = worldPosition(cameraJourney, progress: journeyProgress)
        let point = worldToCanvas(position, viewport: viewport, size: size)
        let radius = max(6, size / 60)
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.setShadow(offset: .zero, blur: radius, color: UIColor(red: 0.98, green: 0.16, blue: 0.47, alpha: 0.6).cgColor)
        cg.setFillColor(UIColor.white.cgColor)
        cg.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        cg.fillPath()
        cg.setFillColor(UIColor(red: 0.98, green: 0.16, blue: 0.47, alpha: 1).cgColor)
        cg.addEllipse(in: CGRect(x: point.x - radius * 0.55, y: point.y - radius * 0.55, width: radius * 1.1, height: radius * 1.1))
        cg.fillPath()
        cg.restoreGState()
    }

    private static func worldPosition(_ journey: Camera.Journey, progress: Double) -> WorldPoint {
        // Re-derive the marker world position the same way Camera does internally.
        guard !journey.worldPoints.isEmpty else { return WorldPoint(x: 0.5, y: 0.5) }
        if journey.worldPoints.count == 1 || journey.totalDistanceKm <= 0 { return journey.worldPoints[0] }
        let target = max(0, min(journey.totalDistanceKm, journey.totalDistanceKm * max(0, min(1, progress))))
        var to = 1
        for (index, distance) in journey.cumulativeDistanceKm.enumerated() where distance >= target { to = max(1, index); break }
        if journey.cumulativeDistanceKm.last ?? 0 < target { to = journey.worldPoints.count - 1 }
        let from = to - 1
        let segmentDistance = journey.cumulativeDistanceKm[to] - journey.cumulativeDistanceKm[from]
        let fraction = segmentDistance <= 0 ? 0 : max(0, min(1, (target - journey.cumulativeDistanceKm[from]) / segmentDistance))
        let a = journey.worldPoints[from], b = journey.worldPoints[to]
        return WorldPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    /// A translucent dark "glass" chip — the shared look for every on-video caption.
    private static func drawChip(_ cg: CGContext, rect: CGRect, size: Double) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.26)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: size * 0.006), blur: size * 0.024, color: UIColor.black.withAlphaComponent(0.35).cgColor)
        UIColor.black.withAlphaComponent(0.5).setFill()
        path.fill()
        cg.restoreGState()
    }

    private static func icon(_ name: String, tint: UIColor, size: CGFloat) -> UIImage? {
        let configured = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        return configured?.withTintColor(tint, renderingMode: .alwaysOriginal)
    }

    private static func drawLabel(_ cg: CGContext, size: Double, options: Options, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        UIGraphicsPushContext(cg)
        cg.saveGState()
        cg.setAlpha(alpha)
        let padding = size * 0.05
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.05, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.026, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.72),
        ]
        let title = NSAttributedString(string: options.title, attributes: titleAttrs)
        let subtitle = NSAttributedString(string: options.periodLabel, attributes: subtitleAttrs)
        let boxWidth = max(title.size().width, subtitle.size().width) + padding * 2
        let boxHeight = title.size().height + subtitle.size().height + padding * 1.9
        let boxRect = CGRect(x: padding * 0.6, y: padding * 0.6, width: boxWidth, height: boxHeight)
        drawChip(cg, rect: boxRect, size: size)
        title.draw(at: CGPoint(x: boxRect.minX + padding, y: boxRect.minY + padding * 0.65))
        subtitle.draw(at: CGPoint(x: boxRect.minX + padding, y: boxRect.minY + padding * 0.65 + title.size().height + 3))
        cg.restoreGState()
        UIGraphicsPopContext()
    }

    private static func drawStats(_ cg: CGContext, size: Double, city: String, travelledKm: Double, unit: DistanceUnit, alpha: CGFloat) {
        guard alpha > 0.01, !city.isEmpty else { return }
        UIGraphicsPushContext(cg)
        cg.saveGState()
        cg.setAlpha(alpha)
        let accent = UIColor(red: 1, green: 0.34, blue: 0.6, alpha: 1)
        let padding = size * 0.038
        let iconSize = size * 0.026
        let iconColumnWidth = iconSize + padding * 0.6

        let cityAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.036, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let distanceAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size * 0.026, weight: .semibold),
            .foregroundColor: accent,
        ]
        let cityText = NSAttributedString(string: city, attributes: cityAttrs)
        let distanceText = NSAttributedString(string: String(format: "%.1f %@ travelled", unit.convert(fromKm: travelledKm), unit.label), attributes: distanceAttrs)

        let boxWidth = iconColumnWidth + max(cityText.size().width, distanceText.size().width) + padding * 1.7
        let boxHeight = cityText.size().height + distanceText.size().height + padding * 1.7
        let boxRect = CGRect(x: padding * 0.7, y: size - boxHeight - padding * 0.7, width: boxWidth, height: boxHeight)
        drawChip(cg, rect: boxRect, size: size)

        let textX = boxRect.minX + padding * 0.9 + iconColumnWidth
        if let pin = icon("mappin.circle.fill", tint: .white, size: iconSize) {
            pin.draw(in: CGRect(x: boxRect.minX + padding * 0.9, y: boxRect.minY + padding * 0.65, width: iconSize, height: iconSize))
        }
        cityText.draw(at: CGPoint(x: textX, y: boxRect.minY + padding * 0.5))
        if let route = icon("point.topleft.down.curvedto.point.bottomright.up.fill", tint: accent, size: iconSize * 0.85) {
            route.draw(in: CGRect(x: boxRect.minX + padding * 0.9, y: boxRect.minY + padding * 0.5 + cityText.size().height + 5, width: iconSize * 0.85, height: iconSize * 0.85))
        }
        distanceText.draw(at: CGPoint(x: textX, y: boxRect.minY + padding * 0.4 + cityText.size().height + 4))
        cg.restoreGState()
        UIGraphicsPopContext()
    }
}
