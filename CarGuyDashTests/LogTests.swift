import Foundation
import Testing
@testable import CarGuyDash

@MainActor
struct LogTests {
    private func scanner() async -> BluetoothScanner {
        let scanner = BluetoothScanner(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        await scanner.useSimulatedAdapter()
        return scanner
    }

    @Test func everyLineStartsWithTheTime() async {
        let scanner = await scanner()
        #expect(!scanner.log.isEmpty)
        #expect(scanner.log.allSatisfy { $0.wholeMatch(of: /\d{2}:\d{2}:\d{2}\.\d{3} .+/) != nil })
    }

    @Test func aSimulatedDropLogsTheStateChanges() async throws {
        let scanner = await scanner()
        scanner.simulateDisconnect(for: .milliseconds(200))
        while scanner.state != .ready { try await Task.sleep(for: .milliseconds(20)) }
        let text = scanner.log.joined(separator: "\n")
        #expect(text.contains("State: Ready → Reconnecting"))
        #expect(text.contains("State: Reconnecting → Ready"))
    }

    @Test func tapsAreLoggedAndDisconnectIsOneStateChange() async {
        let scanner = await scanner()
        scanner.startPolling()
        scanner.stopPolling()
        scanner.stopPolling() // second Stop while the loop winds down: not logged again
        scanner.disconnect()
        scanner.connect()
        for tap in ["Start", "Stop", "Disconnect", "Connect"] {
            #expect(scanner.log.filter { $0.hasSuffix(" " + tap) }.count == 1, "\(tap)")
        }
        let text = scanner.log.joined(separator: "\n")
        #expect(text.contains("State: Ready → Disconnected"))
        #expect(!text.contains("Ready → Reconnecting"))
    }

    @Test func carSheetTapsAreLoggedWithoutTheTypedText() async {
        let scanner = await scanner()
        #expect(scanner.needsCarInfo)
        scanner.saveCar(make: "Zzmake", model: "Zzmodel")
        scanner.skipCarInfo() // the sheet closing after Save: not "closed without saving"
        #expect(scanner.log.last?.hasSuffix("Car profile saved") == true)

        let other = await self.scanner()
        other.skipCarInfo()
        #expect(other.log.last?.hasSuffix("Car profile sheet closed without saving") == true)

        let text = (scanner.log + other.log).joined(separator: "\n")
        #expect(!text.contains("Zzmake") && !text.contains("Zzmodel") && !text.contains(SimulatedAdapter.fakeVIN))
    }

    @Test func aRestoreWithoutAnAdapterIsLogged() async {
        let scanner = await scanner()
        scanner.restore([]) // a real CBPeripheral cannot be built in a test
        #expect(scanner.log.last?.hasSuffix("State restored by iOS: no adapter in it") == true)
    }

    /// A scanner like a new process of the app would be: same saved settings, polling off.
    private func relaunched(sharing defaults: UserDefaults) async -> BluetoothScanner {
        let scanner = BluetoothScanner(defaults: defaults)
        await scanner.useSimulatedAdapter()
        return scanner
    }

    @Test func pollingResumesAfterARestoreOnlyIfItWasOnInTheBackground() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        let first = await relaunched(sharing: defaults)
        first.startPolling()
        first.setAppPhase(.background) // saved: polling was on
        first.stopPolling()

        let resumed = await relaunched(sharing: defaults)
        resumed.restore([])
        #expect(resumed.isPolling)
        #expect(resumed.log.contains { $0.hasSuffix("Polling resumed after restore") })
        resumed.setAppPhase(.background)
        resumed.stopPolling()
        resumed.setAppPhase(.active)
        resumed.setAppPhase(.background) // saved again, now with polling off

        let notResumed = await relaunched(sharing: defaults)
        notResumed.restore([])
        #expect(!notResumed.isPolling)
        #expect(!notResumed.log.contains { $0.hasSuffix("Polling resumed after restore") })
    }
}
