import Foundation
import Observation

/// Latest value of each sensor and when it arrived. Views observe it.
@Observable
final class LiveData {
    struct Reading {
        let value: Double
        let time: Date
    }

    /// A value older than this counts as "N/A".
    static let staleAfter: TimeInterval = 2

    private(set) var readings: [Sensor: Reading] = [:]
    /// The clock. Tests replace it so they do not have to wait for real.
    @ObservationIgnored var now: () -> Date = { .now }

    /// Stores a new value. Nil (no answer) keeps the old one, which turns "N/A" once it is stale.
    func record(_ value: Double?, for sensor: Sensor) {
        guard let value else { return }
        readings[sensor] = Reading(value: value, time: now())
    }

    /// The value, or nil ("N/A") if there is none or it is older than `staleAfter`.
    func value(for sensor: Sensor) -> Double? {
        guard let reading = readings[sensor], now().timeIntervalSince(reading.time) <= Self.staleAfter else { return nil }
        return reading.value
    }
}
