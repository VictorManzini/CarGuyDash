import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct BoostTests {
    private func liveData(manifold: Double?, atmospheric: Double?) -> LiveData {
        let liveData = LiveData()
        liveData.record(manifold, for: .manifoldPressure)
        liveData.record(atmospheric, for: .barometricPressure)
        return liveData
    }

    /// The Dashboard text: boost goes through the same gaugeText as the manifold block.
    private func text(_ liveData: LiveData, _ units: Units = Units()) -> String {
        gaugeText(for: .manifoldPressure, state: .ready, value: liveData.boost, units: units)
    }

    @Test func boostIsManifoldMinusAtmospheric() {
        #expect(text(liveData(manifold: 93, atmospheric: 93)) == "0.00")
        #expect(text(liveData(manifold: 193, atmospheric: 93)) == "1.00")
        #expect(text(liveData(manifold: 193, atmospheric: 93), Units(pressure: .psi)) == "14.5")
        #expect(text(liveData(manifold: 193, atmospheric: 93), Units(pressure: .kPa)) == "100")
        #expect(text(liveData(manifold: 50, atmospheric: 93)) == "-0.43") // vacuum
    }

    @Test func withoutAtmosphericOrManifoldItIsNA() {
        #expect(text(liveData(manifold: 193, atmospheric: nil)) == "N/A")
        #expect(text(liveData(manifold: nil, atmospheric: 93)) == "N/A")
    }

    @Test func atmosphericLivesSixtySecondsAndManifoldTwo() {
        let data = LiveData()
        var clock = Date(timeIntervalSince1970: 0)
        data.now = { clock }
        data.record(93, for: .barometricPressure)
        data.record(193, for: .manifoldPressure)
        clock += 2
        #expect(data.boost == 100)
        clock += 58 // atmospheric is exactly 60 s old
        data.record(193, for: .manifoldPressure) // the manifold is read all the time, so it is fresh
        #expect(data.boost == 100)
        clock += 0.1 // older than 60 s: no invented default, N/A
        data.record(193, for: .manifoldPressure)
        #expect(data.boost == nil)
    }

    @Test func standByAndNAStillApplyToBoost() {
        let data = liveData(manifold: 193, atmospheric: 93)
        #expect(gaugeText(for: .manifoldPressure, state: .reconnecting, value: data.boost) == "Stand By")
        #expect(gaugeText(for: .manifoldPressure, state: .ready, value: data.boost, silent: true) == "Stand By")
        #expect(gaugeText(for: .manifoldPressure, state: .disconnected, value: data.boost) == "N/A")
    }

    @Test func theSimulatedCarAnswers0133With93() async throws {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        await scanner.pollBarometricPressureIfDue()
        #expect(scanner.liveData.value(for: .barometricPressure) == 93)
    }

    @Test func atmosphericIsAskedAtTheStartThenEvery30Seconds() async {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        var clock = Date(timeIntervalSince1970: 0)
        scanner.liveData.now = { clock }
        func asked() -> Int { simulated.received.filter { $0 == "0133\r" }.count }

        await scanner.pollBarometricPressureIfDue()
        #expect(asked() == 1)
        await scanner.pollBarometricPressureIfDue() // same loop turn
        clock += 29.9
        await scanner.pollBarometricPressureIfDue()
        #expect(asked() == 1)
        clock += 0.1
        await scanner.pollBarometricPressureIfDue()
        #expect(asked() == 2)
    }

    @Test func pollingAsksAtmosphericOnceNotOnEveryLap() async throws {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        scanner.startPolling()
        let start = ContinuousClock.now
        // The last sensor of the cycle (0142) asked 3 times = 3 laps.
        while simulated.received.filter({ $0 == "0142\r" }).count < 3 && ContinuousClock.now - start < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        scanner.stopPolling()
        #expect(simulated.received.filter { $0 == "0142\r" }.count >= 3)
        #expect(simulated.received.filter { $0 == "0133\r" }.count == 1)
        // Asked before the first Dashboard sensor (RPM).
        let order = simulated.received
        #expect(try #require(order.firstIndex(of: "0133\r")) < (try #require(order.firstIndex(of: "010C\r"))))
        #expect(scanner.liveData.boost == 0) // simulated car: 93 - 93
    }
}
