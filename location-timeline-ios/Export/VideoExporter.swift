import AVFoundation
import UIKit

enum VideoQuality: String, CaseIterable, Identifiable {
    case p480, p720, p1080
    var id: String { rawValue }
    var pixelSize: Int {
        switch self {
        case .p480: return 480
        case .p720: return 720
        case .p1080: return 1080
        }
    }
    var label: String { "\(pixelSize)p" }
}

struct VideoExportRequest {
    var journey: PreparedJourney
    var title: String
    var periodLabel: String
    var quality: VideoQuality
    var cameraMovement: CameraMovement
    var speed: VideoSpeed = .normal
    var fps: Int32 = 30
}

enum VideoExportError: Error {
    case writerSetup
    case writerFailed(Error?)
}

/// Renders a journey to an MP4 by drawing each frame with `FrameRenderer` and appending it to an
/// `AVAssetWriter` pixel buffer stream — no server, no external encoder.
enum VideoExporter {
    /// Fraction of the overall progress bar spent loading map tiles before any frame is rendered.
    private static let tileLoadWeight = 0.2

    static func export(_ request: VideoExportRequest, cities: [CityLookup.Waypoint] = [], progress: @escaping (Double) -> Void) async throws -> URL {
        let size = Double(request.quality.pixelSize)
        let journeyDurationSeconds = Journey.suggestedDurationSeconds(totalDistanceKm: request.journey.totalDistanceKm, speed: request.speed)
        let totalSeconds = JourneyAnimation.totalDurationSeconds(journeyDurationSeconds)
        let frameCount = max(1, Int(totalSeconds * Double(request.fps)))

        // Preload every tile the whole track will need.
        var neededTiles: [(z: Int, x: Int, y: Int)] = []
        for frameIndex in 0...frameCount {
            let p = Double(frameIndex) / Double(frameCount)
            let tf = JourneyAnimation.frame(atOverallProgress: p, journeyDurationSeconds: journeyDurationSeconds)
            let live = Camera.viewport(at: request.journey.cameraTrack, progress: tf.journeyProgress)
            let outroEase = JourneyAnimation.easeOutCubic(tf.outroProgress)
            let vp = outroEase > 0 ? Camera.blendViewport(live, request.journey.overviewViewport, outroEase, size) : live
            neededTiles.append(contentsOf: FrameRenderer.requiredTiles(viewport: vp))
        }
        var tileImages: [String: UIImage] = [:]
        var seen = Set<String>()
        for t in neededTiles {
            let n = 1 << max(0, t.z)
            let wrappedX = ((t.x % n) + n) % n
            let key = "\(t.z)/\(wrappedX)/\(t.y)"
            if seen.contains(key) { continue }
            seen.insert(key)
        }
        let totalTileCount = max(1, seen.count)
        var loadedTileCount = 0
        progress(0)
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for key in seen {
                let parts = key.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 3 else { continue }
                group.addTask {
                    let image = await TileCache.shared.tile(z: parts[0], x: parts[1], y: parts[2])
                    return (key, image)
                }
            }
            for await (key, image) in group {
                if let image { tileImages[key] = image }
                loadedTileCount += 1
                progress(tileLoadWeight * Double(loadedTileCount) / Double(totalTileCount))
                await Task.yield()
            }
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { throw VideoExportError.writerSetup }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: request.quality.pixelSize,
            AVVideoHeightKey: request.quality.pixelSize,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: request.quality.pixelSize,
            kCVPixelBufferHeightKey as String: request.quality.pixelSize,
        ])
        guard writer.canAdd(input) else { throw VideoExportError.writerSetup }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let options = FrameRenderer.Options(title: request.title, periodLabel: request.periodLabel, cityWaypoints: cities)
        for frameIndex in 0...frameCount {
            let p = Double(frameIndex) / Double(frameCount)
            let image = await FrameRenderer.render(journey: request.journey, progress: p, journeyDurationSeconds: journeyDurationSeconds, size: size, options: options, tiles: tileImages)
            guard let buffer = pixelBuffer(from: image, size: request.quality.pixelSize) else { continue }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: request.fps)
            adaptor.append(buffer, withPresentationTime: time)
            progress(tileLoadWeight + (1 - tileLoadWeight) * Double(frameIndex) / Double(frameCount))
            await Task.yield()
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoExportError.writerFailed(writer.error) }
        progress(1)
        return outputURL
    }

    private static func pixelBuffer(from image: UIImage, size: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ), let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        return buffer
    }
}
