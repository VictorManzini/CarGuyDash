import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct SupportedSensorsTests {
    private func connect() async -> (BluetoothScanner, SimulatedAdapter) {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        return (scanner, simulated)
    }

    /// A new connection, which discovers the supported PIDs again.
    private func reconnect(_ scanner: BluetoothScanner) async throws {
        scanner.disconnect()
        scanner.connect()
        let start = ContinuousClock.now
        while !scanner.isReady && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(scanner.isReady)
    }

    /// Polls until one full cycle has been read (the last sensor has a value; 5 s at most), then stops and waits for the loop to end.
    private func pollOneCycle(_ scanner: BluetoothScanner) async throws {
        while scanner.isPolling { try await Task.sleep(for: .milliseconds(20)) } // the previous loop is still ending
        let last = try #require(scanner.sensorsToPoll.last)
        scanner.liveData.clear()
        scanner.startPolling()
        let start = ContinuousClock.now
        while scanner.liveData.readings[last] == nil && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        scanner.stopPolling()
        while scanner.isPolling { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// The last value read, however old (the loop has ended, so "N/A for being old" is not what is tested).
    private func lastValue(_ scanner: BluetoothScanner, _ sensor: Sensor) -> Double? {
        scanner.liveData.readings[sensor]?.value
    }

    @Test func realMasksGiveTheListInTheDocs() async {
        let (scanner, simulated) = await connect()
        // The second ECU also answers (with zeros); only the engine ECU counts.
        #expect(scanner.supportedPIDs == SupportedPIDsTests.docList)
        #expect(scanner.sensorsToPoll == BluetoothScanner.polledSensors)
        // Blocks asked in order, once each, and no further than the last bit allows.
        let asked = simulated.received.filter { ["0100\r", "0120\r", "0140\r", "0160\r", "0180\r"].contains($0) }
        #expect(asked == ["0100\r", "0120\r", "0140\r", "0160\r"])
    }

    @Test func discoveryFailureKeepsTheFixedList() async throws {
        let (scanner, simulated) = await connect()
        simulated.answersSupportedPIDs = false
        try await reconnect(scanner) // ready, not stuck
        #expect(scanner.supportedPIDs == nil)
        #expect(scanner.sensorsToPoll == BluetoothScanner.polledSensors)

        try await pollOneCycle(scanner)
        #expect(lastValue(scanner, .oilTemp) == 67)
    }

    @Test func aSensorTheCarLacksIsNeverAsked() async throws {
        let (scanner, simulated) = await connect()
        simulated.supportMasks["40"] = [0xFE, 0xD0, 0x84, 0x01] // the 0x11 loses the bit of PID 5C (oil)
        try await reconnect(scanner)
        #expect(scanner.supportedPIDs?.contains(0x5C) == false)
        #expect(!scanner.sensorsToPoll.contains(.oilTemp))

        let before = simulated.received.count
        try await pollOneCycle(scanner)
        let asked = simulated.received.dropFirst(before)
        #expect(!asked.contains("015C\r"))
        #expect(asked.contains("010C\r")) // the others are still read
        #expect(lastValue(scanner, .oilTemp) == nil)
        #expect(lastValue(scanner, .coolantTemp) == 69)
        #expect(gaugeText(for: .oilTemp, state: scanner.state, value: nil) == "N/A")

        // Nothing is saved: the next connection discovers again and the sensor comes back.
        simulated.supportMasks["40"] = [0xFE, 0xD0, 0x84, 0x11]
        try await reconnect(scanner)
        try await pollOneCycle(scanner)
        #expect(lastValue(scanner, .oilTemp) == 67)
    }

    @Test func aCarWithNoneOfThemDoesNotFreezeTheApp() async throws {
        let (scanner, simulated) = await connect()
        simulated.supportMasks["00"] = [0, 0, 0, 0] // nothing supported, no next block
        try await reconnect(scanner)
        #expect(scanner.sensorsToPoll.isEmpty)

        let before = simulated.received.count
        scanner.startPolling()
        try await Task.sleep(for: .milliseconds(500)) // the test would hang here if the loop never yielded
        scanner.stopPolling()
        #expect(simulated.received.count == before)
    }
}
