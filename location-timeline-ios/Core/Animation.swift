import Foundation

/// Playback timing: journey progress 0→1, then a brief outro that blends to the overview.
enum JourneyAnimation {
    static let outroSeconds = 1.5
    static let outroTransitionSeconds = 1.0

    private static func clamp(_ value: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { max(lo, min(hi, value)) }

    static func totalDurationSeconds(_ journeyDurationSeconds: Double) -> Double {
        max(1, journeyDurationSeconds) + outroSeconds
    }

    static func frame(atElapsedSeconds elapsedSeconds: Double, journeyDurationSeconds: Double) -> TimelineFrame {
        let journeySeconds = max(1, journeyDurationSeconds)
        if elapsedSeconds <= journeySeconds {
            return TimelineFrame(journeyProgress: clamp(elapsedSeconds / journeySeconds), outroProgress: 0)
        }
        return TimelineFrame(journeyProgress: 1, outroProgress: clamp((elapsedSeconds - journeySeconds) / outroTransitionSeconds))
    }

    static func frame(atOverallProgress overallProgress: Double, journeyDurationSeconds: Double) -> TimelineFrame {
        frame(atElapsedSeconds: clamp(overallProgress) * totalDurationSeconds(journeyDurationSeconds), journeyDurationSeconds: journeyDurationSeconds)
    }

    static func easeOutCubic(_ value: Double) -> Double {
        let inverse = 1 - clamp(value)
        return 1 - inverse * inverse * inverse
    }

    static func easeInOutCubic(_ value: Double) -> Double {
        let amount = clamp(value)
        if amount < 0.5 { return 4 * amount * amount * amount }
        let inverse = -2 * amount + 2
        return 1 - inverse * inverse * inverse / 2
    }
}
