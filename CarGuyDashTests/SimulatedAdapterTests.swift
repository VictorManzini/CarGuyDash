import Testing
@testable import CarGuyDash

@MainActor
struct SimulatedAdapterTests {
    /// Scanner talking to the simulated adapter, with NO DATA turned off so results are fixed.
    private func connect() async -> (BluetoothScanner, SimulatedAdapter) {
        let scanner = BluetoothScanner()
        let simulated = await scanner.useSimulatedAdapter()
        simulated.noDataChance = 0
        return (scanner, simulated)
    }

    @Test func sensorsReadTheCarValues() async throws {
        let (scanner, _) = await connect()
        let expected: [(Sensor, Double)] = [
            (.oilTemp, 67), (.coolantTemp, 69), (.manifoldPressure, 93), (.intakeAirTemp, 45),
            (.throttlePosition, 78 * 100 / 255.0),
        ]
        for (sensor, value) in expected {
            let result = try #require(await scanner.run("01" + sensor.rawValue))
            #expect(result.response.contains("7E9"), "\(sensor)")
            #expect(sensor.value(from: result.response) == value, "\(sensor)")
        }
        for _ in 0..<20 {
            let result = try #require(await scanner.run("010C"))
            let rpm = try #require(Sensor.rpm.value(from: result.response))
            #expect((750...3000).contains(rpm))
        }
    }

    @Test func atCommandsAnswer() async throws {
        let (scanner, _) = await connect()
        #expect(try #require(await scanner.run("ATZ")).response.contains("ELM327 v2.3"))
        #expect(try #require(await scanner.run("ATRV")).response.contains("12.4V"))
        #expect(try #require(await scanner.run("ATH1")).response.contains("OK"))
    }

    @Test func noDataGivesNoValue() async throws {
        let (scanner, simulated) = await connect()
        simulated.noDataChance = 1
        let result = try #require(await scanner.run("015C"))
        #expect(result.response.contains("NO DATA"))
        #expect(Sensor.oilTemp.value(from: result.response) == nil)
    }

    @Test func blockedCommandsNeverReachTheSimulator() async {
        let (scanner, simulated) = await connect()
        // Only the setup commands, the VIN request and the supported-PID blocks got there so far.
        let beforeBlocked = (BluetoothScanner.setupCommands + ["0902", "0100", "0120", "0140", "0160"]).map { $0 + "\r" }
        #expect(simulated.received == beforeBlocked)
        for command in ["04", "0400", "ATPP 0C SV 01", "ATSH 7E0", "010C\r04"] {
            #expect(await scanner.run(command) == nil, "\(command.debugDescription)")
        }
        // An allowed command does get there, normalized; none of the blocked ones did.
        _ = await scanner.run("01 0c")
        #expect(simulated.received.dropFirst(beforeBlocked.count) == ["010C\r"])
    }
}
