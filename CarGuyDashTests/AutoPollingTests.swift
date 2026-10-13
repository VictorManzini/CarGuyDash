import Foundation
import Testing
@testable import CarGuyDash

/// The real adapter starts polling by itself at Ready. The simulated adapter acts like it with `pollsWhenReady: true`.
@MainActor
struct AutoPollingTests {
    /// Waits until `condition` is true or 5 s pass; returns the condition.
    private func wait(until condition: () -> Bool) async throws -> Bool {
        let start = ContinuousClock.now
        while !condition() && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func scanner(pollsWhenReady: Bool = true) async -> (BluetoothScanner, SimulatedAdapter) {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let simulated = await scanner.useSimulatedAdapter(pollsWhenReady: pollsWhenReady)
        simulated.noDataChance = 0
        return (scanner, simulated)
    }

    @Test func pollingStartsAtReadyWithoutStart() async throws {
        let (scanner, _) = await scanner()
        #expect(scanner.isReady)
        #expect(scanner.wantsPolling)
        #expect(try await wait { scanner.liveData.value(for: .rpm) != nil })
        scanner.stopPolling()
    }

    @Test func theSimulatedAdapterStillWaitsForStart() async throws {
        let (scanner, _) = await scanner(pollsWhenReady: false)
        #expect(scanner.isReady)
        #expect(!scanner.isPolling)
    }

    @Test func pollingKeepsGoingAfterADrop() async throws {
        let (scanner, _) = await scanner()
        scanner.simulateDisconnect(for: .milliseconds(200))
        #expect(try await wait { scanner.isReady })
        #expect(scanner.wantsPolling)
        #expect(scanner.log.filter { $0.hasSuffix("=== Polling started ===") }.count == 1) // the same loop, never restarted
        scanner.stopPolling()
    }

    @Test func disconnectStopsPollingAndConnectStartsItAgain() async throws {
        let (scanner, simulated) = await scanner()
        scanner.disconnect()
        #expect(try await wait { !scanner.isPolling })
        let sent = simulated.received.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(simulated.received.count == sent)

        scanner.connect() // a new connection
        #expect(try await wait { scanner.isReady && scanner.wantsPolling })
        scanner.stopPolling()
    }

    @Test func aManualStopStaysStoppedThroughADrop() async throws {
        let (scanner, simulated) = await scanner()
        scanner.stopPolling()
        #expect(try await wait { !scanner.isPolling })

        scanner.simulateDisconnect(for: .milliseconds(200))
        #expect(try await wait { scanner.isReady })
        let sent = simulated.received.count
        try await Task.sleep(for: .milliseconds(300))
        #expect(!scanner.isPolling)
        #expect(simulated.received.count == sent)

        scanner.startPolling() // Start brings it back
        #expect(scanner.wantsPolling)
        scanner.stopPolling()
    }

    /// Test B runs for 20 s.
    @Test(arguments: ["A", "B"]) func aTestPausesPollingAndResumesIt(test: String) async throws {
        let (scanner, _) = await scanner()
        #expect(try await wait { scanner.liveData.value(for: .rpm) != nil }) // a command is in progress
        if test == "A" { await scanner.runTestA() } else { await scanner.runTestB() }

        #expect(scanner.wantsPolling)
        #expect(!scanner.isTesting)
        let log = scanner.log
        #expect(!log.contains { $0.contains("Busy, not sent") })
        // Polling ended before the test began and started again after it finished.
        let stopped = try #require(log.firstIndex { $0.hasSuffix("=== Polling stopped ===") })
        let began = try #require(log.firstIndex { $0.contains("=== Test \(test)") })
        let finished = try #require(log.firstIndex { $0.hasSuffix("=== Test \(test) finished ===") })
        let restarted = try #require(log.lastIndex { $0.hasSuffix(" Start") }) // the loop logs its own line a moment later
        #expect(stopped < began && finished < restarted)
        scanner.stopPolling()
    }

    @Test func aTestLeavesStoppedPollingStopped() async {
        let (scanner, _) = await scanner(pollsWhenReady: false)
        await scanner.runTestA()
        #expect(!scanner.isPolling)
    }
}
