import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct ReadingMeterTests {
    @Test func theLineHasTheRealSecondsPhaseAndCount() {
        let start = ContinuousClock.now
        var meter = ReadingMeter(now: start)
        for _ in 0..<128 { meter.record() }
        #expect(meter.close(in: .background, at: start + .seconds(10)) == "10 s, background: 128 readings")

        // The next window starts empty, and a late timer shows its real length.
        meter.record()
        #expect(meter.close(in: .active, at: start + .seconds(24)) == "14 s, active: 1 readings")
    }

    private func scanner() async -> BluetoothScanner {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await scanner.useSimulatedAdapter()
        return scanner
    }

    @Test func goingToTheBackgroundAndBackIsLogged() async {
        let scanner = await scanner()
        scanner.setAppPhase(.active) // already active: nothing to log
        scanner.setAppPhase(.background)
        scanner.setAppPhase(.background)
        scanner.setAppPhase(.active)
        let text = scanner.log.joined(separator: "\n")
        #expect(text.components(separatedBy: "App went to the background").count == 2)
        #expect(text.components(separatedBy: "App back in the foreground").count == 2)
    }

    @Test func pollingWritesMeasurementLinesAndAPhaseChangeClosesTheWindow() async throws {
        let scanner = await scanner()
        scanner.meterInterval = .milliseconds(200)
        scanner.startPolling()
        let line = /\d+ s, background: [1-9]\d* readings/
        let start = ContinuousClock.now
        while !scanner.log.contains(where: { $0.contains(/\d+ s, active: [1-9]\d* readings/) })
                && ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(scanner.log.contains { $0.contains(/\d+ s, active: [1-9]\d* readings/) })

        scanner.setAppPhase(.background) // closes the window under "active"
        try await Task.sleep(for: .milliseconds(500))
        scanner.stopPolling()
        #expect(scanner.log.contains { $0.contains(line) })
    }
}
