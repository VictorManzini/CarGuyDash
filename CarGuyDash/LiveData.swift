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

/// Polling: reads the sensors one after another, in a loop, until stopped.
extension BluetoothScanner {
    static let polledSensors: [Sensor] = [
        .rpm, .oilTemp, .coolantTemp, .manifoldPressure, .intakeAirTemp, .throttlePosition, .moduleVoltage,
    ]

    var isPolling: Bool { pollingTask != nil }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            addLog("=== Polling started ===")
            for command in Self.setupCommands { _ = await run(command) }
            // Stops on Stop or when the adapter disconnects (otherwise it would spin, logging "Not connected").
            while !Task.isCancelled && isReady {
                for sensor in Self.polledSensors where !Task.isCancelled {
                    // Short timeout: a sensor that does not answer must not hold up the others.
                    let result = await run("01" + sensor.rawValue, timeout: .seconds(1))
                    liveData.record(result.flatMap { sensor.value(from: $0.response) }, for: sensor)
                }
            }
            addLog("=== Polling stopped ===")
            pollingTask = nil
        }
    }

    /// Ends the loop after the command in progress (at most 1 s).
    func stopPolling() {
        pollingTask?.cancel()
    }
}
