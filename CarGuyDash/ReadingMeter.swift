import Foundation

/// Whether the app is on screen or not, as the measurement lines report it.
enum AppPhase: String {
    case active, background
}

/// Counts valid readings and turns each window into one log line,
/// e.g. "10 s, background: 128 readings, RPM 4.9/s, 102 ms/command".
/// The seconds are the real time of the window, so a timer that fires late in the background shows up as 14 s, not 10 s.
struct ReadingMeter {
    private(set) var count = 0
    private var rpmCount = 0
    /// Polling commands that got an answer, and their total time.
    private var commands = 0
    private var totalMs = 0
    private var windowStart: ContinuousClock.Instant

    init(now: ContinuousClock.Instant = .now) {
        windowStart = now
    }

    /// One valid reading of `sensor`.
    mutating func record(_ sensor: Sensor) {
        count += 1
        if sensor == .rpm { rpmCount += 1 }
    }

    /// One polling command that got an answer (valid or not) after `ms`.
    mutating func time(_ ms: Int) {
        commands += 1
        totalMs += ms
    }

    /// Ends the window: returns its line and starts the next one.
    mutating func close(in phase: AppPhase, at now: ContinuousClock.Instant = .now) -> String {
        let real = (now - windowStart) / .seconds(1)
        let rpmPerSecond = real > 0 ? Double(rpmCount) / real : 0
        let ms = commands > 0 ? totalMs / commands : 0
        let line = "\(Int(real.rounded())) s, \(phase.rawValue): \(count) readings, "
            + "RPM \(String(format: "%.1f", rpmPerSecond))/s, \(ms) ms/command"
        count = 0
        rpmCount = 0
        commands = 0
        totalMs = 0
        windowStart = now
        return line
    }
}
