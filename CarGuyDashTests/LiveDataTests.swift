import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct LiveDataTests {
    @Test func oldValueBecomesNA() {
        let liveData = LiveData()
        var clock = Date(timeIntervalSince1970: 0)
        liveData.now = { clock }

        #expect(liveData.value(for: .oilTemp) == nil) // never read
        liveData.record(67, for: .oilTemp)
        clock += 2
        #expect(liveData.value(for: .oilTemp) == 67) // exactly 2 s: still valid
        clock += 0.1
        #expect(liveData.value(for: .oilTemp) == nil) // more than 2 s: N/A

        // No answer (nil) does not refresh the time.
        liveData.record(nil, for: .oilTemp)
        #expect(liveData.value(for: .oilTemp) == nil)
        liveData.record(68, for: .oilTemp)
        #expect(liveData.value(for: .oilTemp) == 68)
    }

    /// Polls the simulated adapter until `done` is true or 5 s pass.
    private func poll(noDataChance: Double, until done: (BluetoothScanner, SimulatedAdapter) -> Bool) async throws -> BluetoothScanner {
        let scanner = BluetoothScanner()
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = noDataChance
        scanner.startPolling()
        let start = ContinuousClock.now
        while !done(scanner, simulated) && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(50))
        }
        scanner.stopPolling()
        return scanner
    }

    @Test func pollingFillsEverySensor() async throws {
        let scanner = try await poll(noDataChance: 0) { scanner, _ in
            BluetoothScanner.polledSensors.allSatisfy { scanner.liveData.value(for: $0) != nil }
        }
        let liveData = scanner.liveData
        #expect(liveData.value(for: .oilTemp) == 67)
        #expect(liveData.value(for: .coolantTemp) == 69)
        #expect((88...190).contains(try #require(liveData.value(for: .manifoldPressure)))) // follows the RPM
        #expect(liveData.value(for: .intakeAirTemp) == 45)
        #expect(liveData.value(for: .throttlePosition) == 78 * 100 / 255.0)
        #expect(liveData.value(for: .moduleVoltage) == 14.1)
        #expect((750...3000).contains(try #require(liveData.value(for: .rpm))))
    }

    @Test func noDataLeavesEverySensorNA() async throws {
        // Wait until the last sensor of the cycle was asked for.
        let scanner = try await poll(noDataChance: 1) { _, simulated in simulated.received.contains("0142\r") }
        for sensor in BluetoothScanner.polledSensors {
            #expect(scanner.liveData.value(for: sensor) == nil, "\(sensor)")
        }
    }

    @Test func pollingStops() async throws {
        let scanner = try await poll(noDataChance: 0) { scanner, _ in scanner.liveData.value(for: .rpm) != nil }
        let start = ContinuousClock.now
        while scanner.isPolling && ContinuousClock.now - start < .seconds(2) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!scanner.isPolling)
    }

    /// Gives the main actor a few turns, far less than the old 200 ms timer, and no real time to wait.
    private func letTheLoopRun() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func waitingForAStateChangeNeedsNoTimer() async {
        let scanner = BluetoothScanner()
        var woke = false
        let waiter = Task { await scanner.waitForStateChange(); woke = true }
        await letTheLoopRun()
        #expect(!woke) // nothing changed, so it keeps waiting
        scanner.wakeStateWaiter()
        await waiter.value // returns by itself: no clock involved
        #expect(woke)
    }

    @Test func stopEndsTheLoopWhileItWaitsForReady() async {
        let scanner = BluetoothScanner()
        await scanner.useSimulatedAdapter()
        scanner.disconnect()
        scanner.startPolling()
        await letTheLoopRun() // now waiting, since the state is Disconnected
        scanner.stopPolling()
        await letTheLoopRun()
        #expect(!scanner.isPolling)
    }

    @Test func theLoopReadsAgainAsSoonAsTheStateIsReady() async throws {
        let scanner = BluetoothScanner()
        let simulated = await scanner.useSimulatedAdapter()
        scanner.disconnect()
        scanner.startPolling()
        await letTheLoopRun()
        let asked = simulated.received.count
        scanner.connect()
        let start = ContinuousClock.now
        while scanner.liveData.value(for: .rpm) == nil && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        scanner.stopPolling()
        #expect(scanner.liveData.value(for: .rpm) != nil)
        #expect(simulated.received.count > asked)
    }
}
