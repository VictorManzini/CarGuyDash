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

    @Test func rpmIsAskedEveryOtherRequest() {
        let order = BluetoothScanner.pollOrder([.coolantTemp, .rpm, .oilTemp, .manifoldPressure])
        #expect(order == [.rpm, .coolantTemp, .rpm, .oilTemp, .rpm, .manifoldPressure])
        // Without RPM, or with RPM alone, nothing changes.
        #expect(BluetoothScanner.pollOrder([.coolantTemp, .oilTemp]) == [.coolantTemp, .oilTemp])
        #expect(BluetoothScanner.pollOrder([.rpm]) == [.rpm])
    }

    /// Polls the simulated adapter until `done` is true or 5 s pass.
    private func poll(noDataChance: Double, until done: (BluetoothScanner, SimulatedAdapter) -> Bool) async throws -> BluetoothScanner {
        // Own storage: the default gauge layout, whatever the simulator has saved.
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
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
            scanner.sensorsToPoll.allSatisfy { scanner.liveData.value(for: $0) != nil }
        }
        let liveData = scanner.liveData
        #expect(liveData.value(for: .oilTemp) == 67)
        #expect(liveData.value(for: .coolantTemp) == 69)
        #expect((88...190).contains(try #require(liveData.value(for: .manifoldPressure)))) // follows the RPM
        #expect(liveData.value(for: .intakeAirTemp) == 45)
        #expect(liveData.value(for: .throttlePosition) == nil) // no gauge shows it, so it is not asked
        #expect(liveData.value(for: .moduleVoltage) == 14.1)
        #expect((750...3000).contains(try #require(liveData.value(for: .rpm))))
    }

    @Test func noDataLeavesEverySensorNA() async throws {
        // Wait until the last sensor of the cycle was asked for.
        let scanner = try await poll(noDataChance: 1) { _, simulated in simulated.received.contains("0142\r") }
        for sensor in scanner.sensorsToPoll {
            #expect(scanner.liveData.value(for: sensor) == nil, "\(sensor)")
        }
    }

    @Test func unreadableAnswersAreLoggedRawAtMostEvery10Seconds() {
        let scanner = BluetoothScanner()
        var clock = Date(timeIntervalSince1970: 0)
        scanner.liveData.now = { clock }
        func lines() -> [String] { scanner.log.filter { $0.contains("No value from") } }

        scanner.logUnreadable("NO DATA\r\r>", for: .rpm)
        #expect(lines().last?.hasSuffix(#"No value from 010C: "NO DATA\r\r>""#) == true)
        clock += 9
        scanner.logUnreadable("NO DATA\r\r>", for: .rpm)
        #expect(lines().count == 1) // same sensor within 10 s: skipped
        scanner.logUnreadable("?\r\r>", for: .oilTemp)
        #expect(lines().count == 2) // another sensor has its own 10 s
        clock += 1
        scanner.logUnreadable("NO DATA\r\r>", for: .rpm)
        #expect(lines().count == 3)
        clock += 10
        scanner.logUnreadable("7E81014490201574241\r\r>", for: .rpm)
        #expect(lines().count == 3) // the VIN never reaches the log
        scanner.logUnreadable("7E8 10 14 49 02 01 57 42 41\r\r>", for: .oilTemp) // with spaces too
        #expect(lines().count == 3)
        #expect(!scanner.log.contains { $0.contains("490201") || $0.contains("49 02 01") })
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
