import Testing
@testable import CarGuyDash

@MainActor
struct ReconnectTests {
    /// Waits until `condition` is true or 5 s pass; returns the condition.
    private func wait(until condition: () -> Bool) async throws -> Bool {
        let start = ContinuousClock.now
        while !condition() && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Simulated adapter, polling, every sensor read at least once.
    private func pollingScanner() async throws -> (BluetoothScanner, SimulatedAdapter) {
        let scanner = BluetoothScanner()
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        scanner.startPolling()
        #expect(try await wait { BluetoothScanner.polledSensors.allSatisfy { scanner.liveData.value(for: $0) != nil } })
        return (scanner, simulated)
    }

    private func allNA(_ scanner: BluetoothScanner) -> Bool {
        BluetoothScanner.polledSensors.allSatisfy { scanner.liveData.value(for: $0) == nil }
    }

    @Test func pollingResumesAfterADrop() async throws {
        let (scanner, simulated) = try await pollingScanner()

        scanner.simulateDisconnect(for: .milliseconds(500))
        #expect(scanner.state == .reconnecting)
        #expect(allNA(scanner))

        #expect(try await wait { scanner.state == .ready })
        // The setup commands were sent again after the drop.
        #expect(simulated.received.filter { $0 == "ATH1\r" }.count == 2)
        #expect(try await wait { scanner.liveData.value(for: .oilTemp) == 67 })
        #expect(scanner.isPolling)
        scanner.stopPolling()
    }

    @Test func stopDuringADropKeepsItStopped() async throws {
        let (scanner, simulated) = try await pollingScanner()

        scanner.simulateDisconnect(for: .milliseconds(500))
        scanner.stopPolling()
        #expect(try await wait { scanner.state == .ready })
        #expect(try await wait { !scanner.isPolling })

        // Connected again, but nothing is read any more.
        let sent = simulated.received.count
        try await Task.sleep(for: .milliseconds(500))
        #expect(simulated.received.count == sent)
        #expect(allNA(scanner))
    }
}
