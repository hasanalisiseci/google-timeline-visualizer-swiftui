import Foundation

enum TimelineParseReason {
    case malformedJson, legacyFormat, rawSignalsOnly, unsupportedFormat, noUsableLocations
}

struct TimelineParseError: Error {
    var reason: TimelineParseReason
    var message: String
}

/// Parses Google Timeline JSON exports (current `semanticSegments` format) into a flat,
/// chronologically ordered point list. Ported 1:1 from the web visualizer's timeline.ts.
enum TimelineParser {
    private static let segmentDirectionSignalMs: Double = 36 * 60 * 60 * 1000

    private struct ParsedInstant {
        var instant: Date
        var recordedDate: String?
        var timeZoneMissing: Bool
    }

    private struct TimeInterval {
        var start: Double
        var end: Double
    }

    private struct ParsedSegment {
        var anchor: Date?
        var points: [GeoPoint]
        var standalonePath: Bool
    }

    // MARK: coordinate parsing

    static func parseCoordinate(_ value: Any?) -> (Double, Double)? {
        if let dict = value as? [String: Any] {
            return parseCoordinate(dict["latLng"] ?? dict["point"])
        }
        guard let string = value as? String else { return nil }
        var cleaned = string.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("geo:") { cleaned.removeFirst(4) }
        if let questionIndex = cleaned.firstIndex(of: "?") { cleaned = String(cleaned[cleaned.startIndex..<questionIndex]) }
        cleaned = cleaned.replacingOccurrences(of: "°", with: "").replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2, var latitude = Double(parts[0]), var longitude = Double(parts[1]) else { return nil }
        if abs(latitude) > 1_000_000 || abs(longitude) > 1_000_000 {
            latitude /= 10_000_000
            longitude /= 10_000_000
        }
        guard latitude >= -85.05112878, latitude <= 85.05112878, longitude >= -180, longitude <= 180 else { return nil }
        return (latitude, longitude)
    }

    // MARK: instant parsing

