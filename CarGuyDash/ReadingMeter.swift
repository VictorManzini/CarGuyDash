import Foundation

/// Whether the app is on screen or not, as the measurement lines report it.
enum AppPhase: String {
    case active, background
}

/// Counts valid readings and turns each window into one log line, e.g. "10 s, background: 128 readings".
/// The seconds are the real time of the window, so a timer that fires late in the background shows up as 14 s, not 10 s.
struct ReadingMeter {
    private(set) var count = 0
    private var windowStart: ContinuousClock.Instant

    init(now: ContinuousClock.Instant = .now) {
        windowStart = now
    }

    mutating func record() {
        count += 1
    }

    /// Ends the window: returns its line and starts the next one.
    mutating func close(in phase: AppPhase, at now: ContinuousClock.Instant = .now) -> String {
        let seconds = Int(((now - windowStart) / .seconds(1)).rounded())
        let line = "\(seconds) s, \(phase.rawValue): \(count) readings"
        count = 0
        windowStart = now
        return line
    }
}
