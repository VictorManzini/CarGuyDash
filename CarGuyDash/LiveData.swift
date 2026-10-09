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
    /// The atmospheric pressure changes slowly and is asked only every 30 s, so it lives longer.
    static let barometricStaleAfter: TimeInterval = 60

    private(set) var readings: [Sensor: Reading] = [:]
    /// The clock. Tests replace it so they do not have to wait for real.
    @ObservationIgnored var now: () -> Date = { .now }

    /// Stores a new value. Nil (no answer) keeps the old one, which turns "N/A" once it is stale.
    func record(_ value: Double?, for sensor: Sensor) {
        guard let value else { return }
        readings[sensor] = Reading(value: value, time: now())
    }

    /// Forgets every value: they all show "N/A".
    func clear() {
        readings = [:]
    }

    /// The value, or nil ("N/A") if there is none or it is too old (`staleAfter`, or `barometricStaleAfter`).
    func value(for sensor: Sensor) -> Double? {
        let limit = sensor == .barometricPressure ? Self.barometricStaleAfter : Self.staleAfter
        guard let reading = readings[sensor], now().timeIntervalSince(reading.time) <= limit else { return nil }
        return reading.value
    }

    /// Turbo pressure in kPa: manifold minus atmospheric. Negative = vacuum.
    /// Nil ("N/A") if either is missing or old: there is never a made-up atmospheric value.
    var boost: Double? {
        guard let manifold = value(for: .manifoldPressure), let atmospheric = value(for: .barometricPressure) else { return nil }
        return manifold - atmospheric
    }
}

/// Polling: reads the sensors one after another, in a loop, until stopped.
extension BluetoothScanner {
    static let polledSensors: [Sensor] = [
        .rpm, .oilTemp, .coolantTemp, .manifoldPressure, .intakeAirTemp, .throttlePosition, .moduleVoltage,
    ]

    /// What polling asks: the Dashboard sensors the car supports, or all of them if discovery failed.
    /// A sensor the car lacks is never asked and stays "N/A".
    var sensorsToPoll: [Sensor] {
        guard let supportedPIDs else { return Self.polledSensors }
        return Self.polledSensors.filter { supportedPIDs.contains(Int($0.rawValue, radix: 16) ?? -1) }
    }

    /// How often the atmospheric pressure (0133) is asked. Once at the start, then this often,
    /// so the other sensors do not slow down.
    static let barometricEvery: TimeInterval = 30

    /// Asks 0133 if it was never asked or the last ask was `barometricEvery` ago. Not asked if the car lacks it.
    /// Not part of the silence check or the readings meter: it only feeds the turbo gauge.
    func pollBarometricPressureIfDue() async {
        let now = liveData.now()
        guard supportedPIDs?.contains(0x33) ?? true,
              baroAskedAt.map({ now.timeIntervalSince($0) >= Self.barometricEvery }) ?? true else { return }
        baroAskedAt = now
        let result = await run("01" + Sensor.barometricPressure.rawValue, timeout: .seconds(1))
        liveData.record(result.flatMap { Sensor.barometricPressure.value(from: $0.response) }, for: .barometricPressure)
    }

    var isPolling: Bool { pollingTask != nil }

    /// Polling is on and Stop was not tapped (`isPolling` stays true while a stopped loop winds down).
    var wantsPolling: Bool { pollingTask?.isCancelled == false }

    func startPolling() {
        guard pollingTask == nil else { return }
        addLog("Start")
        pollingTask = Task {
            addLog("=== Polling started ===")
            meter = ReadingMeter()
            resetSilence()
            baroAskedAt = nil // asked right away at the start
            // Only measures: polling never waits for it. In the background it may fire late; the line says by how much.
            let meterTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: meterInterval)
                    if !Task.isCancelled { addLog(meter.close(in: appPhase)) }
                }
            }
            // Runs until Stop. While the connection is down it waits for the state to change, then reads again once ready.
            while !Task.isCancelled {
                let sensors = sensorsToPoll
                // Also waits when the car supports none of them: without it this loop would never yield.
                // Woken by a state change or by Stop, not by a timer.
                guard isReady, !sensors.isEmpty else {
                    await waitForStateChange()
                    continue
                }
                await pollBarometricPressureIfDue()
                for sensor in sensors where !Task.isCancelled && isReady {
                    // Short timeout: a sensor that does not answer must not hold up the others.
                    let result = await run("01" + sensor.rawValue, timeout: .seconds(1))
                    let value = result.flatMap { sensor.value(from: $0.response) }
                    if value != nil { meter.record() }
                    noteReading(valid: value != nil)
                    liveData.record(value, for: sensor)
                }
            }
            meterTask.cancel()
            resetSilence()
            addLog("=== Polling stopped ===")
            pollingTask = nil
        }
    }

    /// Ends the loop after the command in progress (at most 1 s), or at once if it is waiting.
    func stopPolling() {
        guard let pollingTask, !pollingTask.isCancelled else { return }
        addLog("Stop")
        pollingTask.cancel()
        wakeStateWaiter()
    }
}
