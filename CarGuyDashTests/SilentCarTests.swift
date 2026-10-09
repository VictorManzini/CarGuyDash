import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct SilentCarTests {
    /// Polling the simulated adapter with a short silence limit (so the tests do not wait 2 s).
    private func polling() async -> (BluetoothScanner, SimulatedAdapter) {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        scanner.silenceAfter = .milliseconds(300)
        scanner.startPolling()
        return (scanner, simulated)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let start = ContinuousClock.now
        while !condition() && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func text(_ scanner: BluetoothScanner, _ sensor: Sensor) -> String {
        gaugeText(for: sensor, state: scanner.state, value: scanner.liveData.value(for: sensor), silent: scanner.carSilent)
    }

    @Test func theLimitIsTwoSeconds() {
        #expect(BluetoothScanner().silenceAfter == .seconds(2))
    }

    @Test func noAnswerAtAllIsSilenceAndAnAnswerBringsItBack() async throws {
        let (scanner, simulated) = await polling()
        try await wait { scanner.liveData.value(for: .rpm) != nil }
        #expect(!scanner.carSilent)
        #expect(scanner.statusText == "Ready")

        simulated.noDataChance = 1
        try await wait { scanner.carSilent }
        #expect(scanner.carSilent)
        #expect(scanner.state == .ready) // the Bluetooth connection is untouched
        #expect(scanner.statusText == "Ignition off?")
        for sensor in BluetoothScanner.polledSensors { #expect(text(scanner, sensor) == "Stand By", "\(sensor)") }
        let asked = simulated.received.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(simulated.received.count > asked) // polling keeps asking

        simulated.noDataChance = 0
        try await wait { !scanner.carSilent }
        try await wait { scanner.liveData.value(for: .rpm) != nil }
        scanner.stopPolling()
        #expect(!scanner.carSilent)
        #expect(scanner.statusText == "Ready")
        #expect(text(scanner, .rpm) != "Stand By" && text(scanner, .rpm) != "N/A")

        let log = scanner.log.joined(separator: "\n")
        #expect(log.contains("Car silent (no readings for 2 s)"))
        #expect(log.contains("Car answering again"))
    }

    @Test func oneSensorWithoutAnswerIsOnlyNA() async throws {
        let (scanner, simulated) = await polling()
        simulated.silentPIDs = ["5C"] // oil temperature
        try await wait { scanner.liveData.value(for: .coolantTemp) != nil }
        try await Task.sleep(for: .milliseconds(800)) // well past the silence limit
        scanner.stopPolling()
        #expect(!scanner.carSilent)
        #expect(scanner.statusText == "Ready")
        #expect(text(scanner, .oilTemp) == "N/A")
        #expect(text(scanner, .coolantTemp) == "69")
        #expect(!scanner.log.joined(separator: "\n").contains("Car silent"))
    }
}
