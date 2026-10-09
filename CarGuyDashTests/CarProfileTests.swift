import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct CarProfileTests {
    /// A scanner on the simulated adapter (fake VIN) with its own throwaway saved cars.
    private func scanner(suite: String = UUID().uuidString) async -> BluetoothScanner {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        return scanner
    }

    private func waitReady(_ scanner: BluetoothScanner) async throws {
        let start = ContinuousClock.now
        while !scanner.isReady && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func newVINAsksForMakeAndModel() async {
        let scanner = await scanner()
        #expect(scanner.isReady)
        #expect(scanner.vin == SimulatedAdapter.fakeVIN)
        #expect(scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")

        scanner.saveCar(make: " BMW ", model: "M135i")
        #expect(!scanner.needsCarInfo)
        #expect(scanner.carName == "BMW M135i")
    }

    @Test func blankMakeOrModelIsNotSaved() async {
        let scanner = await scanner()
        scanner.saveCar(make: "BMW", model: "  ")
        scanner.saveCar(make: "", model: "M135i")
        #expect(scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")
    }

    @Test func knownVINDoesNotAsk() async {
        let suite = UUID().uuidString
        let first = await scanner(suite: suite)
        first.saveCar(make: "BMW", model: "M135i")

        // A new launch of the app with the same saved cars.
        let second = BluetoothScanner(defaults: UserDefaults(suiteName: suite)!)
        await second.useSimulatedAdapter()
        #expect(!second.needsCarInfo)
        #expect(second.carName == "BMW M135i")
    }

    @Test func skippingKeepsItUnknownAndAsksAgainNextConnection() async throws {
        let scanner = await scanner()
        scanner.skipCarInfo()
        #expect(!scanner.needsCarInfo)
        #expect(scanner.carName == "Unknown car")

        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(scanner.needsCarInfo)
    }

    @Test func noVINMeansUnknownCarAndReadingContinues() async throws {
        let scanner = await scanner()
        let simulated = try #require(scanner.simulator)
        scanner.saveCar(make: "BMW", model: "M135i")
        simulated.noDataChance = 0

        // Next connection the car does not answer 0902.
        simulated.answersVIN = false
        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(scanner.vin == nil)
        #expect(scanner.carName == "Unknown car")
        #expect(!scanner.needsCarInfo) // nothing to ask without a VIN

        // Still reads normally.
        scanner.startPolling()
        let start = ContinuousClock.now
        while scanner.liveData.value(for: .oilTemp) == nil && ContinuousClock.now - start < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
        scanner.stopPolling()
        #expect(scanner.liveData.value(for: .oilTemp) == 67)
    }

    @Test func theVINRequestPassesTheGatekeeperOncePerConnection() async throws {
        let scanner = await scanner()
        let simulated = try #require(scanner.simulator)
        #expect(Gatekeeper.check("0902") == .allowed)
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        // It comes right after the setup commands, then the supported-PID blocks.
        #expect(simulated.received == (BluetoothScanner.setupCommands + ["0902", "0100", "0120", "0140", "0160"]).map { $0 + "\r" })

        // Polling does not ask again; a new connection does.
        simulated.noDataChance = 0
        scanner.startPolling()
        try await Task.sleep(for: .milliseconds(500))
        scanner.stopPolling()
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        scanner.disconnect()
        scanner.connect()
        try await waitReady(scanner)
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 2)
    }
}

@MainActor
struct VINStaysOutOfTheLogTests {
    // Hex of the fake VIN's first bytes ("TES"), as they would appear in a log line.
    private let fakeVINHex = "544553"

    @Test func testADoesNotAskForTheVIN() async {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        let asked = simulated.received.count
        await scanner.runTestA()
        // Only the VIN request made when connecting; none from the test.
        #expect(simulated.received.filter { $0 == "0902\r" }.count == 1)
        #expect(simulated.received.count > asked)
        #expect(!scanner.log.contains { $0.contains("0902") || $0.contains(fakeVINHex) || $0.contains(SimulatedAdapter.fakeVIN) })
    }

    @Test func aLateVINAnswerIsHidden() async {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await scanner.useSimulatedAdapter()
        scanner.receive("7E81014490201544553\r7E8215456494E303030\r7E82230303030303031\r\r>") // nobody is waiting for it
        #expect(scanner.log.last?.contains("Late response") == true)
        #expect(!scanner.log.contains { $0.contains(fakeVINHex) })
    }
}