    private static let timeZoneSuffix = try! NSRegularExpression(pattern: "(?:z|[+-]\\d{2}:?\\d{2})$", options: .caseInsensitive)
    private static let dateOnlyPrefix = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}")

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
    }

    private static func parseInstant(_ value: Any?) -> ParsedInstant? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let timeZoneMissing = !matches(timeZoneSuffix, raw)
        let candidate = timeZoneMissing ? raw + "Z" : raw
        let instant = isoWithFraction.date(from: candidate) ?? isoNoFraction.date(from: candidate)
        guard let instant else { return nil }
        let recordedDate = (timeZoneMissing && matches(dateOnlyPrefix, raw)) ? String(raw.prefix(10)) : nil
        return ParsedInstant(instant: instant, recordedDate: recordedDate, timeZoneMissing: timeZoneMissing)
    }

    private static func parseOffsetMinutes(_ value: Any?) -> Int? {
        if let number = value as? Int, number >= 0 { return number }
        if let number = value as? Double, number >= 0, number == number.rounded() { return Int(number) }
        if let string = value as? String, let number = Int(string), number >= 0 { return number }
        return nil
    }

    private static func parseOffsetInstant(_ startValue: Any?, _ endValue: Any?, _ offsetValue: Any?) -> Date? {
        guard let start = parseInstant(startValue), let offsetMinutes = parseOffsetMinutes(offsetValue) else { return nil }
        let instant = start.instant.addingTimeInterval(Double(offsetMinutes) * 60)
        if let end = parseInstant(endValue), !start.timeZoneMissing, !end.timeZoneMissing,
           instant.timeIntervalSince1970 > end.instant.timeIntervalSince1970 + 60 {
            return nil
        }
        return instant
    }

    @discardableResult
    private static func addPoint(_ output: inout [GeoPoint], _ time: Any?, _ coordinate: Any?) -> Bool {
        guard let parsedTime = parseInstant(time), let parsed = parseCoordinate(coordinate) else { return false }
        output.append(GeoPoint(instant: parsedTime.instant, latitude: parsed.0, longitude: parsed.1, recordedDate: parsedTime.recordedDate, timeZoneMissing: parsedTime.timeZoneMissing))
        return true
    }

    private static func semanticInterval(_ startValue: Any?, _ endValue: Any?) -> TimeInterval? {
        guard let start = parseInstant(startValue), let end = parseInstant(endValue), !start.timeZoneMissing, !end.timeZoneMissing else { return nil }
        let startMs = start.instant.timeIntervalSince1970 * 1000
        let endMs = end.instant.timeIntervalSince1970 * 1000
        return endMs >= startMs ? TimeInterval(start: startMs, end: endMs) : nil
    }

    private static func mergeIntervals(_ intervals: [TimeInterval]) -> [TimeInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [TimeInterval] = []
        for interval in sorted {
            if merged.isEmpty || interval.start > merged[merged.count - 1].end {
                merged.append(interval)
            } else if interval.end > merged[merged.count - 1].end {
                merged[merged.count - 1].end = interval.end
            }
        }
        return merged
    }

    private static func isCovered(_ point: GeoPoint, _ intervals: [TimeInterval]) -> Bool {
        if point.timeZoneMissing { return false }
        let timestamp = point.instant.timeIntervalSince1970 * 1000
        var low = 0, high = intervals.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let interval = intervals[mid]
            if timestamp < interval.start { high = mid - 1 }
            else if timestamp > interval.end { low = mid + 1 }
            else { return true }
        }
        return false
    }

    private static func normalizeSegmentDirection(_ segments: [ParsedSegment]) -> [ParsedSegment] {
        let anchors = segments.compactMap { $0.anchor?.timeIntervalSince1970 }
        var ascending = 0, descending = 0
        if anchors.count > 1 {
            for index in 1..<anchors.count {
                let delta = (anchors[index] - anchors[index - 1]) * 1000
                if abs(delta) < segmentDirectionSignalMs { continue }
                if delta > 0 { ascending += 1 } else { descending += 1 }
            }
        }
        if let first = anchors.first, let last = anchors.last {
            let endpointDelta = (last - first) * 1000
            if abs(endpointDelta) >= segmentDirectionSignalMs {
                if endpointDelta > 0 { ascending += 2 } else { descending += 2 }
            }
        }
        return descending > ascending ? segments.reversed() : segments
    }

    // MARK: top-level parse

    static func parseTimelineJson(_ data: Any) throws -> [GeoPoint] {
        let segments: [Any]
        if let array = data as? [Any] {
            segments = array
        } else if let dict = data as? [String: Any], let semantic = dict["semanticSegments"] as? [Any] {
            segments = semantic
        } else if let dict = data as? [String: Any], dict["timelineObjects"] != nil || dict["locations"] != nil {
            throw TimelineParseError(reason: .legacyFormat, message: "This is an older Google Takeout format. Export Timeline data from your phone instead.")
        } else if let dict = data as? [String: Any], dict["rawSignals"] != nil {
            throw TimelineParseError(reason: .rawSignalsOnly, message: "This export contains raw signals but no reconstructed Timeline journeys.")
        } else {
            throw TimelineParseError(reason: .unsupportedFormat, message: "Timeline JSON must be an array or contain semanticSegments.")
        }

        var parsedSegments: [ParsedSegment] = []
        var semanticIntervals: [TimeInterval] = []
        for rawSegment in segments {
            guard let segment = rawSegment as? [String: Any] else { continue }
            let startTime = segment["startTime"]
            let endTime = segment["endTime"]
            var segmentPoints: [GeoPoint] = []
            var semanticPointAdded = false
            let hasPath = (segment["timelinePath"] as? [Any]) != nil

            if let activity = segment["activity"] as? [String: Any] {
                if addPoint(&segmentPoints, startTime, activity["start"]) { semanticPointAdded = true }
            }
            if let visit = segment["visit"] as? [String: Any], let topCandidate = visit["topCandidate"] as? [String: Any] {
                if addPoint(&segmentPoints, startTime, topCandidate["placeLocation"]) { semanticPointAdded = true }
            }
            if let path = segment["timelinePath"] as? [Any] {
                for rawPathPoint in path {
                    guard let pathPoint = rawPathPoint as? [String: Any] else { continue }
                    let absolute = parseInstant(pathPoint["time"])
                    let offsetInstant = parseOffsetInstant(startTime, endTime, pathPoint["durationMinutesOffsetFromStartTime"])
                    guard let coordinate = parseCoordinate(pathPoint["point"]), let instant = absolute?.instant ?? offsetInstant else { continue }
                    let segmentStart = absolute == nil ? parseInstant(startTime) : nil
                    let recordedDate = absolute?.recordedDate ?? (segmentStart?.timeZoneMissing == true ? String(describing: instant) : nil)
                    segmentPoints.append(GeoPoint(
                        instant: instant, latitude: coordinate.0, longitude: coordinate.1,
                        recordedDate: recordedDate,
                        timeZoneMissing: absolute?.timeZoneMissing ?? segmentStart?.timeZoneMissing ?? false
                    ))
                }
            }
            if let activity = segment["activity"] as? [String: Any] {
                if addPoint(&segmentPoints, endTime, activity["end"]) { semanticPointAdded = true }
            }
            if !segmentPoints.isEmpty {
                if semanticPointAdded, let interval = semanticInterval(startTime, endTime) {
                    semanticIntervals.append(interval)
                }
                parsedSegments.append(ParsedSegment(
                    anchor: parseInstant(startTime)?.instant ?? segmentPoints[0].instant,
                    points: segmentPoints,
                    standalonePath: hasPath && !semanticPointAdded
                ))
            }
        }

        let coverage = mergeIntervals(semanticIntervals)
        let points = normalizeSegmentDirection(parsedSegments).flatMap { segment -> [GeoPoint] in
            segment.standalonePath ? segment.points.filter { !isCovered($0, coverage) } : segment.points
        }

        var unique: [String: GeoPoint] = [:]
        var order: [String] = []
        for point in points {
            let key = "\(Int(point.instant.timeIntervalSince1970 * 1000)):\(point.latitude):\(point.longitude)"
            if unique[key] == nil { order.append(key) }
            unique[key] = point
        }
        var deduplicated = order.map { unique[$0]! }
        if !deduplicated.contains(where: { $0.timeZoneMissing }) {
            deduplicated.sort { $0.instant < $1.instant }
        }
        guard !deduplicated.isEmpty else {
            throw TimelineParseError(reason: .noUsableLocations, message: "This Timeline export contains no usable location points.")
        }
        return deduplicated
    }

    // MARK: range selection

    static func monthKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    static func localDateKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func pointDateKey(_ point: GeoPoint) -> String {
        point.recordedDate ?? localDateKey(point.instant)
    }

    private static func pointMonthKey(_ point: GeoPoint) -> String {
        String(pointDateKey(point).prefix(7))
    }

    static func availableMonths(_ points: [GeoPoint]) -> [MonthOption] {
        let keys = Set(points.map(pointMonthKey)).sorted()
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return keys.compactMap { key in
            let parts = key.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
            var components = DateComponents()
            components.year = year; components.month = month; components.day = 1
            guard let date = Calendar.current.date(from: components) else { return nil }
            return MonthOption(key: key, label: formatter.string(from: date))
        }
    }

    static func selectRange(_ points: [GeoPoint], startMonth: String, endMonth: String) -> [GeoPoint] {
        points.filter { let key = pointMonthKey($0); return key >= startMonth && key <= endMonth }
    }

    static func selectDateRange(_ points: [GeoPoint], startDate: String, endDate: String) -> [GeoPoint] {
        points.filter { let key = pointDateKey($0); return key >= startDate && key <= endDate }
    }
}
